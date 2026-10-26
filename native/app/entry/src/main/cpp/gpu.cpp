// In-process GPU renderer: upstream vtest (gpu/virglrenderer/vtest, patched) on the
// device's own libvirglrenderer, bundled in the HAP. Hyprland's Mesa virpipe
// connects to native/vtest/vtest-broker in the Arch session, which passes the
// connection here. Rendering runs on the Maleoon GPU (Mesa zink, which the system
// EGL loads for processes with NEED_OPENGL=1), and when Hyprland reads a frame back
// the resource is presented straight into this app's window instead: no copy.
#include <hilog/log.h>
#include <native_buffer/buffer_common.h>
#include <native_buffer/native_buffer.h>
#include <native_window/external_window.h>

#include <dlfcn.h>
#include <fcntl.h>
#include <errno.h>
#include <poll.h>
#include <sys/stat.h>
#include <stddef.h>
#include <string.h>
#include <sys/socket.h>
#include <sys/un.h>
#include <pthread.h>
#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>

#include <atomic>
#include <ctime>
#include <map>
#include <string>
#include <cstdint>

#include "gpu.h"

#undef LOG_DOMAIN
#undef LOG_TAG
#define LOG_DOMAIN 0x0D0D
#define LOG_TAG "ohdisp-gpu"
#define LOGI(...) OH_LOG_Print(LOG_APP, LOG_INFO, LOG_DOMAIN, LOG_TAG, __VA_ARGS__)

struct virgl_box {
    uint32_t x, y, z, w, h, d;
};
struct ResourceInfo {
    uint32_t handle, virgl_format, width, height, depth, flags, tex_id, stride;
    int drm_fourcc, fd;
    uint32_t spare[8];  // the system build may have grown it
};

extern "C" {
int vtest_main(int argc, char **argv);
int virgl_renderer_resource_get_info(int res_handle, ResourceInfo *info);
int virgl_renderer_ohos_set_scanout(uint32_t res_id, uint32_t scanout_id);
int virgl_renderer_ohos_present(uint32_t res_id, uint32_t scanout_id);
void OhmarchyHwfSetWindow(OHNativeWindow *window, void (*onUse)(void));
}

namespace {

std::atomic<bool> g_gpuActive{false};
OHNativeWindow *g_window = nullptr;
std::atomic<uint64_t> g_presents{0};
uint32_t g_scanoutRes = 0;
uint32_t g_pendingPresent = 0;  // frame to present when the renderer is idle
pthread_t g_vtestThread;
const char *kBroker = "@ohmarchy-vtest";
// Without root (route J, the desktop runs inside this app): no vtest-broker. The app
// is its own broker then (LocalGpu): it listens on a socket in its files directory
// for Mesa virpipe clients and passes each connection to vtest over kLocalBroker,
// the same way vtest-broker does.
const char *kLocalBroker = "@ohmarchy-vtest-app";
std::atomic<const char *> g_vtestName{kBroker};
std::atomic<bool> g_localGpu{false};
const char *kLog = "/data/storage/el2/base/files/vtest.log";

void OnWindowUse()
{
    LOGI("renderer took the window");
}

// The library presents with eglSwapBuffers at swap interval 1, which waits for the
// display: Hyprland's frame then blocks on vsync and clients fall a frame behind.
// libepoxy's dispatch entries are plain pointers: point eglSwapBuffers at a wrapper
// that sets swap interval 0 on each surface it presents (the system shows the
// latest buffer). The real functions come from the system EGL, as in epoxy.
using SwapBuffersFn = unsigned (*)(void *dpy, void *surface);
using SwapIntervalFn = unsigned (*)(void *dpy, int interval);
SwapBuffersFn g_realSwap = nullptr;
SwapIntervalFn g_swapInterval = nullptr;

unsigned SwapNoWait(void *dpy, void *surface)
{
    static void *intervalSet = nullptr;
    if (surface != intervalSet) {
        g_swapInterval(dpy, 0);
        intervalSet = surface;
    }
    return g_realSwap(dpy, surface);
}

void WrapSwapBuffers()
{
    void *epoxy = dlopen("libepoxy.so", RTLD_NOW | RTLD_NOLOAD);
    void *egl = dlopen("libEGL.so", RTLD_NOW);
    if (epoxy == nullptr || egl == nullptr || getenv("OHMARCHY_PRESENT_VSYNC") != nullptr) {
        return;
    }
    auto *entry = static_cast<SwapBuffersFn *>(dlsym(epoxy, "epoxy_eglSwapBuffers"));
    g_realSwap = reinterpret_cast<SwapBuffersFn>(dlsym(egl, "eglSwapBuffers"));
    g_swapInterval = reinterpret_cast<SwapIntervalFn>(dlsym(egl, "eglSwapInterval"));
    if (entry != nullptr && g_realSwap != nullptr && g_swapInterval != nullptr) {
        *entry = SwapNoWait;
        LOGI("presents do not wait for vsync");
    }
}

void *VtestThread(void *)
{
    char a0[] = "vtest", a1[] = "--no-fork", a2[] = "--multi-clients", a3[] = "--socket-path";
    std::string name = g_vtestName.load();
    char *argv[] = {a0, a1, a2, a3, &name[0], nullptr};
    optind = 1;
    vtest_main(5, argv);
    return nullptr;
}

// vtest reports through stdout and stderr, which go nowhere in an app: forward
// them to hilog, one line each (tag ohdisp-vtest).
void *LogPump(void *arg)
{
    FILE *in = fdopen(static_cast<int>(reinterpret_cast<intptr_t>(arg)), "r");
    char line[512];
    while (in != nullptr && fgets(line, sizeof(line), in) != nullptr) {
        line[strcspn(line, "\n")] = '\0';
        OH_LOG_Print(LOG_APP, LOG_INFO, LOG_DOMAIN, "ohdisp-vtest", "%{public}s", line);
    }
    return nullptr;
}

void StartLogPump()
{
    int fds[2];
    pthread_t t;
    if (pipe(fds) != 0) {
        return;
    }
    dup2(fds[1], 1);
    dup2(fds[1], 2);
    close(fds[1]);
    setvbuf(stdout, nullptr, _IOLBF, 0);
    setvbuf(stderr, nullptr, _IOLBF, 0);
    if (pthread_create(&t, nullptr, LogPump, reinterpret_cast<void *>(static_cast<intptr_t>(fds[0]))) == 0) {
        pthread_detach(t);
    }
}

void *Supervisor(void *)
{
    StartLogPump();
    for (;;) {
        if (pthread_create(&g_vtestThread, nullptr, VtestThread, nullptr) == 0) {
            pthread_join(g_vtestThread, nullptr);
        }
        LOGI("vtest stopped; retrying");
        g_scanoutRes = 0;
        g_pendingPresent = 0;
        sleep(2);
    }
    return nullptr;
}

}  // namespace

