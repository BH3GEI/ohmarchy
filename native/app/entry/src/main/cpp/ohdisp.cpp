// ohdisp: show a Linux Wayland desktop in an XComponent surface and send mouse,
// touch and key input back. Frames come from the compositor's frame export (its
// output buffers, shared as dmabufs over the abstract socket @ohmarchy-display);
// without it, from RFB (wayvnc on 127.0.0.1:5900). Input always goes over RFB.
#include "ohm_names.h"
#include <ace/xcomponent/native_interface_xcomponent.h>
#include <arkui/ui_input_event.h>
#include <hilog/log.h>
#include <inputmethod/inputmethod_controller_capi.h>
#include <napi/native_api.h>
#include <native_buffer/buffer_common.h>
#include <native_buffer/native_buffer.h>
#include <native_window/external_window.h>

#include <arpa/inet.h>
#include <netinet/in.h>
#include <netinet/tcp.h>
#include <sys/mman.h>
#include <sys/socket.h>
#include <sys/un.h>
#include <unistd.h>

#include <atomic>
#include <chrono>
#include <ctime>
#include <cstddef>
#include <map>
#include <cstring>
#include <bitset>
#include <mutex>
#include <string>
#include <thread>
#include <vector>

#include "audio.h"
#include "gpu.h"

#undef LOG_DOMAIN
#undef LOG_TAG
#define LOG_DOMAIN 0x0D0D
#define LOG_TAG "ohdisp"
#define LOGI(...) OH_LOG_Print(LOG_APP, LOG_INFO, LOG_DOMAIN, LOG_TAG, __VA_ARGS__)
#define LOGE(...) OH_LOG_Print(LOG_APP, LOG_ERROR, LOG_DOMAIN, LOG_TAG, __VA_ARGS__)

