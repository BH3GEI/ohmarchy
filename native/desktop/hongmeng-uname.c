// Preloaded in the chroot: HongMeng reports sysname "HarmonyOS" and release
// "HongMeng Kernel 1.11.13.0"; cmake, meson and kmod expect Linux and a numeric release.
#define _GNU_SOURCE
#include <dlfcn.h>
#include <string.h>
#include <sys/utsname.h>

int uname(struct utsname *u)
{
    static int (*real)(struct utsname *);
    if (!real)
        real = dlsym(RTLD_NEXT, "uname");
    int r = real(u);
    if (r == 0 && strcmp(u->sysname, "Linux") != 0) {
        strcpy(u->sysname, "Linux");
        strcpy(u->release, "6.6.0-hongmeng");
    }
    return r;
}
