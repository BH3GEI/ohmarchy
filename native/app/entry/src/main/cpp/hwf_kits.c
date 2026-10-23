// libhwf_kits.z.so for the app: the system virglrenderer dlopens a library of this
// name and asks it for the native window to present scanout 0 into (in the 鸿融 VM
// that window comes from the VM app over IPC). Here it is the app's own XComponent
// window, handed over by ohdisp before the renderer starts.
#include <native_window/external_window.h>
#include <stddef.h>

static OHNativeWindow *g_window;
static void (*g_onUse)(void);

__attribute__((visibility("default"))) void OhmarchyHwfSetWindow(OHNativeWindow *window, void (*onUse)(void))
{
    g_window = window;
    g_onUse = onUse;
}

__attribute__((visibility("default"))) OHNativeWindow *GetNativeWindow(int id)
{
    if (id != 0 || g_window == NULL) {
        return NULL;
    }
    if (g_onUse) {
        g_onUse();
    }
    return g_window;
}

__attribute__((visibility("default"))) void ReleaseNativeWindow(int id) { (void)id; }
__attribute__((visibility("default"))) int HWFDisConnectWindow(int id) { (void)id; return 0; }
__attribute__((visibility("default"))) int VMDisConnectWindow(int id) { (void)id; return 0; }
