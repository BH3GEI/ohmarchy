// vote120: a frame-rate vote of 120 Hz from a small, transparent window.
//
// HarmonyOS picks the panel's refresh rate from the votes of the visible
// windows. Oseasy's VM window never votes, so the panel idles at 60 Hz even
// while the VM delivers 120 frames/s. This app's XComponent votes {60, 120, 120}
// (OH_NativeXComponent_SetExpectedFrameRateRange; no permission involved). The
// vote takes effect with a frame callback registered; the callback also counts
// how often the system calls it, which is the rate this window actually gets.
// Optionally (setDraw(true), the default) it presents a fully transparent buffer
// on every frame, to keep the layer active for the frame-rate manager.
#include <ace/xcomponent/native_interface_xcomponent.h>
#include <hilog/log.h>
#include <napi/native_api.h>
#include <native_buffer/buffer_common.h>
#include <native_buffer/native_buffer.h>
#include <native_window/external_window.h>
#include <sys/mman.h>
#include <atomic>
#include <cstdio>
#include <cstring>
#include <mutex>
#include <unistd.h>

#define LOG_TAG "vote120"
#define LOGI(...) OH_LOG_Print(LOG_APP, LOG_INFO, 0x0120, LOG_TAG, __VA_ARGS__)

namespace {

OH_NativeXComponent_Callback g_cb;
std::mutex g_mu;
OHNativeWindow *g_win = nullptr;
uint64_t g_w = 0, g_h = 0;
std::atomic<bool> g_draw{true};
std::atomic<int> g_cbRate{0};     // frame callbacks in the last second
std::atomic<int> g_presents{0};   // buffers presented in the last second
int g_min = 60, g_max = 120, g_expected = 120;

void PresentTransparent()
{
    std::lock_guard<std::mutex> lk(g_mu);
    if (!g_win || !g_w || !g_h) {
        return;
    }
    OHNativeWindowBuffer *buf = nullptr;
    int fence = -1;
    if (OH_NativeWindow_NativeWindowRequestBuffer(g_win, &buf, &fence) != 0 || !buf) {
        return;
    }
    if (fence >= 0) {
        close(fence);
    }
    BufferHandle *bh = OH_NativeWindow_GetBufferHandleFromNative(buf);
    if (bh) {
        void *map = bh->virAddr;
        bool mapped = false;
        if (!map) {
            map = mmap(nullptr, static_cast<size_t>(bh->size), PROT_READ | PROT_WRITE, MAP_SHARED, bh->fd, 0);
            mapped = map != MAP_FAILED;
        }
        if (map && map != MAP_FAILED) {
            memset(map, 0, static_cast<size_t>(bh->size));   // RGBA 0: transparent
            if (mapped) {
                munmap(map, static_cast<size_t>(bh->size));
            }
        }
    }
    Region region{nullptr, 0};
    OH_NativeWindow_NativeWindowFlushBuffer(g_win, buf, -1, region);
}

void OnFrame(OH_NativeXComponent *, uint64_t ts, uint64_t)
{
    static uint64_t start = 0;
    static int cbs = 0, presents = 0;
    if (!start) {
        start = ts;
    }
    cbs++;
    if (g_draw) {
        PresentTransparent();
        presents++;
    }
    if (ts - start >= 1000000000ULL) {
        g_cbRate = cbs;
        g_presents = presents;
        LOGI("frame callbacks %{public}d/s, presents %{public}d/s", cbs, presents);
        cbs = presents = 0;
        start = ts;
    }
}

void OnSurfaceCreated(OH_NativeXComponent *c, void *window)
{
    std::lock_guard<std::mutex> lk(g_mu);
    g_win = static_cast<OHNativeWindow *>(window);
    OH_NativeXComponent_GetXComponentSize(c, window, &g_w, &g_h);
    OH_NativeWindow_NativeWindowHandleOpt(g_win, SET_FORMAT, NATIVEBUFFER_PIXEL_FMT_RGBA_8888);
    OH_NativeWindow_NativeWindowHandleOpt(g_win, SET_BUFFER_GEOMETRY, static_cast<int>(g_w), static_cast<int>(g_h));
    OH_NativeWindow_NativeWindowHandleOpt(g_win, SET_USAGE,
        static_cast<uint64_t>(NATIVEBUFFER_USAGE_CPU_READ | NATIVEBUFFER_USAGE_CPU_WRITE | NATIVEBUFFER_USAGE_MEM_DMA));
    LOGI("surface %{public}llux%{public}llu", static_cast<unsigned long long>(g_w),
         static_cast<unsigned long long>(g_h));
}

void OnSurfaceChanged(OH_NativeXComponent *c, void *window)
{
    std::lock_guard<std::mutex> lk(g_mu);
    OH_NativeXComponent_GetXComponentSize(c, window, &g_w, &g_h);
    if (g_win) {
        OH_NativeWindow_NativeWindowHandleOpt(g_win, SET_BUFFER_GEOMETRY, static_cast<int>(g_w), static_cast<int>(g_h));
    }
}

void OnSurfaceDestroyed(OH_NativeXComponent *, void *)
{
    std::lock_guard<std::mutex> lk(g_mu);
    g_win = nullptr;
}

void DispatchTouch(OH_NativeXComponent *, void *) {}

napi_value GetStatus(napi_env env, napi_callback_info)
{
    char s[128];
    snprintf(s, sizeof(s), "vote %d-%d (%d) Hz: callbacks %d/s, presents %d/s", g_min, g_max, g_expected,
             g_cbRate.load(), g_presents.load());
    napi_value v;
    napi_create_string_utf8(env, s, NAPI_AUTO_LENGTH, &v);
    return v;
}

napi_value SetDraw(napi_env env, napi_callback_info info)
{
    size_t argc = 1;
    napi_value arg;
    napi_get_cb_info(env, info, &argc, &arg, nullptr, nullptr);
    bool on = true;
    if (argc >= 1) {
        napi_get_value_bool(env, arg, &on);
    }
    g_draw = on;
    return nullptr;
}

napi_value Init(napi_env env, napi_value exports)
{
    napi_property_descriptor desc[] = {
        {"getStatus", nullptr, GetStatus, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"setDraw", nullptr, SetDraw, nullptr, nullptr, nullptr, napi_default, nullptr},
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
    g_cb.DispatchTouchEvent = DispatchTouch;
    OH_NativeXComponent_RegisterCallback(nc, &g_cb);
    OH_NativeXComponent_RegisterOnFrameCallback(nc, OnFrame);
    OH_NativeXComponent_ExpectedRateRange rate{g_min, g_max, g_expected};
    OH_NativeXComponent_SetExpectedFrameRateRange(nc, &rate);
    return exports;
}

napi_module g_module = {
    .nm_version = 1,
    .nm_flags = 0,
    .nm_filename = nullptr,
    .nm_register_func = Init,
    .nm_modname = "vote120",
    .nm_priv = nullptr,
    .reserved = {0},
};

}  // namespace

extern "C" __attribute__((constructor)) void RegisterVote120Module()
{
    napi_module_register(&g_module);
}
