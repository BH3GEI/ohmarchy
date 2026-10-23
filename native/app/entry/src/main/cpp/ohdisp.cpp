// ohdisp: show a Linux Wayland desktop in an XComponent surface and send mouse,
// touch and key input back. Frames come from the compositor's frame export (its
// output buffers, shared as dmabufs over the abstract socket @ohmarchy-display);
// without it, from RFB (wayvnc on 127.0.0.1:5900). Input always goes over RFB.
#include <ace/xcomponent/native_interface_xcomponent.h>
#include <arkui/ui_input_event.h>
#include <hilog/log.h>
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
#include <cstddef>
#include <map>
#include <cstring>
#include <mutex>
#include <string>
#include <thread>
#include <vector>

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
const char *kExportName = "ohmarchy-display";
uint8_t g_buttons = 0;

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
    std::lock_guard<std::mutex> lk(g_winMu);
    if (g_win == nullptr || w <= 0 || h <= 0) {
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
            sleep(2);
            continue;
        }
        LOGI("frame export connected");
        g_shown = false;
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
        }
        for (auto &[id, b] : bufs) {
            if (b.map != nullptr) {
                munmap(b.map, b.size);
            }
            if (b.fd >= 0) {
                close(b.fd);
            }
        }
        close(fd);
        g_frameMode = false;
        g_shown = false;
        LOGE("frame export disconnected");
        sleep(1);
    }
}

void StartOnce()
{
    bool expected = false;
    if (g_started.compare_exchange_strong(expected, true)) {
        std::thread(FrameLoop).detach();
        std::thread(RfbLoop).detach();
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
    OH_NativeWindow_NativeWindowHandleOpt(g_win, SET_FORMAT, NATIVEBUFFER_PIXEL_FMT_RGBA_8888);
    OH_NativeWindow_NativeWindowHandleOpt(g_win, SET_USAGE,
        static_cast<uint64_t>(NATIVEBUFFER_USAGE_CPU_READ | NATIVEBUFFER_USAGE_CPU_WRITE | NATIVEBUFFER_USAGE_MEM_DMA));
    OH_NativeWindow_NativeWindowSetScalingModeV2(g_win, OH_SCALING_MODE_SCALE_TO_WINDOW_V2);
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
    int x, y;
    ToFb(ev.x, ev.y, &x, &y);
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
    SendPointer(x, y, g_buttons);
}

void OnHover(OH_NativeXComponent *, bool) {}

int g_lastX = 0, g_lastY = 0;

void OnAxis(OH_NativeXComponent *, ArkUI_UIInputEvent *event, ArkUI_UIInputEvent_Type)
{
    double v = OH_ArkUI_AxisEvent_GetVerticalAxisValue(event);
    int x, y;
    ToFb(OH_ArkUI_PointerEvent_GetX(event), OH_ArkUI_PointerEvent_GetY(event), &x, &y);
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
    if (!g_shown) {
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

napi_value Init(napi_env env, napi_value exports)
{
    napi_property_descriptor desc[] = {
        {"getStatus", nullptr, GetStatus, nullptr, nullptr, nullptr, napi_default, nullptr},
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

extern "C" __attribute__((constructor)) void RegisterOhdispModule()
{
    napi_module_register(&g_module);
}
