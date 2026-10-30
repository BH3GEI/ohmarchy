// The Linux desktop's cursor as this window's own pointer. aquamarine's headless
// backend (desktop/patches) sends the cursor as its own buffer ("OHDC" on the export
// socket) instead of Hyprland drawing it into every frame, where it trailed the hand
// by a frame's way through the GPU. Here it becomes a HarmonyOS custom cursor, drawn
// by the system at the pointer's position at once, with its shape (I-beam, resize
// arrows...). HarmonyOS may drop a custom cursor when the pointer leaves and comes
// back (OH_Input_SetCustomCursor's notes): hover-enter sets it again.
#include "cursor.h"

#include <hilog/log.h>
#include <multimedia/image_framework/image/pixelmap_native.h>
#include <multimodalinput/oh_input_manager.h>
#include <multimodalinput/oh_pointer_style.h>

#include <atomic>
#include <condition_variable>
#include <cstring>
#include <mutex>
#include <thread>
#include <vector>

#undef LOG_DOMAIN
#undef LOG_TAG
#define LOG_DOMAIN 0x0D0D
#define LOG_TAG "ohdisp"

namespace {

std::atomic<int32_t> g_windowId{-1};
std::mutex g_mu;
std::condition_variable g_cv;
// the cursor to show (RGBA rows, tight), and whether there is one to apply
std::vector<uint8_t> g_px;
int g_w = 0, g_h = 0, g_hx = 0, g_hy = 0;
bool g_pending = false, g_reset = false, g_started = false;
// the last set was refused (the pointer was over another window: only the window under
// it may set it); set again at the next pointer event here
std::atomic<bool> g_refused{false};
// set again after a refusal, from a pointer event here: refused again means it will not
// work, and the desktop draws its cursor itself (once)
std::atomic<bool> g_retrying{false}, g_soft{false};

void Apply(const std::vector<uint8_t> &px, int w, int h, int hx, int hy)
{
    const int32_t win = g_windowId.load();
    if (win < 0) {
        return;
    }
    static const uint8_t clear[4] = {0, 0, 0, 0};
    std::vector<uint8_t> data = w > 0 && h > 0 ? px : std::vector<uint8_t>(clear, clear + 4);
    if (w <= 0 || h <= 0) {  // no cursor (Linux hid it): a transparent one
        w = h = 1;
        hx = hy = 0;
    }
    OH_Pixelmap_InitializationOptions *opts = nullptr;
    OH_PixelmapNative *pm = nullptr;
    OH_PixelmapInitializationOptions_Create(&opts);
    OH_PixelmapInitializationOptions_SetWidth(opts, static_cast<uint32_t>(w));
    OH_PixelmapInitializationOptions_SetHeight(opts, static_cast<uint32_t>(h));
    OH_PixelmapInitializationOptions_SetSrcPixelFormat(opts, PIXEL_FORMAT_RGBA_8888);
    OH_PixelmapInitializationOptions_SetPixelFormat(opts, PIXEL_FORMAT_RGBA_8888);
    OH_PixelmapInitializationOptions_SetAlphaType(opts, PIXELMAP_ALPHA_TYPE_PREMULTIPLIED);
    Image_ErrorCode ie = OH_PixelmapNative_CreatePixelmap(data.data(), data.size(), opts, &pm);
    OH_PixelmapInitializationOptions_Release(opts);
    if (ie != IMAGE_SUCCESS || pm == nullptr) {
        OH_LOG_Print(LOG_APP, LOG_ERROR, LOG_DOMAIN, LOG_TAG, "cursor: pixelmap %{public}dx%{public}d: %{public}d", w, h, ie);
        return;
    }
    Input_CustomCursor *cur = OH_Input_CustomCursor_Create(pm, hx, hy);
    Input_CursorConfig *cfg = OH_Input_CursorConfig_Create(false);
    Input_Result r = OH_Input_SetCustomCursor(win, cur, cfg);
    g_refused = r != INPUT_SUCCESS;
    if (g_retrying.exchange(false) && r != INPUT_SUCCESS && !g_soft.exchange(true)) {
        OH_LOG_Print(LOG_APP, LOG_WARN, LOG_DOMAIN, LOG_TAG, "cursor: refused here too: the desktop draws it");
        CursorSoftFallback();
    }
    static int logged = 0;
    if (r != INPUT_SUCCESS || logged < 5) {
        logged++;
        OH_LOG_Print(LOG_APP, LOG_INFO, LOG_DOMAIN, LOG_TAG,
                     "cursor: %{public}dx%{public}d hotspot %{public}d,%{public}d on window %{public}d -> %{public}d", w, h, hx,
                     hy, win, r);
    }
    OH_Input_CursorConfig_Destroy(&cfg);
    OH_Input_CustomCursor_Destroy(&cur);
    OH_PixelmapNative_Release(pm);
}

// one thread makes the system calls (IPC), off the frame loop and the UI thread
void Worker()
{
    for (;;) {
        std::vector<uint8_t> px;
        int w, h, hx, hy;
        bool reset;
        {
            std::unique_lock<std::mutex> lk(g_mu);
            g_cv.wait(lk, [] { return g_pending || g_reset; });
            reset = g_reset;
            g_reset = false;
            g_pending = false;
            px = g_px;
            w = g_w;
            h = g_h;
            hx = g_hx;
            hy = g_hy;
        }
        if (reset) {
            const int32_t win = g_windowId.load();
            if (win >= 0) {
                OH_Input_SetPointerStyle(win, DEFAULT);
            }
            continue;
        }
        Apply(px, w, h, hx, hy);
    }
}

void Kick()
{
    if (!g_started) {
        g_started = true;
        std::thread(Worker).detach();
    }
    g_cv.notify_one();
}

}  // namespace

void CursorSetWindow(int32_t id)
{
    if (g_windowId.exchange(id) != id) {
        OH_LOG_Print(LOG_APP, LOG_INFO, LOG_DOMAIN, LOG_TAG, "cursor: window %{public}d", id);
    }
}

void CursorUpdate(const uint8_t *map, int w, int h, int stride, bool rgb, int hx, int hy)
{
    std::lock_guard<std::mutex> lk(g_mu);
    g_px.assign(static_cast<size_t>(w > 0 ? w : 0) * (h > 0 ? h : 0) * 4, 0);
    for (int y = 0; map != nullptr && y < h; y++) {
        const uint8_t *s = map + static_cast<size_t>(y) * stride;
        uint8_t *d = g_px.data() + static_cast<size_t>(y) * w * 4;
        for (int x = 0; x < w; x++, s += 4, d += 4) {
            // DRM ARGB8888 is B,G,R,A in memory, ABGR8888 R,G,B,A: to R,G,B,A
            d[0] = rgb ? s[0] : s[2];
            d[1] = s[1];
            d[2] = rgb ? s[2] : s[0];
            d[3] = s[3];
        }
    }
    g_w = map != nullptr ? w : 0;
    g_h = map != nullptr ? h : 0;
    g_hx = hx;
    g_hy = hy;
    g_pending = true;
    g_reset = false;
    Kick();
}

void CursorReapply()
{
    std::lock_guard<std::mutex> lk(g_mu);
    if (g_w > 0 || !g_px.empty()) {
        g_pending = true;
        Kick();
    }
}

void CursorRetryIfRefused()
{
    if (g_refused.exchange(false)) {
        g_retrying = true;
        CursorReapply();
    }
}

void CursorReset()
{
    std::lock_guard<std::mutex> lk(g_mu);
    g_px.clear();
    g_w = g_h = 0;
    g_pending = false;
    g_reset = true;
    Kick();
}
