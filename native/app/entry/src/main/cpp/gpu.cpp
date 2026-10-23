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

#include <fcntl.h>
#include <stddef.h>
#include <string.h>
#include <sys/socket.h>
#include <sys/un.h>
#include <pthread.h>
#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>

#include <atomic>
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
pthread_t g_vtestThread;
const char *kBroker = "@ohmarchy-vtest";
const char *kLog = "/data/storage/el2/base/files/vtest.log";

void OnWindowUse()
{
    LOGI("renderer took the window");
}

void *VtestThread(void *)
{
    char a0[] = "vtest", a1[] = "--no-fork", a2[] = "--multi-clients", a3[] = "--socket-path",
         a4[] = "@ohmarchy-vtest";  // kBroker
    char *argv[] = {a0, a1, a2, a3, a4, nullptr};
    optind = 1;
    vtest_main(5, argv);
    return nullptr;
}

void *Supervisor(void *)
{
    for (;;) {
        if (pthread_create(&g_vtestThread, nullptr, VtestThread, nullptr) == 0) {
            pthread_join(g_vtestThread, nullptr);
        }
        LOGI("vtest stopped; retrying");
        g_scanoutRes = 0;
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
    // Presenting takes the resource to show.
    static uint32_t boundW = 0, boundH = 0;
    if (g_scanoutRes == 0 || info.width != boundW || info.height != boundH) {
        if (virgl_renderer_ohos_set_scanout(res_id, 0) != 0) {
            fprintf(stderr, "set_scanout %u failed\n", res_id);
            return false;
        }
        fprintf(stderr, "scanout -> res %u (%ux%u fmt %u)\n", res_id, info.width, info.height, info.virgl_format);
        g_scanoutRes = res_id;
        boundW = info.width;
        boundH = info.height;
    }
    // Bit 31 on the scanout id is the library's "resize debounce over" flag (the VM
    // sends it from a timer a second after a resolution change); without it every
    // present after a size change keeps showing black.
    int r = virgl_renderer_ohos_present(res_id, 0x80000000u);
    if (r != 0 || g_presents < 8 || g_presents % 120 == 0) {
        fprintf(stderr, "present #%llu res %u box %u,%u %ux%u -> %d\n", static_cast<unsigned long long>(g_presents.load()), res_id,
                box->x, box->y, box->w, box->h, r);
    }
    g_presents++;
    return true;
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

bool GpuStart(OHNativeWindow *window)
{
    static std::atomic<bool> started{false};
    g_window = window;
    OhmarchyHwfSetWindow(window, OnWindowUse);
    if (started) {
        return true;
    }
    if (!BrokerPresent()) {
        return false;
    }
    // From here on the window belongs to the renderer: a CPU-written buffer first
    // would fix its format and leave Vulkan unable to build a swapchain on it.
    g_gpuActive = true;
    started = true;
    // Before anything in the process initialises EGL: the system EGL picks Mesa
    // (zink on the Maleoon GPU's Vulkan) only with this set.
    setenv("NEED_OPENGL", "1", 1);
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
    pthread_t t;
    pthread_create(&t, nullptr, Supervisor, nullptr);
    pthread_detach(t);
    LOGI("gpu renderer thread started");
    return true;
}