// vtest's exit() calls end its thread, not the app (see CMakeLists.txt).
extern "C" __attribute__((noreturn)) void vtest_exit(int code)
{
    fprintf(stderr, "vtest exit %d\n", code);
    pthread_exit(nullptr);
}

void PresentNow(uint32_t res_id)
{
    // Bit 31 on the scanout id is the library's "resize debounce over" flag (the VM
    // sends it from a timer a second after a resolution change); without it every
    // present after a size change keeps showing black.
    static const bool timing = getenv("VTEST_ZC_TIMING") != nullptr;
    static double presentMs = 0;
    static int presentN = 0;
    timespec t0{}, t1{};
    clock_gettime(CLOCK_MONOTONIC, &t0);
    int r = virgl_renderer_ohos_present(res_id, 0x80000000u);
    if (timing) {
        clock_gettime(CLOCK_MONOTONIC, &t1);
        presentMs += (t1.tv_sec - t0.tv_sec) * 1e3 + (t1.tv_nsec - t0.tv_nsec) / 1e6;
        if (++presentN == 120) {
            fprintf(stderr, "present call: %.2f ms avg\n", presentMs / presentN);
            presentMs = 0;
            presentN = 0;
        }
    }
    if (r != 0 || g_presents < 8 || g_presents % 120 == 0) {
        fprintf(stderr, "present #%llu res %u -> %d\n", static_cast<unsigned long long>(g_presents.load()), res_id, r);
    }
    g_presents++;
}

extern "C" bool vtest_present_hook(const char *client, uint32_t res_id, const virgl_box *box)
{
    // Only the compositor's frames go to the window; GPU clients read back their own.
    ResourceInfo info{};
    if (client == nullptr || strcmp(client, "Hyprland") != 0 ||
        virgl_renderer_resource_get_info(static_cast<int>(res_id), &info) != 0 || info.width < 640 ||
        info.height < 400 || box->w == 0) {
        return false;
    }
    // Bind the scanout once per size: re-binding it to each of the compositor's
    // buffers would restart the library's black-screen resize debounce every frame.
    // Presenting takes the resource to show. Also once per compositor: a restarted
    // Hyprland (a new vtest context, so a new debug_name) at the same size would
    // otherwise present through the old one's binding, and the window kept
    // showing the old desktop.
    static uint32_t boundW = 0, boundH = 0;
    static const char *boundClient = nullptr;
    if (g_scanoutRes == 0 || info.width != boundW || info.height != boundH || client != boundClient) {
        if (virgl_renderer_ohos_set_scanout(res_id, 0) != 0) {
            fprintf(stderr, "set_scanout %u failed\n", res_id);
            return false;
        }
        fprintf(stderr, "scanout -> res %u (%ux%u fmt %u)\n", res_id, info.width, info.height, info.virgl_format);
        g_scanoutRes = res_id;
        boundW = info.width;
        boundH = info.height;
        boundClient = client;
    }
    // Present when the renderer has nothing else to do (vtest_idle_hook): a present
    // blocks this thread for about a millisecond, and clients waiting for a reply
    // meanwhile would fall behind. A newer frame shows the pending one first.
    static const bool immediate = getenv("OHMARCHY_PRESENT_IMMEDIATE") != nullptr;
    if (g_pendingPresent != 0) {
        PresentNow(g_pendingPresent);
    }
    g_pendingPresent = res_id;
    if (immediate) {
        PresentNow(res_id);
        g_pendingPresent = 0;
    }
    return true;
}