namespace {

const char *kHost = "127.0.0.1";
const int kPort = 5900;

std::mutex g_winMu;
OHNativeWindow *g_win = nullptr;
uint64_t g_surfW = 0, g_surfH = 0;

std::mutex g_sendMu;
std::atomic<int> g_sock{-1};
std::atomic<int> g_fbW{0}, g_fbH{0};
std::vector<uint8_t> g_fb;  // RGBX, fbW * fbH * 4
std::atomic<bool> g_started{false};
std::atomic<bool> g_frameMode{false};  // frames from the export socket; RFB for input only
std::atomic<bool> g_shown{false};      // a frame has been shown since the source (re)connected
std::atomic<int> g_exportSock{-1};     // export socket, also carries input to the compositor
std::mutex g_exportSendMu;
const char *kExportName = OHM_NAME_PREFIX "-display";
uint8_t g_buttons = 0;
std::atomic<uint64_t> g_blits{0};  // frames shown by the CPU path (Blit)
std::atomic<int64_t> g_desktopUid{-1};  // the compositor's uid (export socket peer)
// With the GPU renderer: the export socket is there exactly while Hyprland runs.
// Presents counted when it connected (frames of this desktop come after), when it
// was last lost, and the desktop starts asked for while the app is in front.
std::atomic<uint64_t> g_presentsAtConnect{0};
std::atomic<int64_t> g_desktopLostAt{0};
std::atomic<bool> g_foreground{true};
std::atomic<int> g_kicks{0};

bool InputLog();

int64_t NowS()
{
    timespec t{};
    clock_gettime(CLOCK_MONOTONIC, &t);
    return t.tv_sec;
}

// No desktop for 10 s while the app is in front (a start takes 6-8 s, and the
// broker starts one itself when the app first connects): ask it for one, at most
// every 30 s and 3 times until a desktop connects (then GetStatus says what to do).
void MaybeStartDesktop()
{
    static int64_t lastKick = 0;
    int64_t now = NowS();
    if (!GpuActive() || !g_foreground || g_exportSock.load() >= 0 || now - g_desktopLostAt < 10 ||
        now - lastKick < 30 || g_kicks >= 3) {
        return;
    }
    lastKick = now;
    g_kicks++;
    BrokerKick();
}

bool ReadAll(int fd, void *buf, size_t n)
{
    auto *p = static_cast<uint8_t *>(buf);
    while (n > 0) {
        ssize_t r = recv(fd, p, n, 0);
        if (r <= 0) {
            return false;
        }
        p += r;
        n -= static_cast<size_t>(r);
    }
    return true;
}

bool WriteAll(int fd, const void *buf, size_t n)
{
    auto *p = static_cast<const uint8_t *>(buf);
    while (n > 0) {
        ssize_t w = send(fd, p, n, MSG_NOSIGNAL);
        if (w <= 0) {
            return false;
        }
        p += w;
        n -= static_cast<size_t>(w);
    }
    return true;
}

uint16_t Be16(const uint8_t *p) { return static_cast<uint16_t>(p[0] << 8 | p[1]); }
uint32_t Be32(const uint8_t *p) { return uint32_t(p[0]) << 24 | uint32_t(p[1]) << 16 | uint32_t(p[2]) << 8 | p[3]; }
void Put16(uint8_t *p, uint16_t v) { p[0] = v >> 8; p[1] = v & 0xff; }
void Put32(uint8_t *p, uint32_t v) { p[0] = v >> 24; p[1] = (v >> 16) & 0xff; p[2] = (v >> 8) & 0xff; p[3] = v & 0xff; }

void Send(const uint8_t *buf, size_t n)
{
    int fd = g_sock.load();
    if (fd < 0) {
        return;
    }
    std::lock_guard<std::mutex> lk(g_sendMu);
    WriteAll(fd, buf, n);
}

void SendPointer(int x, int y, uint8_t mask)
{
    int w = g_fbW.load(), h = g_fbH.load();
    if (w <= 0 || h <= 0) {
        return;
    }
    x = x < 0 ? 0 : (x >= w ? w - 1 : x);
    y = y < 0 ? 0 : (y >= h ? h - 1 : y);
    uint8_t m[6] = {5, mask};
    Put16(m + 2, static_cast<uint16_t>(x));
    Put16(m + 4, static_cast<uint16_t>(y));
    Send(m, sizeof(m));
}

void SendKey(uint32_t keysym, bool down)
{
    uint8_t m[8] = {4, static_cast<uint8_t>(down ? 1 : 0), 0, 0};
    Put32(m + 4, keysym);
    Send(m, sizeof(m));
}

// Input for the compositor's export devices: {type, a, b, c} in host byte order.
//   1 pointer position (output pixels)  2 button (evdev BTN_*), pressed
//   3 scroll axis (0 vertical, 1 horizontal), steps  4 key (evdev KEY_*), pressed
//   5 smooth scroll (touchpad): axis, delta in 1/100 px, source (1 finger)
//   6 scroll stop (touchpad fingers lifted): axis
//   7 swipe begin: fingers  8 swipe update: dx, dy in 1/100 px, fingers  9 swipe end: cancelled
bool SendExportInput(int32_t type, int32_t a, int32_t b, int32_t c = 0)
{
    int fd = g_exportSock.load();
    if (fd < 0) {
        return false;
    }
    int32_t msg[4] = {type, a, b, c};
    std::lock_guard<std::mutex> lk(g_exportSendMu);
    return WriteAll(fd, msg, sizeof(msg));
}

void RequestUpdate(int fd, bool incremental)
{
    uint8_t m[10] = {3, static_cast<uint8_t>(incremental ? 1 : 0), 0, 0, 0, 0};
    Put16(m + 6, static_cast<uint16_t>(g_fbW.load()));
    Put16(m + 8, static_cast<uint16_t>(g_fbH.load()));
    std::lock_guard<std::mutex> lk(g_sendMu);
    WriteAll(fd, m, sizeof(m));
}

// Copy a frame into a window buffer of the same size; the surface scales it to the window.
// rgbaFix: the source is RFB's RGBX with an undefined X byte, so force it opaque.
void Blit(const uint8_t *src, int w, int h, int srcStride, int32_t format, bool rgbaFix)
{
    g_blits++;
    std::lock_guard<std::mutex> lk(g_winMu);
    if (g_win == nullptr || w <= 0 || h <= 0 || GpuActive()) {
        return;
    }
    static int frames = 0;
    static int32_t curFormat = -1;
    frames++;
    if (format != curFormat) {
        OH_NativeWindow_NativeWindowHandleOpt(g_win, SET_FORMAT, format);
        curFormat = format;
    }
    OH_NativeWindow_NativeWindowHandleOpt(g_win, SET_BUFFER_GEOMETRY, w, h);
    OHNativeWindowBuffer *buf = nullptr;
    int fence = -1;
    int rc = OH_NativeWindow_NativeWindowRequestBuffer(g_win, &buf, &fence);
    if (rc != 0 || buf == nullptr) {
        LOGE("RequestBuffer rc=%{public}d", rc);
        return;
    }
    if (fence >= 0) {
        close(fence);
    }
    BufferHandle *bh = OH_NativeWindow_GetBufferHandleFromNative(buf);
    if (frames <= 2 || frames % 600 == 0) {
        LOGI("present #%{public}d %{public}dx%{public}d fmt %{public}d buf %{public}dx%{public}d stride %{public}d",
             frames, w, h, format, bh ? bh->width : -1, bh ? bh->height : -1, bh ? bh->stride : -1);
    }
    if (bh == nullptr || bh->width < w || bh->height < h) {
        OH_NativeWindow_NativeWindowAbortBuffer(g_win, buf);
        return;
    }
    // The buffer is not mapped for us; map its dma-buf fd for the copy.
    void *map = bh->virAddr;
    bool mapped = false;
    if (map == nullptr) {
        map = mmap(nullptr, static_cast<size_t>(bh->size), PROT_READ | PROT_WRITE, MAP_SHARED, bh->fd, 0);
        if (map == MAP_FAILED) {
            LOGE("mmap failed: %{public}s", strerror(errno));
            OH_NativeWindow_NativeWindowAbortBuffer(g_win, buf);
            return;
        }
        mapped = true;
    }
    auto *dst = static_cast<uint8_t *>(map);
    size_t row = static_cast<size_t>(w) * 4;
    for (int y = 0; y < h; y++) {
        uint8_t *d = dst + static_cast<size_t>(y) * bh->stride;
        const uint8_t *s = src + static_cast<size_t>(y) * srcStride;
        if (rgbaFix) {
            auto *d32 = reinterpret_cast<uint32_t *>(d);
            auto *s32 = reinterpret_cast<const uint32_t *>(s);
            for (int x = 0; x < w; x++) {
                d32[x] = s32[x] | 0xff000000u;
            }
        } else {
            memcpy(d, s, row);
        }
    }
    if (mapped) {
        munmap(map, static_cast<size_t>(bh->size));
    }
    Region region{nullptr, 0};
    rc = OH_NativeWindow_NativeWindowFlushBuffer(g_win, buf, -1, region);
    if (rc != 0) {
        LOGE("FlushBuffer rc=%{public}d", rc);
    }

    g_shown = true;

    // frames shown per second, logged every 2 s while frames keep coming
    static auto windowStart = std::chrono::steady_clock::now();
    static int windowFrames = 0;
    windowFrames++;
    auto now = std::chrono::steady_clock::now();
    double secs = std::chrono::duration<double>(now - windowStart).count();
    if (secs >= 2.0) {
        LOGI("fps %{public}.1f", windowFrames / secs);
        windowStart = now;
        windowFrames = 0;
    }
}

void Present()
{
    int w = g_fbW.load();
    Blit(g_fb.data(), w, g_fbH.load(), w * 4, NATIVEBUFFER_PIXEL_FMT_RGBA_8888, true);
}

bool Handshake(int fd)
{
    char ver[12];
    if (!ReadAll(fd, ver, 12)) {
        return false;
    }
    const char *mine = "RFB 003.008\n";
    if (!WriteAll(fd, mine, 12)) {
        return false;
    }
    uint8_t n = 0;
    if (!ReadAll(fd, &n, 1) || n == 0) {
        return false;
    }
    std::vector<uint8_t> types(n);
    if (!ReadAll(fd, types.data(), n)) {
        return false;
    }
    bool none = false;
    for (uint8_t t : types) {
        none |= t == 1;
    }
    if (!none) {
        LOGE("server offers no 'None' security type");
        return false;
    }
    uint8_t sel = 1;
    uint8_t res[4];
    if (!WriteAll(fd, &sel, 1) || !ReadAll(fd, res, 4) || Be32(res) != 0) {
        return false;
    }
    uint8_t shared = 1;
    uint8_t init[24];
    if (!WriteAll(fd, &shared, 1) || !ReadAll(fd, init, 24)) {
        return false;
    }
    std::vector<char> name(Be32(init + 20));
    if (!ReadAll(fd, name.data(), name.size())) {
        return false;
    }
    g_fbW = Be16(init);
    g_fbH = Be16(init + 2);
    g_fb.assign(static_cast<size_t>(g_fbW) * g_fbH * 4, 0);
    LOGI("connected %{public}dx%{public}d", g_fbW.load(), g_fbH.load());

    // 32bpp true colour, little endian, red in the lowest byte: memory order R,G,B,X.
    uint8_t pf[20] = {0, 0, 0, 0, 32, 24, 0, 1};
    Put16(pf + 8, 255);
    Put16(pf + 10, 255);
    Put16(pf + 12, 255);
    pf[14] = 0;
    pf[15] = 8;
    pf[16] = 16;
    // Raw, CopyRect, DesktopSize.
    const int32_t encs[] = {0, 1, -223};
    uint8_t se[4 + sizeof(encs)] = {2, 0};
    Put16(se + 2, sizeof(encs) / 4);
    for (size_t i = 0; i < sizeof(encs) / 4; i++) {
        Put32(se + 4 + i * 4, static_cast<uint32_t>(encs[i]));
    }
    return WriteAll(fd, pf, sizeof(pf)) && WriteAll(fd, se, sizeof(se));
}

bool HandleUpdate(int fd)
{
    uint8_t hdr[3];
    if (!ReadAll(fd, hdr, 3)) {
        return false;
    }
    int nrects = Be16(hdr + 1);
    std::vector<uint8_t> tmp;
    for (int i = 0; i < nrects; i++) {
        uint8_t r[12];
        if (!ReadAll(fd, r, 12)) {
            return false;
        }
        int x = Be16(r), y = Be16(r + 2), w = Be16(r + 4), h = Be16(r + 6);
        int32_t enc = static_cast<int32_t>(Be32(r + 8));
        int fbw = g_fbW.load();
        if (enc == 0) {
            size_t row = static_cast<size_t>(w) * 4;
            for (int yy = 0; yy < h; yy++) {
                if (!ReadAll(fd, g_fb.data() + (static_cast<size_t>(y + yy) * fbw + x) * 4, row)) {
                    return false;
                }
            }
        } else if (enc == 1) {
            uint8_t s[4];
            if (!ReadAll(fd, s, 4)) {
                return false;
            }
            int sx = Be16(s), sy = Be16(s + 2);
            size_t row = static_cast<size_t>(w) * 4;
            tmp.resize(row * h);
            for (int yy = 0; yy < h; yy++) {
                memcpy(tmp.data() + yy * row, g_fb.data() + (static_cast<size_t>(sy + yy) * fbw + sx) * 4, row);
            }
            for (int yy = 0; yy < h; yy++) {
                memcpy(g_fb.data() + (static_cast<size_t>(y + yy) * fbw + x) * 4, tmp.data() + yy * row, row);
            }
        } else if (enc == -223) {
            g_fbW = w;
            g_fbH = h;
            g_fb.assign(static_cast<size_t>(w) * h * 4, 0);
            LOGI("resized %{public}dx%{public}d", w, h);
        } else {
            LOGE("unexpected encoding %{public}d", enc);
            return false;
        }
    }
    Present();
    return true;
}

bool SkipBytes(int fd, size_t n)
{
    uint8_t b[256];
    while (n > 0) {
        size_t k = n < sizeof(b) ? n : sizeof(b);
        if (!ReadAll(fd, b, k)) {
            return false;
        }
        n -= k;
    }
    return true;
}

void RfbLoop()
{
    for (;;) {
        int fd = socket(AF_INET, SOCK_STREAM, 0);
        sockaddr_in a{};
        a.sin_family = AF_INET;
        a.sin_port = htons(kPort);
        inet_pton(AF_INET, kHost, &a.sin_addr);
        if (connect(fd, reinterpret_cast<sockaddr *>(&a), sizeof(a)) != 0) {
            LOGE("connect failed: %{public}s", strerror(errno));
            close(fd);
            sleep(2);
            continue;
        }
        int one = 1;
        setsockopt(fd, IPPROTO_TCP, TCP_NODELAY, &one, sizeof(one));
        if (!Handshake(fd)) {
            LOGE("handshake failed");
            close(fd);
            sleep(2);
            continue;
        }
        g_sock = fd;
        if (!g_frameMode) {
            RequestUpdate(fd, false);
        }
        bool ok = true;
        while (ok) {
            uint8_t type;
            if (!ReadAll(fd, &type, 1)) {
                break;
            }
            if (type == 0) {
                ok = HandleUpdate(fd);
                if (ok && !g_frameMode) {
                    RequestUpdate(fd, true);
                }
            } else if (type == 1) {  // SetColourMapEntries
                uint8_t h[5];
                ok = ReadAll(fd, h, 5) && SkipBytes(fd, Be16(h + 3) * 6u);
            } else if (type == 2) {  // Bell
            } else if (type == 3) {  // ServerCutText
                uint8_t h[7];
                ok = ReadAll(fd, h, 7) && SkipBytes(fd, Be32(h + 3));
            } else {
                LOGE("unknown server message %{public}d", type);
                ok = false;
            }
        }
        LOGE("disconnected");
        g_sock = -1;
        if (!g_frameMode) {
            g_shown = false;
        }
        close(fd);
        sleep(1);
    }
}

// Frames straight from the compositor: each message names one of its output buffers
// (the dmabuf fd comes along the first time) and the damage; the buffer is complete.
void FrameLoop()
{
    struct ExportBuffer {
        int fd = -1;
        uint8_t *map = nullptr;
        size_t size = 0;
    };
    for (;;) {
        int fd = socket(AF_UNIX, SOCK_STREAM | SOCK_CLOEXEC, 0);
        sockaddr_un a{};
        a.sun_family = AF_UNIX;
        size_t len = strlen(kExportName);
        memcpy(a.sun_path + 1, kExportName, len);  // abstract namespace
        if (connect(fd, reinterpret_cast<sockaddr *>(&a), offsetof(sockaddr_un, sun_path) + 1 + len) != 0) {
            close(fd);
            g_frameMode = false;
            MaybeStartDesktop();
            sleep(2);
            continue;
        }
        LOGI("frame export connected");
        g_presentsAtConnect = GpuPresents();
        g_kicks = 0;
        {
            ucred cr{};
            socklen_t len = sizeof(cr);
            if (getsockopt(fd, SOL_SOCKET, SO_PEERCRED, &cr, &len) == 0) {
                g_desktopUid = static_cast<int64_t>(cr.uid);
            }
        }
        g_shown = false;
        g_exportSock = fd;
        g_frameMode = true;
        std::map<uint64_t, ExportBuffer> bufs;
        for (;;) {
            struct __attribute__((packed)) {
                uint32_t magic, version;
                uint64_t id;
                uint32_t w, h, stride, format, nrects;
            } hdr;
            char cmsgbuf[CMSG_SPACE(sizeof(int))];
            iovec iov{&hdr, sizeof(hdr)};
            msghdr msg{};
            msg.msg_iov = &iov;
            msg.msg_iovlen = 1;
            msg.msg_control = cmsgbuf;
            msg.msg_controllen = sizeof(cmsgbuf);
            if (recvmsg(fd, &msg, MSG_WAITALL | MSG_CMSG_CLOEXEC) != sizeof(hdr) || hdr.magic != 0x4644484f) {
                break;
            }
            int newFd = -1;
            for (cmsghdr *c = CMSG_FIRSTHDR(&msg); c != nullptr; c = CMSG_NXTHDR(&msg, c)) {
                if (c->cmsg_level == SOL_SOCKET && c->cmsg_type == SCM_RIGHTS) {
                    memcpy(&newFd, CMSG_DATA(c), sizeof(int));
                }
            }
            std::vector<int32_t> rects(hdr.nrects * 4u);
            if (!rects.empty() && !ReadAll(fd, rects.data(), rects.size() * sizeof(int32_t))) {
                break;
            }
            ExportBuffer &b = bufs[hdr.id];
            if (newFd >= 0) {
                if (b.map != nullptr) {
                    munmap(b.map, b.size);
                }
                if (b.fd >= 0) {
                    close(b.fd);
                }
                b.fd = newFd;
                b.size = static_cast<size_t>(hdr.stride) * hdr.h;
                void *m = mmap(nullptr, b.size, PROT_READ, MAP_SHARED, newFd, 0);
                b.map = m == MAP_FAILED ? nullptr : static_cast<uint8_t *>(m);
                if (b.map == nullptr) {
                    LOGE("mmap export buffer: %{public}s", strerror(errno));
                }
            }
            if (b.map == nullptr) {
                continue;
            }
            // DRM XRGB/ARGB8888 are B,G,R,X in memory; XBGR/ABGR8888 are R,G,B,X.
            const bool rgb = hdr.format == 0x34324258 || hdr.format == 0x34324241;
            g_fbW = static_cast<int>(hdr.w);
            g_fbH = static_cast<int>(hdr.h);
            Blit(b.map, static_cast<int>(hdr.w), static_cast<int>(hdr.h), static_cast<int>(hdr.stride),
                 rgb ? NATIVEBUFFER_PIXEL_FMT_RGBA_8888 : NATIVEBUFFER_PIXEL_FMT_BGRA_8888, false);
            // A/V sync tests (tests/audio/avsync.sh) time a white flash in the middle
            // of the screen, on CLOCK_MONOTONIC like the sound onsets (audio.cpp).
            const uint8_t *mid = b.map + static_cast<size_t>(hdr.h / 2) * hdr.stride + (hdr.w / 2) * 4;
            bool bright = mid[0] > 200 && mid[1] > 200 && mid[2] > 200;
            static bool wasBright = false;
            if (bright && !wasBright) {
                timespec now{};
                clock_gettime(CLOCK_MONOTONIC, &now);
                LOGI("flash shown at %{public}lld ns", static_cast<long long>(now.tv_sec * 1000000000LL + now.tv_nsec));
            }
            wasBright = bright;
        }
        for (auto &[id, b] : bufs) {
            if (b.map != nullptr) {
                munmap(b.map, b.size);
            }
            if (b.fd >= 0) {
                close(b.fd);
            }
        }
        g_exportSock = -1;
        {
            std::lock_guard<std::mutex> lk(g_exportSendMu);
            close(fd);
        }
        g_frameMode = false;
        g_shown = false;
        g_desktopLostAt = NowS();
        LOGE("frame export disconnected");
        sleep(1);
    }
}

void StartOnce()
{
    bool expected = false;
    if (g_started.compare_exchange_strong(expected, true)) {
        g_desktopLostAt = NowS();
        std::thread(FrameLoop).detach();
        std::thread(RfbLoop).detach();
        AudioStart();
    }
}

// Map a window coordinate to the remote framebuffer.
void ToFb(float x, float y, int *fx, int *fy)
{
    double sw = g_surfW ? static_cast<double>(g_surfW) : 1.0;
    double sh = g_surfH ? static_cast<double>(g_surfH) : 1.0;
    *fx = static_cast<int>(x * g_fbW.load() / sw);
    *fy = static_cast<int>(y * g_fbH.load() / sh);
}

void OnSurfaceCreated(OH_NativeXComponent *c, void *window)
{
    std::lock_guard<std::mutex> lk(g_winMu);
    g_win = static_cast<OHNativeWindow *>(window);
    OH_NativeXComponent_GetXComponentSize(c, window, &g_surfW, &g_surfH);
    OH_NativeWindow_NativeWindowSetScalingModeV2(g_win, OH_SCALING_MODE_SCALE_TO_WINDOW_V2);
    if (!GpuStart(g_win)) {
        OH_NativeWindow_NativeWindowHandleOpt(g_win, SET_FORMAT, NATIVEBUFFER_PIXEL_FMT_RGBA_8888);
        OH_NativeWindow_NativeWindowHandleOpt(g_win, SET_USAGE,
            static_cast<uint64_t>(NATIVEBUFFER_USAGE_CPU_READ | NATIVEBUFFER_USAGE_CPU_WRITE | NATIVEBUFFER_USAGE_MEM_DMA));
    }
    LOGI("surface %{public}llux%{public}llu", static_cast<unsigned long long>(g_surfW),
         static_cast<unsigned long long>(g_surfH));
    StartOnce();
}

void OnSurfaceChanged(OH_NativeXComponent *c, void *window)
{
    std::lock_guard<std::mutex> lk(g_winMu);
    OH_NativeXComponent_GetXComponentSize(c, window, &g_surfW, &g_surfH);
}

void OnSurfaceDestroyed(OH_NativeXComponent *, void *)
{
    std::lock_guard<std::mutex> lk(g_winMu);
    g_win = nullptr;
}

void FlushModsForPointer();  // Alt+Shift as Super, below
void ResetMods();

void OnTouch(OH_NativeXComponent *c, void *window)
{
    OH_NativeXComponent_TouchEvent ev;
    if (OH_NativeXComponent_GetTouchEvent(c, window, &ev) != 0) {
        return;
    }
    // Mouse input also arrives as touch events with a mouse source; leave those to OnMouse.
    OH_NativeXComponent_EventSourceType src;
    if (OH_NativeXComponent_GetTouchEventSourceType(c, ev.id, &src) == 0 &&
        src == OH_NATIVEXCOMPONENT_SOURCE_TYPE_MOUSE) {
        return;
    }
    if (InputLog()) {  // touch screen, or touchpad gestures if HarmonyOS passes them on
        LOGI("input touch type %{public}d source %{public}d points %{public}u", static_cast<int>(ev.type),
             static_cast<int>(src), ev.numPoints);
    }
    int x, y;
    ToFb(ev.x, ev.y, &x, &y);
    if (g_frameMode) {
        SendExportInput(1, x, y);
        if (ev.type == OH_NATIVEXCOMPONENT_DOWN || ev.type == OH_NATIVEXCOMPONENT_UP) {
            FlushModsForPointer();
            SendExportInput(2, 0x110, ev.type == OH_NATIVEXCOMPONENT_DOWN);  // BTN_LEFT
        }
        return;
    }
    uint8_t mask = (ev.type == OH_NATIVEXCOMPONENT_DOWN || ev.type == OH_NATIVEXCOMPONENT_MOVE) ? 1 : 0;
    SendPointer(x, y, mask);
}

void OnMouse(OH_NativeXComponent *c, void *window)
{
    OH_NativeXComponent_MouseEvent ev;
    if (OH_NativeXComponent_GetMouseEvent(c, window, &ev) != 0) {
        return;
    }
    uint8_t bit = 0;
    switch (ev.button) {
        case OH_NATIVEXCOMPONENT_LEFT_BUTTON: bit = 1; break;
        case OH_NATIVEXCOMPONENT_MIDDLE_BUTTON: bit = 2; break;
        case OH_NATIVEXCOMPONENT_RIGHT_BUTTON: bit = 4; break;
        default: break;
    }
    if (ev.action == OH_NATIVEXCOMPONENT_MOUSE_PRESS) {
        g_buttons |= bit;
    } else if (ev.action == OH_NATIVEXCOMPONENT_MOUSE_RELEASE) {
        g_buttons &= static_cast<uint8_t>(~bit);
    }
    int x, y;
    ToFb(ev.x, ev.y, &x, &y);
    if (g_frameMode) {
        SendExportInput(1, x, y);
        if (bit != 0 && (ev.action == OH_NATIVEXCOMPONENT_MOUSE_PRESS || ev.action == OH_NATIVEXCOMPONENT_MOUSE_RELEASE)) {
            const int32_t btn = bit == 1 ? 0x110 : (bit == 2 ? 0x112 : 0x111);  // BTN_LEFT/MIDDLE/RIGHT
            FlushModsForPointer();
            SendExportInput(2, btn, ev.action == OH_NATIVEXCOMPONENT_MOUSE_PRESS);
        }
        return;
    }
    SendPointer(x, y, g_buttons);
}

void OnHover(OH_NativeXComponent *, bool) {}

int g_lastX = 0, g_lastY = 0;

// What HarmonyOS delivers (keys, scroll, gestures), to hilog tag ohdisp: the first
// 300 events after start, all of them while the file "inputlog" exists in the
// app's files directory.
bool InputLog()
{
    static int n = 0;
    static int64_t checked = -1;
    static bool file = false;
    int64_t now = NowS();
    if (now != checked) {
        checked = now;
        file = access("/data/storage/el2/base/files/inputlog", F_OK) == 0;
    }
    return file || n++ < 300;
}

// Scroll. Touchpad (two fingers): its deltas as smooth finger scrolling, both axes,
// and a stop when the fingers lift (clients then do kinetic scrolling). Mouse
// wheel: notches, as before. Units: the axis values are in vp (logged with the
// first events); OHMARCHY scroll speed is kScrollScale output pixels per unit.
const double kScrollScale = 1.0;
void OnAxis(OH_NativeXComponent *, ArkUI_UIInputEvent *event, ArkUI_UIInputEvent_Type)
{
    double v = OH_ArkUI_AxisEvent_GetVerticalAxisValue(event);
    double hz = OH_ArkUI_AxisEvent_GetHorizontalAxisValue(event);
    int32_t act = OH_ArkUI_AxisEvent_GetAxisAction(event);
    int32_t tool = OH_ArkUI_UIInputEvent_GetToolType(event);
    int32_t srcType = OH_ArkUI_UIInputEvent_GetSourceType(event);
    int x, y;
    ToFb(OH_ArkUI_PointerEvent_GetX(event), OH_ArkUI_PointerEvent_GetY(event), &x, &y);
    if (InputLog()) {
        LOGI("input axis action %{public}d tool %{public}d source %{public}d v %{public}.2f h %{public}.2f pinch %{public}.3f step %{public}d",
             act, tool, srcType, v, hz, OH_ArkUI_AxisEvent_GetPinchAxisScaleValue(event),
             OH_ArkUI_AxisEvent_GetScrollStep(event));
    }
    if (g_frameMode && tool == UI_INPUT_EVENT_TOOL_TYPE_TOUCHPAD) {
        SendExportInput(1, x, y);
        FlushModsForPointer();
        if (v != 0) {
            SendExportInput(5, 0, static_cast<int32_t>(v * kScrollScale * 100), 1);
        }
        if (hz != 0) {
            SendExportInput(5, 1, static_cast<int32_t>(hz * kScrollScale * 100), 1);
        }
        if (act == UI_AXIS_EVENT_ACTION_END || act == UI_AXIS_EVENT_ACTION_CANCEL) {
            SendExportInput(6, 0, 0);
            SendExportInput(6, 1, 0);
        }
        return;
    }
    if (v == 0 && hz == 0) {
        return;
    }
    if (g_frameMode) {
        // a wheel notch is 15 units; small values still move one step
        auto steps = [](double d) { int n = static_cast<int>(d / 15.0); return n != 0 ? n : (d < 0 ? -1 : 1); };
        SendExportInput(1, x, y);
        FlushModsForPointer();
        if (v != 0) {
            SendExportInput(3, 0, steps(v));
        }
        if (hz != 0) {
            SendExportInput(3, 1, steps(hz));
        }
        return;
    }
    if (v == 0) {
        return;
    }
    uint8_t wheel = v < 0 ? 8 : 16;  // buttons 4/5: scroll up/down
    SendPointer(x, y, g_buttons | wheel);
    SendPointer(x, y, g_buttons);
}

uint32_t KeySym(OH_NativeXComponent_KeyCode k)
{
    if (k >= KEY_A && k <= KEY_Z) {
        return 'a' + (k - KEY_A);
    }
    if (k >= KEY_0 && k <= KEY_9) {
        return '0' + (k - KEY_0);
    }
    if (k >= KEY_F1 && k <= KEY_F12) {
        return 0xffbe + (k - KEY_F1);
    }
    if (k >= KEY_NUMPAD_0 && k <= KEY_NUMPAD_9) {
        return 0xffb0 + (k - KEY_NUMPAD_0);
    }
    switch (k) {
        case KEY_ENTER: return 0xff0d;
        case KEY_NUMPAD_ENTER: return 0xff8d;
        case KEY_ESCAPE: return 0xff1b;
        case KEY_TAB: return 0xff09;
        case KEY_DEL: return 0xff08;
        case KEY_FORWARD_DEL: return 0xffff;
        case KEY_SPACE: return ' ';
        case KEY_DPAD_LEFT: return 0xff51;
        case KEY_DPAD_UP: return 0xff52;
        case KEY_DPAD_RIGHT: return 0xff53;
        case KEY_DPAD_DOWN: return 0xff54;
        case KEY_MOVE_HOME: return 0xff50;
        case KEY_MOVE_END: return 0xff57;
        case KEY_PAGE_UP: return 0xff55;
        case KEY_PAGE_DOWN: return 0xff56;
        case KEY_INSERT: return 0xff63;
        case KEY_SHIFT_LEFT: return 0xffe1;
        case KEY_SHIFT_RIGHT: return 0xffe2;
        case KEY_CTRL_LEFT: return 0xffe3;
        case KEY_CTRL_RIGHT: return 0xffe4;
        case KEY_CAPS_LOCK: return 0xffe5;
        case KEY_ALT_LEFT: return 0xffe9;
        case KEY_ALT_RIGHT: return 0xffea;
        case KEY_META_LEFT: return 0xffeb;
        case KEY_META_RIGHT: return 0xffec;
        case KEY_MENU: return 0xff67;
        case KEY_MINUS: return '-';
        case KEY_EQUALS: return '=';
        case KEY_LEFT_BRACKET: return '[';
        case KEY_RIGHT_BRACKET: return ']';
        case KEY_BACKSLASH: return '\\';
        case KEY_SEMICOLON: return ';';
        case KEY_APOSTROPHE: return '\'';
        case KEY_GRAVE: return '`';
        case KEY_COMMA: return ',';
        case KEY_PERIOD: return '.';
        case KEY_SLASH: return '/';
        case KEY_NUMPAD_DIVIDE: return 0xffaf;
        case KEY_NUMPAD_MULTIPLY: return 0xffaa;
        case KEY_NUMPAD_SUBTRACT: return 0xffad;
        case KEY_NUMPAD_ADD: return 0xffab;
        case KEY_NUMPAD_DOT: return 0xffae;
        default: return 0;
    }
}

// ---- Input method: Ctrl+Space attaches the HarmonyOS IME; its text goes to ohime in the
// chroot (@ohmarchy-ime: {uint32 type, uint32 len} + UTF-8; 1 commit, 2 preedit), which
// commits it to the focused Linux app. Detached, keys go to the compositor as evdev codes.
const char *kImeName = OHM_NAME_PREFIX "-ime";
InputMethod_TextEditorProxy *g_imeEditor = nullptr;
InputMethod_InputMethodProxy *g_imeProxy = nullptr;
std::mutex g_imeMu;
int g_imeSock = -1;

std::string Utf8(const char16_t *text, size_t length)
{
    std::string out;
    for (size_t i = 0; i < length; i++) {
        uint32_t c = text[i];
        if (c >= 0xD800 && c <= 0xDBFF && i + 1 < length && text[i + 1] >= 0xDC00 && text[i + 1] <= 0xDFFF) {
            c = 0x10000 + ((c - 0xD800) << 10) + (text[++i] - 0xDC00);
        }
        if (c < 0x80) {
            out += static_cast<char>(c);
        } else if (c < 0x800) {
            out += static_cast<char>(0xC0 | (c >> 6));
            out += static_cast<char>(0x80 | (c & 0x3F));
        } else if (c < 0x10000) {
            out += static_cast<char>(0xE0 | (c >> 12));
            out += static_cast<char>(0x80 | ((c >> 6) & 0x3F));
            out += static_cast<char>(0x80 | (c & 0x3F));
        } else {
            out += static_cast<char>(0xF0 | (c >> 18));
            out += static_cast<char>(0x80 | ((c >> 12) & 0x3F));
            out += static_cast<char>(0x80 | ((c >> 6) & 0x3F));
            out += static_cast<char>(0x80 | (c & 0x3F));
        }
    }
    return out;
}

bool SendIme(uint32_t type, const std::string &text)
{
    std::lock_guard<std::mutex> lk(g_imeMu);
    for (int attempt = 0; attempt < 2; attempt++) {
        if (g_imeSock < 0) {
            g_imeSock = socket(AF_UNIX, SOCK_STREAM | SOCK_CLOEXEC, 0);
            sockaddr_un a{};
            a.sun_family = AF_UNIX;
            size_t len = strlen(kImeName);
            memcpy(a.sun_path + 1, kImeName, len);
            if (connect(g_imeSock, reinterpret_cast<sockaddr *>(&a), offsetof(sockaddr_un, sun_path) + 1 + len) != 0) {
                close(g_imeSock);
                g_imeSock = -1;
                return false;
            }
        }
        uint32_t hdr[2] = {type, static_cast<uint32_t>(text.size())};
        if (WriteAll(g_imeSock, hdr, sizeof(hdr)) && WriteAll(g_imeSock, text.data(), text.size())) {
            return true;
        }
        close(g_imeSock);  // ohime restarted: reconnect once
        g_imeSock = -1;
    }
    return false;
}

void TapKey(int32_t key)
{
    SendExportInput(4, key, 1);
    SendExportInput(4, key, 0);
}

void ImeGetTextConfig(InputMethod_TextEditorProxy *, InputMethod_TextConfig *config)
{
    OH_TextConfig_SetInputType(config, IME_TEXT_INPUT_TYPE_TEXT);
    OH_TextConfig_SetEnterKeyType(config, IME_ENTER_KEY_NEWLINE);
    OH_TextConfig_SetPreviewTextSupport(config, true);
}
void ImeInsertText(InputMethod_TextEditorProxy *, const char16_t *text, size_t length)
{
    SendIme(1, Utf8(text, length));
}
void ImeDeleteForward(InputMethod_TextEditorProxy *, int32_t length)
{
    for (int32_t i = 0; i < length; i++) {
        TapKey(111);  // KEY_DELETE
    }
}
void ImeDeleteBackward(InputMethod_TextEditorProxy *, int32_t length)
{
    for (int32_t i = 0; i < length; i++) {
        TapKey(14);  // KEY_BACKSPACE
    }
}
void ImeKeyboardStatus(InputMethod_TextEditorProxy *, InputMethod_KeyboardStatus) {}
void ImeEnter(InputMethod_TextEditorProxy *, InputMethod_EnterKeyType)
{
    TapKey(28);  // KEY_ENTER
}
void ImeMoveCursor(InputMethod_TextEditorProxy *, InputMethod_Direction direction)
{
    switch (direction) {
        case IME_DIRECTION_UP: TapKey(103); break;
        case IME_DIRECTION_DOWN: TapKey(108); break;
        case IME_DIRECTION_LEFT: TapKey(105); break;
        case IME_DIRECTION_RIGHT: TapKey(106); break;
        default: break;
    }
}
void ImeSetSelection(InputMethod_TextEditorProxy *, int32_t, int32_t) {}
void ImeExtendAction(InputMethod_TextEditorProxy *, InputMethod_ExtendAction) {}
void ImeLeftText(InputMethod_TextEditorProxy *, int32_t, char16_t[], size_t *length)
{
    *length = 0;  // the Linux app's text is not visible from here
}
void ImeRightText(InputMethod_TextEditorProxy *, int32_t, char16_t[], size_t *length)
{
    *length = 0;
}
int32_t ImeIndexAtCursor(InputMethod_TextEditorProxy *)
{
    return 0;
}
int32_t ImePrivateCommand(InputMethod_TextEditorProxy *, InputMethod_PrivateCommand *[], size_t)
{
    return 0;
}
int32_t ImeSetPreview(InputMethod_TextEditorProxy *, const char16_t text[], size_t length, int32_t, int32_t)
{
    SendIme(2, Utf8(text, length));
    return 0;
}
void ImeFinishPreview(InputMethod_TextEditorProxy *)
{
    SendIme(2, "");
}

void ImeToggle()
{
    if (g_imeProxy != nullptr) {
        OH_InputMethodController_Detach(g_imeProxy);
        g_imeProxy = nullptr;
        SendIme(2, "");
        LOGI("ime: detached, keys go to the desktop");
        return;
    }
    if (g_imeEditor == nullptr) {
        g_imeEditor = OH_TextEditorProxy_Create();
        OH_TextEditorProxy_SetGetTextConfigFunc(g_imeEditor, ImeGetTextConfig);
        OH_TextEditorProxy_SetInsertTextFunc(g_imeEditor, ImeInsertText);
        OH_TextEditorProxy_SetDeleteForwardFunc(g_imeEditor, ImeDeleteForward);
        OH_TextEditorProxy_SetDeleteBackwardFunc(g_imeEditor, ImeDeleteBackward);
        OH_TextEditorProxy_SetSendKeyboardStatusFunc(g_imeEditor, ImeKeyboardStatus);
        OH_TextEditorProxy_SetSendEnterKeyFunc(g_imeEditor, ImeEnter);
        OH_TextEditorProxy_SetMoveCursorFunc(g_imeEditor, ImeMoveCursor);
        OH_TextEditorProxy_SetHandleSetSelectionFunc(g_imeEditor, ImeSetSelection);
        OH_TextEditorProxy_SetHandleExtendActionFunc(g_imeEditor, ImeExtendAction);
        OH_TextEditorProxy_SetGetLeftTextOfCursorFunc(g_imeEditor, ImeLeftText);
        OH_TextEditorProxy_SetGetRightTextOfCursorFunc(g_imeEditor, ImeRightText);
        OH_TextEditorProxy_SetGetTextIndexAtCursorFunc(g_imeEditor, ImeIndexAtCursor);
        OH_TextEditorProxy_SetReceivePrivateCommandFunc(g_imeEditor, ImePrivateCommand);
        OH_TextEditorProxy_SetSetPreviewTextFunc(g_imeEditor, ImeSetPreview);
        OH_TextEditorProxy_SetFinishTextPreviewFunc(g_imeEditor, ImeFinishPreview);
    }
    InputMethod_AttachOptions *options = OH_AttachOptions_Create(false);
    InputMethod_ErrorCode rc = OH_InputMethodController_Attach(g_imeEditor, options, &g_imeProxy);
    OH_AttachOptions_Destroy(options);
    if (rc != IME_ERR_OK) {
        LOGE("ime: attach failed %{public}d", static_cast<int>(rc));
        g_imeProxy = nullptr;
        return;
    }
    LOGI("ime: attached, text goes to the focused Linux app");
}

bool g_ctrlDown = false;
// Keys the compositor holds as pressed. HarmonyOS keeps the release of the Super
// (Meta) key for itself (it opens its start menu then, which takes the focus), so
// Hyprland would keep Super pressed and turn every later key into a Super chord.
// When the window loses the focus, everything still pressed is released.
std::mutex g_heldMu;
std::bitset<256> g_held;

void SendKeyExport(uint32_t key, bool down)
{
    if (key < g_held.size()) {
        std::lock_guard<std::mutex> lk(g_heldMu);
        g_held[key] = down;
    }
    SendExportInput(4, static_cast<int32_t>(key), down);
}

void ReleaseHeldKeys()
{
    std::bitset<256> held;
    {
        std::lock_guard<std::mutex> lk(g_heldMu);
        held = g_held;
        g_held.reset();
    }
    for (size_t k = 0; k < held.size(); k++) {
        if (held[k]) {
            if (InputLog()) {
                LOGI("input key evdev %{public}zu released (focus lost)", k);
            }
            SendExportInput(4, static_cast<int32_t>(k), 0);
        }
    }
    g_ctrlDown = false;
    ResetMods();
}

// A stand-in for Super: HarmonyOS opens its start menu on the Super key's release
// and keeps many Super chords for itself, so Omarchy's Super shortcuts are typed
// another way here. The file files/super-key in the app's data directory says how:
// "altshift" (Alt+Shift held together, the default), "ralt" (right Alt), "capslock",
// or "off" (only the real Super key).
enum class SuperKey { AltShift, RightAlt, CapsLock, Off };
SuperKey SuperStandIn()
{
    static int64_t checked = -1;
    static SuperKey key = SuperKey::AltShift;
    int64_t now = NowS();
    if (now != checked) {
        checked = now;
        key = SuperKey::AltShift;
        if (FILE *f = fopen("/data/storage/el2/base/files/super-key", "r")) {
            char b[16] = {0};
            if (fgets(b, sizeof(b), f) != nullptr) {
                if (strncmp(b, "ralt", 4) == 0) {
                    key = SuperKey::RightAlt;
                } else if (strncmp(b, "capslock", 8) == 0) {
                    key = SuperKey::CapsLock;
                } else if (strncmp(b, "off", 3) == 0) {
                    key = SuperKey::Off;
                }
            }
            fclose(f);
        }
    }
    return key;
}

// Alt+Shift as Super. Alt and Shift held together (either side of each) are Super;
// holding the other Shift as well adds Shift, the other Alt adds Alt:
//   Alt+Shift+X = Super+X        Alt+Shift+Shift+X = Super+Shift+X
//   Alt+Alt+Shift+X = Super+Alt+X, and all four for Super+Shift+Alt+X.
// Tab is left alone, so Alt+Shift+Tab stays "previous window". Alt and Shift reach
// the compositor only when a key, button, scroll or swipe follows (or as a tap when
// pressed and released alone), so a Super chord never shows Hyprland Alt or Shift.
enum ModBit { kLAlt = 1, kRAlt = 2, kLShift = 4, kRShift = 8 };
const uint32_t kModKeys[] = {125, 56, 100, 42, 54};  // Super, Alt, AltGr, Shift, right Shift
unsigned g_mods;         // Alt/Shift keys held
unsigned g_modsTap;      // the one modifier pressed alone, until anything else happens
std::bitset<5> g_modsSent;  // kModKeys the compositor has as pressed

int ModBitOf(OH_NativeXComponent_KeyCode k)
{
    switch (k) {
        case KEY_ALT_LEFT: return kLAlt;
        case KEY_ALT_RIGHT: return kRAlt;
        case KEY_SHIFT_LEFT: return kLShift;
        case KEY_SHIFT_RIGHT: return kRShift;
        default: return 0;
    }
}

std::bitset<5> WantedMods(bool superChord)
{
    std::bitset<5> w;
    const bool alt = g_mods & (kLAlt | kRAlt), shift = g_mods & (kLShift | kRShift);
    if (superChord && alt && shift) {
        w[0] = true;
        w[3] = (g_mods & kLShift) && (g_mods & kRShift);
        w[1] = (g_mods & kLAlt) && (g_mods & kRAlt);
    } else {
        w[1] = g_mods & kLAlt;
        w[2] = g_mods & kRAlt;
        w[3] = g_mods & kLShift;
        w[4] = g_mods & kRShift;
    }
    return w;
}

// Bring the compositor's modifiers to what is held; pressOnly false only releases.
void FlushMods(bool superChord, bool press = true)
{
    std::bitset<5> want = WantedMods(superChord);
    if (!press) {
        want &= g_modsSent;
    }
    for (size_t i = 0; i < want.size(); i++) {
        if (g_modsSent[i] && !want[i]) {
            SendKeyExport(kModKeys[i], false);
        }
    }
    for (size_t i = 0; i < want.size(); i++) {
        if (!g_modsSent[i] && want[i]) {
            SendKeyExport(kModKeys[i], true);
        }
    }
    g_modsSent = want;
    g_modsTap = 0;
}

// Before a button, scroll or swipe: pending Alt/Shift (or their Super) go out.
void FlushModsForPointer()
{
    if (g_frameMode && SuperStandIn() == SuperKey::AltShift && g_mods != 0) {
        FlushMods(true);
    }
}

// An Alt or Shift key in Alt+Shift mode; returns true when it was handled.
bool OnModKey(OH_NativeXComponent_KeyCode code, bool down)
{
    const int bit = ModBitOf(code);
    if (bit == 0 || SuperStandIn() != SuperKey::AltShift) {
        return false;
    }
    if (down) {
        g_modsTap = g_mods == 0 ? bit : 0;
        g_mods |= bit;
        return true;
    }
    const bool tap = g_modsTap == static_cast<unsigned>(bit);
    g_mods &= ~static_cast<unsigned>(bit);
    if (tap) {  // pressed and released alone: the plain key, for apps that use a tap
        uint32_t key = bit == kLAlt ? 56 : bit == kRAlt ? 100 : bit == kLShift ? 42 : 54;
        SendKeyExport(key, true);
        SendKeyExport(key, false);
    }
    FlushMods(true, false);
    return true;
}

// Focus lost: ReleaseHeldKeys has released what the compositor had.
void ResetMods()
{
    g_mods = 0;
    g_modsTap = 0;
    g_modsSent.reset();
}

// OpenHarmony key code -> Linux evdev KEY_* code (the compositor applies the keymap).
uint32_t EvdevKey(OH_NativeXComponent_KeyCode k)
{
    static const uint8_t letters[26] = {30, 48, 46, 32, 18, 33, 34, 35, 23, 36, 37, 38, 50,
                                        49, 24, 25, 16, 19, 31, 20, 22, 47, 17, 45, 21, 44};
    static const uint8_t numpad[10] = {82, 79, 80, 81, 75, 76, 77, 71, 72, 73};
    if (k >= KEY_A && k <= KEY_Z) {
        return letters[k - KEY_A];
    }
    if (k >= KEY_1 && k <= KEY_9) {
        return 2 + (k - KEY_1);
    }
    if (k >= KEY_F1 && k <= KEY_F10) {
        return 59 + (k - KEY_F1);
    }
    if (k >= KEY_NUMPAD_0 && k <= KEY_NUMPAD_9) {
        return numpad[k - KEY_NUMPAD_0];
    }
    switch (k) {
        case KEY_0: return 11;
        case KEY_F11: return 87;
        case KEY_F12: return 88;
        case KEY_ENTER: return 28;
        case KEY_NUMPAD_ENTER: return 96;
        case KEY_ESCAPE: return 1;
        case KEY_TAB: return 15;
        case KEY_DEL: return 14;
        case KEY_FORWARD_DEL: return 111;
        case KEY_SPACE: return 57;
        case KEY_DPAD_LEFT: return 105;
        case KEY_DPAD_UP: return 103;
        case KEY_DPAD_RIGHT: return 106;
        case KEY_DPAD_DOWN: return 108;
        case KEY_MOVE_HOME: return 102;
        case KEY_MOVE_END: return 107;
        case KEY_PAGE_UP: return 104;
        case KEY_PAGE_DOWN: return 109;
        case KEY_INSERT: return 110;
        case KEY_SHIFT_LEFT: return 42;
        case KEY_SHIFT_RIGHT: return 54;
        case KEY_CTRL_LEFT: return 29;
        case KEY_CTRL_RIGHT: return 97;
        case KEY_CAPS_LOCK: return SuperStandIn() == SuperKey::CapsLock ? 125 : 58;
        case KEY_ALT_LEFT: return 56;
        case KEY_ALT_RIGHT: return SuperStandIn() == SuperKey::RightAlt ? 125 : 100;
        case KEY_META_LEFT: return 125;
        case KEY_META_RIGHT: return 126;
        case KEY_MENU: return 127;
        case KEY_MINUS: return 12;
        case KEY_EQUALS: return 13;
        case KEY_LEFT_BRACKET: return 26;
        case KEY_RIGHT_BRACKET: return 27;
        case KEY_BACKSLASH: return 43;
        case KEY_SEMICOLON: return 39;
        case KEY_APOSTROPHE: return 40;
        case KEY_GRAVE: return 41;
        case KEY_COMMA: return 51;
        case KEY_PERIOD: return 52;
        case KEY_SLASH: return 53;
        case KEY_NUMPAD_DIVIDE: return 98;
        case KEY_NUMPAD_MULTIPLY: return 55;
        case KEY_NUMPAD_SUBTRACT: return 74;
        case KEY_NUMPAD_ADD: return 78;
        case KEY_NUMPAD_DOT: return 83;
        case KEY_SYSRQ: return 99;
        default: return 0;
    }
}

bool OnKey(OH_NativeXComponent *c, void *)
{
    OH_NativeXComponent_KeyEvent *ev = nullptr;
    if (OH_NativeXComponent_GetKeyEvent(c, &ev) != 0 || ev == nullptr) {
        return false;
    }
    OH_NativeXComponent_KeyAction action;
    OH_NativeXComponent_KeyCode code;
    OH_NativeXComponent_GetKeyEventAction(ev, &action);
    OH_NativeXComponent_GetKeyEventCode(ev, &code);
    const bool down = action == OH_NATIVEXCOMPONENT_KEY_ACTION_DOWN;
    if (InputLog()) {
        LOGI("input key code %{public}d %{public}s -> evdev %{public}u", static_cast<int>(code), down ? "down" : "up",
             EvdevKey(code));
    }
    if (code == KEY_CTRL_LEFT || code == KEY_CTRL_RIGHT) {
        g_ctrlDown = down;
    }
    // Ctrl+Space toggles the HarmonyOS IME only when ohime runs in the desktop (an empty
    // preedit probes it); otherwise the chord goes on to fcitx5, which uses it too.
    static bool chordTaken = false;
    if (g_frameMode && down && g_ctrlDown && code == KEY_SPACE && (g_imeProxy != nullptr || SendIme(2, ""))) {
        chordTaken = true;
        ImeToggle();
        return true;
    }
    if (g_frameMode) {
        if (code == KEY_SPACE && !down && chordTaken) {
            chordTaken = false;
            return true;  // release of the toggle chord
        }
        if (OnModKey(code, down)) {
            return true;
        }
        uint32_t key = EvdevKey(code);
        if (key == 0) {
            LOGI("unmapped key %{public}d", static_cast<int>(code));
            return false;
        }
        if (down && SuperStandIn() == SuperKey::AltShift) {
            FlushMods(code != KEY_TAB);
        }
        SendKeyExport(key, action == OH_NATIVEXCOMPONENT_KEY_ACTION_DOWN);
        return true;
    }
    uint32_t sym = KeySym(code);
    if (sym == 0) {
        LOGI("unmapped key %{public}d", static_cast<int>(code));
        return false;
    }
    SendKey(sym, action == OH_NATIVEXCOMPONENT_KEY_ACTION_DOWN);
    return true;  // consumed: keep the system from acting on it
}

OH_NativeXComponent_Callback g_cb;
OH_NativeXComponent_MouseEvent_Callback g_mouseCb;

// Status line for the page while nothing is on screen; empty once frames show.
napi_value GetStatus(napi_env env, napi_callback_info)
{
    const char *msg = "";
    if (GpuActive()) {
        // The overlay hides whatever the window last showed (an old desktop).
        if (g_exportSock.load() < 0) {
            msg = g_kicks >= 3 ? "The Omarchy desktop does not start. Log: /run/user/60000/ohmarchy-desktop.log;"
                                 " in a root shell on this PC: omarchy desktop start"
                               : "Connecting to the Omarchy desktop…";
        } else if (GpuPresents() <= g_presentsAtConnect) {
            msg = "Connected to Omarchy, waiting for the first frame…";
        }
    } else if (!g_shown && GpuPresents() == 0) {
        if (g_frameMode) {
            msg = "Connected to Omarchy, waiting for the first frame…";
        } else if (g_sock.load() >= 0) {
            msg = "Connected over VNC, waiting for the first frame…";
        } else {
            msg = "Omarchy desktop is not running. In a root shell on this PC: omarchy desktop start";
        }
    }
    napi_value v = nullptr;
    napi_create_string_utf8(env, msg, NAPI_AUTO_LENGTH, &v);
    return v;
}

// The page in front or not (Index.ets onPageShow/onPageHide): desktop starts are
// asked for only while the user looks at the app.
// Multi-finger touchpad swipes, from the page's PanGesture (the native touch and axis
// callbacks don't see them): swipe(phase 0 begin / 1 update / 2 end / 3 cancel,
// dx, dy in px since the last call, fingers). Hyprland's gestures act on them.
napi_value Swipe(napi_env env, napi_callback_info info)
{
    size_t argc = 4;
    napi_value argv[4] = {nullptr};
    napi_get_cb_info(env, info, &argc, argv, nullptr, nullptr);
    int32_t phase = 0, fingers = 3;
    double dx = 0, dy = 0;
    if (argc < 4 || napi_get_value_int32(env, argv[0], &phase) != napi_ok ||
        napi_get_value_double(env, argv[1], &dx) != napi_ok || napi_get_value_double(env, argv[2], &dy) != napi_ok ||
        napi_get_value_int32(env, argv[3], &fingers) != napi_ok) {
        return nullptr;
    }
    if (InputLog()) {
        LOGI("input swipe phase %{public}d fingers %{public}d dx %{public}.1f dy %{public}.1f", phase, fingers, dx, dy);
    }
    if (!g_frameMode) {
        return nullptr;
    }
    switch (phase) {
        case 0: FlushModsForPointer(); SendExportInput(7, fingers, 0); break;
        case 1: SendExportInput(8, static_cast<int32_t>(dx * 100), static_cast<int32_t>(dy * 100), fingers); break;
        default: SendExportInput(9, phase == 3 ? 1 : 0, 0); break;
    }
    return nullptr;
}

// Route J: the app is its own vtest broker; returns the socket path for clients.
napi_value LocalGpuNapi(napi_env env, napi_callback_info)
{
    std::string path = LocalGpu();
    napi_value v = nullptr;
    napi_create_string_utf8(env, path.c_str(), path.size(), &v);
    return v;
}

napi_value ReleaseKeys(napi_env, napi_callback_info)
{
    ReleaseHeldKeys();
    return nullptr;
}

napi_value SetForeground(napi_env env, napi_callback_info info)
{
    size_t argc = 1;
    napi_value argv[1] = {nullptr};
    bool fg = true;
    napi_get_cb_info(env, info, &argc, argv, nullptr, nullptr);
    if (argc >= 1) {
        napi_get_value_bool(env, argv[0], &fg);
    }
    g_foreground = fg;
    if (fg) {
        g_kicks = 0;  // a new look at the app: try again
    }
    return nullptr;
}

napi_value Init(napi_env env, napi_value exports)
{
    napi_property_descriptor desc[] = {
        {"getStatus", nullptr, GetStatus, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"setForeground", nullptr, SetForeground, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"swipe", nullptr, Swipe, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"releaseKeys", nullptr, ReleaseKeys, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"localGpu", nullptr, LocalGpuNapi, nullptr, nullptr, nullptr, napi_default, nullptr},
    };
    napi_define_properties(env, exports, sizeof(desc) / sizeof(desc[0]), desc);

    napi_value obj = nullptr;
    OH_NativeXComponent *nc = nullptr;
    if (napi_get_named_property(env, exports, OH_NATIVE_XCOMPONENT_OBJ, &obj) != napi_ok ||
        napi_unwrap(env, obj, reinterpret_cast<void **>(&nc)) != napi_ok || nc == nullptr) {
        return exports;
    }
    g_cb.OnSurfaceCreated = OnSurfaceCreated;
    g_cb.OnSurfaceChanged = OnSurfaceChanged;
    g_cb.OnSurfaceDestroyed = OnSurfaceDestroyed;
    g_cb.DispatchTouchEvent = OnTouch;
    OH_NativeXComponent_RegisterCallback(nc, &g_cb);
    g_mouseCb.DispatchMouseEvent = OnMouse;
    g_mouseCb.DispatchHoverEvent = OnHover;
    OH_NativeXComponent_RegisterMouseEventCallback(nc, &g_mouseCb);
    OH_NativeXComponent_RegisterKeyEventCallbackWithResult(nc, OnKey);
    OH_NativeXComponent_RegisterUIInputEventCallback(nc, OnAxis, ARKUI_UIINPUTEVENT_TYPE_AXIS);
    // Ask for the panel's top refresh rate (it idles at 60 Hz otherwise): frames are
    // presented as fast as the display takes them. The vote needs a frame callback,
    // which then runs on every vsync: after a second without new frames the vote
    // drops to 10 Hz (an idle desktop costs the app almost nothing), and the first
    // new frame raises it again.
    OH_NativeXComponent_ExpectedRateRange rate{60, 120, 120};
    OH_NativeXComponent_RegisterOnFrameCallback(nc, [](OH_NativeXComponent *c, uint64_t ts, uint64_t) {
        static uint64_t seen = 0, changed = 0;
        static bool fast = true;
        uint64_t frames = g_blits + GpuPresents();
        if (frames != seen) {
            seen = frames;
            changed = ts;
            if (!fast) {
                OH_NativeXComponent_ExpectedRateRange r{60, 120, 120};
                OH_NativeXComponent_SetExpectedFrameRateRange(c, &r);
                fast = true;
            }
        } else if (fast && ts - changed > 1000000000ULL) {
            OH_NativeXComponent_ExpectedRateRange r{1, 10, 10};
            OH_NativeXComponent_SetExpectedFrameRateRange(c, &r);
            fast = false;
        }
    });
    OH_NativeXComponent_SetExpectedFrameRateRange(nc, &rate);
    return exports;
}

napi_module g_module = {
    .nm_version = 1,
    .nm_flags = 0,
    .nm_filename = nullptr,
    .nm_register_func = Init,
    .nm_modname = "ohdisp",
    .nm_priv = nullptr,
    .reserved = {0},
};

}  // namespace

int64_t DesktopUid() { return g_desktopUid; }

extern "C" __attribute__((constructor)) void RegisterOhdispModule()
{
    napi_module_register(&g_module);
}
