// libhwf_kits.z.so for route I's vhost-device-gpu (option A in docs/vm-own.md).
// The system virglrenderer dlopens a library of this name and asks it for the
// native window of scanout 0 (in 鸿融 that window is the VM app's, found through
// the WindowsFusion service). This one makes the window from another process's
// surface: route D's app logs its XComponent surface id, and testvm.sh puts the
// directory of this library first in vhost-device-gpu's LD_LIBRARY_PATH
// (TESTVM_GPU_LIBPATH) with the id in OHMARCHY_SURFACE_ID or in the file
// OHMARCHY_SURFACE_ID_FILE. Same entry points as route D's in-app stub
// (native/app/entry/src/main/cpp/hwf_kits.c).
//   $NDK/llvm/bin/clang --target=aarch64-linux-ohos --sysroot=$NDK/sysroot -O2 -fPIC \
//     -shared -o libhwf_kits.z.so hwf_kits_remote.c -lnative_window
#include <native_window/external_window.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>

static OHNativeWindow *g_window;

static uint64_t surface_id(void)
{
    const char *s = getenv("OHMARCHY_SURFACE_ID");
    if (s && *s) {
        return strtoull(s, NULL, 0);
    }
    const char *path = getenv("OHMARCHY_SURFACE_ID_FILE");
    unsigned long long id = 0;
    FILE *f = path ? fopen(path, "r") : NULL;
    if (f) {
        if (fscanf(f, "%llu", &id) != 1) {
            id = 0;
        }
        fclose(f);
    }
    return id;
}

__attribute__((visibility("default"))) OHNativeWindow *GetNativeWindow(int id)
{
    if (id != 0) {
        return NULL;
    }
    if (g_window == NULL) {
        uint64_t sid = surface_id();
        int32_t r = sid ? OH_NativeWindow_CreateNativeWindowFromSurfaceId(sid, &g_window) : -1;
        fprintf(stderr, "hwf_kits_remote: surface %llu -> window %p (rc %d)\n",
                (unsigned long long)sid, (void *)g_window, r);
        if (r != 0) {
            g_window = NULL;
        }
    }
    return g_window;
}

__attribute__((visibility("default"))) void ReleaseNativeWindow(int id)
{
    if (id == 0 && g_window != NULL) {
        OH_NativeWindow_DestroyNativeWindow(g_window);
        g_window = NULL;
    }
}

__attribute__((visibility("default"))) int HWFDisConnectWindow(int id) { (void)id; return 0; }
__attribute__((visibility("default"))) int VMDisConnectWindow(int id) { (void)id; return 0; }