extern "C" void vtest_idle_hook(void)
{
    if (g_pendingPresent != 0) {
        PresentNow(g_pendingPresent);
        g_pendingPresent = 0;
    }
}

// Command tracing for development: while the file "trace" exists in the app's files
// directory, print per-client counts of transfers and command types every second.
extern "C" void vtest_trace_hook(const char *client, int op, uint32_t res_id, const virgl_box *box,
                                 const uint32_t *cmd, uint32_t length_dw)
{
    static time_t checked = 0, last = 0;
    static bool on = false;
    struct Stats {
        std::map<std::string, uint64_t> n;
    };
    static std::map<std::string, Stats> stats;
    time_t now = time(nullptr);
    if (now != checked) {
        checked = now;
        on = access("/data/storage/el2/base/files/trace", F_OK) == 0;
    }
    if (!on) {
        return;
    }
    Stats &st = stats[client ? client : "?"];
    char key[64];
    if (op < 2) {
        snprintf(key, sizeof(key), "%s %ux%u res%u", op ? "put" : "get", box->w, box->h, res_id);
        st.n[key]++;
    } else {
        for (uint32_t i = 0; i < length_dw;) {
            uint32_t hdr = cmd[i];
            snprintf(key, sizeof(key), "cmd%u/%u", hdr & 0xff, (hdr >> 8) & 0xff);
            st.n[key]++;
            i += 1 + (hdr >> 16);
        }
    }
    if (now != last) {
        last = now;
        for (auto &[c, cs] : stats) {
            std::string line = c + ":";
            for (auto &[k, v] : cs.n) {
                line += " " + k + "=" + std::to_string(v);
            }
            fprintf(stderr, "trace %s\n", line.c_str());
        }
        stats.clear();
    }
}

bool GpuActive() { return g_gpuActive; }
uint64_t GpuPresents() { return g_presents; }

bool BrokerPresent()
{
    int fd = socket(AF_UNIX, SOCK_STREAM | SOCK_CLOEXEC, 0);
    sockaddr_un a{};
    a.sun_family = AF_UNIX;
    const char *name = kBroker + 1;
    memcpy(a.sun_path + 1, name, strlen(name));
    bool ok = connect(fd, reinterpret_cast<sockaddr *>(&a), offsetof(sockaddr_un, sun_path) + 1 + strlen(name)) == 0;
    close(fd);
    return ok;
}

void BrokerKick()
{
    int fd = socket(AF_UNIX, SOCK_STREAM | SOCK_CLOEXEC, 0);
    sockaddr_un a{};
    a.sun_family = AF_UNIX;
    const char *name = kBroker + 1;
    memcpy(a.sun_path + 1, name, strlen(name));
    if (connect(fd, reinterpret_cast<sockaddr *>(&a), offsetof(sockaddr_un, sun_path) + 1 + strlen(name)) == 0) {
        LOGI("broker kicked: desktop (re)start");
    }
    close(fd);
}

int ListenUnix(const char *path, bool abstract)
{
    int fd = socket(AF_UNIX, SOCK_STREAM | SOCK_CLOEXEC, 0);
    sockaddr_un a{};
    a.sun_family = AF_UNIX;
    size_t len = strlen(path);
    socklen_t alen;
    if (abstract) {
        memcpy(a.sun_path + 1, path + 1, len - 1);  // "@name"
        alen = offsetof(sockaddr_un, sun_path) + len;
    } else {
        unlink(path);
        memcpy(a.sun_path, path, len);
        alen = offsetof(sockaddr_un, sun_path) + len + 1;
    }
    if (fd < 0 || bind(fd, reinterpret_cast<sockaddr *>(&a), alen) != 0 || listen(fd, 16) != 0) {
        LOGI("listen on %{public}s failed: %{public}s", path, strerror(errno));
        close(fd);
        return -1;
    }
    if (!abstract) {
        chmod(path, 0600);
    }
    return fd;
}

