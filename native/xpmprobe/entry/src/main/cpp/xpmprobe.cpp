// XPM / executable-memory probe for HarmonyOS debug HAP (Route H no-root question).
// Tries each way to get runnable code memory, logs pass/fail + errno via hilog (tag XPMPROBE).
#include <napi/native_api.h>
#include <hilog/log.h>
#include <sys/mman.h>
#include <sys/syscall.h>
#include <sys/wait.h>
#include <unistd.h>
#include <fcntl.h>
#include <dlfcn.h>
#include <cstring>
#include <cerrno>
#include <cstdio>

#undef LOG_TAG
#define LOG_TAG "XPMPROBE"
#define LOGI(...) OH_LOG_Print(LOG_APP, LOG_INFO, 0xBEEF, LOG_TAG, __VA_ARGS__)

// A tiny aarch64 function: mov w0,#42 ; ret   -> returns 42 if the memory is really executable.
static const unsigned int CODE[2] = {0x52800540u /*mov w0,#42*/, 0xd65f03c0u /*ret*/};

static bool tryCall(void *mem) {
    memcpy(mem, CODE, sizeof(CODE));
    __builtin___clear_cache((char *)mem, (char *)mem + sizeof(CODE));
    using Fn = int (*)();
    int r = ((Fn)mem)();           // if the page isn't executable, this faults
    return r == 42;
}

static napi_value RunProbes(napi_env env, napi_callback_info) {
    long pg = sysconf(_SC_PAGESIZE);
    LOGI("=== XPM probe start, pagesize=%{public}ld uid=%{public}d ===", pg, (int)getuid());

    // (a) anonymous mmap PROT_EXEC directly
    {
        void *p = mmap(nullptr, pg, PROT_READ | PROT_WRITE | PROT_EXEC, MAP_PRIVATE | MAP_ANONYMOUS, -1, 0);
        if (p == MAP_FAILED) LOGI("(a) mmap RWX anon: FAIL errno=%{public}d(%{public}s)", errno, strerror(errno));
        else { LOGI("(a) mmap RWX anon: mapped @%{public}p; calling...", p);
               LOGI("(a) mmap RWX anon: call %{public}s", tryCall(p) ? "OK (executable!)" : "ran-but-wrong"); munmap(p, pg); }
    }
    // (b) mmap RW then mprotect to add EXEC
    {
        void *p = mmap(nullptr, pg, PROT_READ | PROT_WRITE, MAP_PRIVATE | MAP_ANONYMOUS, -1, 0);
        if (p == MAP_FAILED) { LOGI("(b) mmap RW: FAIL errno=%{public}d", errno); }
        else {
            memcpy(p, CODE, sizeof(CODE));
            int mp = mprotect(p, pg, PROT_READ | PROT_EXEC);
            if (mp != 0) LOGI("(b) mprotect RW->RX: FAIL errno=%{public}d(%{public}s)", errno, strerror(errno));
            else { __builtin___clear_cache((char*)p,(char*)p+sizeof(CODE));
                   LOGI("(b) mprotect RW->RX: ok; call %{public}s", ((int(*)())p)()==42?"OK (executable!)":"wrong"); }
            munmap(p, pg);
        }
    }
    // (c) memfd double-map: RW map to write, RX map to exec (defeats W^X if both allowed)
    {
        int fd = (int)syscall(SYS_memfd_create, "xpm", 0u);
        if (fd < 0) LOGI("(c) memfd_create: FAIL errno=%{public}d(%{public}s)", errno, strerror(errno));
        else {
            if (ftruncate(fd, pg) != 0) LOGI("(c) ftruncate: FAIL errno=%{public}d", errno);
            void *rw = mmap(nullptr, pg, PROT_READ | PROT_WRITE, MAP_SHARED, fd, 0);
            void *rx = mmap(nullptr, pg, PROT_READ | PROT_EXEC, MAP_SHARED, fd, 0);
            if (rw == MAP_FAILED || rx == MAP_FAILED)
                LOGI("(c) memfd dual-map: FAIL rw=%{public}d rx=%{public}d errno=%{public}d(%{public}s)",
                     rw!=MAP_FAILED, rx!=MAP_FAILED, errno, strerror(errno));
            else { memcpy(rw, CODE, sizeof(CODE)); __builtin___clear_cache((char*)rx,(char*)rx+sizeof(CODE));
                   LOGI("(c) memfd dual-map: ok; call %{public}s", ((int(*)())rx)()==42?"OK (executable!)":"wrong"); }
            if (rw!=MAP_FAILED) munmap(rw,pg); if (rx!=MAP_FAILED) munmap(rx,pg); close(fd);
        }
    }
    // (d) dlopen a system .so (proves dynamic loading of already-signed code works)
    {
        void *h = dlopen("libhilog_ndk.z.so", RTLD_NOW);
        LOGI("(d) dlopen system .so: %{public}s", h ? "OK" : dlerror());
        if (h) dlclose(h);
    }
    // (e) fork+execve ELFs. A tiny static ELF that exit(42)s makes success unambiguous;
    //     the child logs its own errno if execve fails, so we learn WHY (EACCES/EPERM/ENOEXEC).
    {
        const char *paths[] = {
            "/system/bin/toybox",                                              // system ELF (baseline)
            "/data/storage/el2/base/haps/entry/files/exit42",                  // our unsigned static ELF in sandbox
            "/data/storage/el2/base/haps/entry/files/exit42dyn",               // our dynamic ELF via its own ld
            nullptr};
        for (int i = 0; paths[i]; i++) {
            LOGI("(e) try %{public}s present=%{public}d x=%{public}d", paths[i],
                 access(paths[i], F_OK) == 0, access(paths[i], X_OK) == 0);
            pid_t pid = fork();
            if (pid == 0) {
                execl(paths[i], paths[i], (char*)nullptr);
                int e = errno;                       // execve failed
                OH_LOG_Print(LOG_APP, LOG_ERROR, 0xBEEF, LOG_TAG,
                    "(e) CHILD execve %{public}s FAILED errno=%{public}d(%{public}s)", paths[i], e, strerror(e));
                _exit(120 + (e & 7));
            } else if (pid > 0) { int st=0; waitpid(pid,&st,0);
                LOGI("(e) %{public}s -> %{public}s=%{public}d (42=ran-ok; 120+=execve-failed)",
                     paths[i], WIFEXITED(st)?"exit":"signal", WIFEXITED(st)?WEXITSTATUS(st):WTERMSIG(st)); }
            else LOGI("(e) fork FAIL errno=%{public}d", errno);
        }
    }
    LOGI("=== XPM probe done ===");
    napi_value r; napi_create_int32(env, 0, &r); return r;
}

static napi_value Init(napi_env env, napi_value exports) {
    napi_property_descriptor desc[] = {
        {"runProbes", nullptr, RunProbes, nullptr, nullptr, nullptr, napi_default, nullptr},
    };
    napi_define_properties(env, exports, 1, desc);
    return exports;
}
static napi_module g_module = { .nm_version = 1, .nm_flags = 0, .nm_filename = nullptr,
    .nm_register_func = Init, .nm_modname = "xpm", .nm_priv = nullptr, .reserved = {0} };
extern "C" __attribute__((constructor)) void RegisterModule(void) { napi_module_register(&g_module); }