// The app's own broker: vtest connects to kLocalBroker; clients connect to the
// files-directory socket, and each is handed to vtest with SCM_RIGHTS (marker 'l').
void *LocalBroker(void *arg)
{
    std::string path = static_cast<const char *>(arg);
    int vl = ListenUnix(kLocalBroker, true);
    int cl = ListenUnix(path.c_str(), false);
    int vfd = -1;
    while (vl >= 0 && cl >= 0) {
        pollfd p[2] = {{vl, POLLIN, 0}, {cl, POLLIN, 0}};
        if (poll(p, 2, -1) < 0) {
            continue;
        }
        if (p[0].revents & POLLIN) {
            int fd = accept4(vl, nullptr, nullptr, SOCK_CLOEXEC);
            if (fd >= 0) {
                if (vfd >= 0) {
                    close(vfd);
                }
                vfd = fd;
                LOGI("local gpu: renderer connected");
            }
        }
        if (p[1].revents & POLLIN) {
            int c = accept4(cl, nullptr, nullptr, SOCK_CLOEXEC);
            if (c < 0) {
                continue;
            }
            char byte = 'l';
            char cbuf[CMSG_SPACE(sizeof(int))] = {};
            iovec iov{&byte, 1};
            msghdr msg{};
            msg.msg_iov = &iov;
            msg.msg_iovlen = 1;
            msg.msg_control = cbuf;
            msg.msg_controllen = sizeof(cbuf);
            cmsghdr *cm = CMSG_FIRSTHDR(&msg);
            cm->cmsg_level = SOL_SOCKET;
            cm->cmsg_type = SCM_RIGHTS;
            cm->cmsg_len = CMSG_LEN(sizeof(int));
            memcpy(CMSG_DATA(cm), &c, sizeof(int));
            if (vfd < 0 || sendmsg(vfd, &msg, MSG_NOSIGNAL) <= 0) {
                LOGI("local gpu: no renderer for a client");
            }
            close(c);
        }
    }
    return nullptr;
}

std::string LocalGpu()
{
    static std::string path = "/data/storage/el2/base/files/vtest.sock";
    bool expected = false;
    if (g_localGpu.compare_exchange_strong(expected, true)) {
        g_vtestName = kLocalBroker;
        pthread_t t;
        pthread_create(&t, nullptr, LocalBroker, const_cast<char *>(path.c_str()));
        pthread_detach(t);
        LOGI("local gpu: clients on %{public}s", path.c_str());
    }
    return path;
}

bool GpuStart(OHNativeWindow *window)
{
    static std::atomic<bool> started{false};
    g_window = window;
    OhmarchyHwfSetWindow(window, OnWindowUse);
    if (started) {
        return true;
    }
    // Route J sets OHMARCHY_LOCAL_GPU in this process (the jl module starts before
    // the window exists): be the vtest broker ourselves.
    // (files/local-gpu does the same, for trying it with the chroot's desktop.)
    if (getenv("OHMARCHY_LOCAL_GPU") != nullptr || access("/data/storage/el2/base/files/local-gpu", F_OK) == 0) {
        LocalGpu();
    }
    if (!g_localGpu && !BrokerPresent()) {
        return false;
    }
    // From here on the window belongs to the renderer: a CPU-written buffer first
    // would fix its format and leave Vulkan unable to build a swapchain on it.
    g_gpuActive = true;
    started = true;
    // Before anything in the process initialises EGL: the system EGL picks Mesa
    // (zink on the Maleoon GPU's Vulkan) only with this set.
    setenv("NEED_OPENGL", "1", 1);
    // GPU clients' frames reach Hyprland as GPU copies (vtest-inapp.patch).
    setenv("VTEST_ZERO_COPY_CLIENTS", "1", 0);
    if (access("/data/storage/el2/base/files/zc-timing", F_OK) == 0) {
        setenv("VTEST_ZC_TIMING", "1", 1);  // per-frame stage times in vtest.log
    }
    if (getenv("VIRGL_LOG_LEVEL") == nullptr) {
        setenv("VIRGL_LOG_LEVEL", "info", 1);
    }
    int log = open(kLog, O_WRONLY | O_CREAT | O_TRUNC | O_CLOEXEC, 0644);
    if (log >= 0) {
        dup2(log, STDOUT_FILENO);
        dup2(log, STDERR_FILENO);
        close(log);
        setvbuf(stdout, nullptr, _IOLBF, 0);
        setvbuf(stderr, nullptr, _IONBF, 0);
    }
    WrapSwapBuffers();
    pthread_t t;
    pthread_create(&t, nullptr, Supervisor, nullptr);
    pthread_detach(t);
    LOGI("gpu renderer thread started");
    return true;
}
