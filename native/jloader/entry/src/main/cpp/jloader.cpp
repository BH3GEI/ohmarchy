// Route J loader: dlopen a busybox compiled as a HAP-signed .so and run `sh -c <cmd>` in a
// forked child (fork is allowed; applets run in-process via FEATURE_SH_STANDALONE, no execve).
// Captures the child's stdout/stderr to a sandbox file and logs it (tag JLOADER).
#include <napi/native_api.h>
#include <hilog/log.h>
#include <dlfcn.h>
#include <unistd.h>
#include <fcntl.h>
#include <sys/wait.h>
#include <cstdio>
#include <cstring>
#include <cerrno>
#undef LOG_TAG
#define LOG_TAG "JLOADER"
#define LOGI(...) OH_LOG_Print(LOG_APP, LOG_INFO, 0xBEEF, LOG_TAG, __VA_ARGS__)

static const char *BB = "/data/storage/el1/bundle/libs/arm64/libbusybox.so";
static const char *OUT = "/data/storage/el2/base/haps/entry/files/jout.txt";

static napi_value RunBusybox(napi_env env, napi_callback_info info) {
    size_t argc = 1; napi_value args[1] = {nullptr};
    napi_get_cb_info(env, info, &argc, args, nullptr, nullptr);
    char cmd[4096] = {0}; size_t n = 0;
    if (argc >= 1) napi_get_value_string_utf8(env, args[0], cmd, sizeof(cmd), &n);
    if (n == 0) strcpy(cmd, "echo no-cmd");
    LOGI("=== J loader: sh -c \"%{public}s\" (bb=%{public}s present=%{public}d) ===", cmd, BB, access(BB, F_OK) == 0);

    unlink(OUT);
    pid_t pid = fork();
    if (pid == 0) {
        int fd = open(OUT, O_CREAT | O_WRONLY | O_TRUNC, 0644);
        if (fd >= 0) { dup2(fd, 1); dup2(fd, 2); if (fd > 2) close(fd); }
        void *h = dlopen(BB, RTLD_NOW | RTLD_GLOBAL);
        if (!h) { dprintf(2, "dlopen busybox FAILED: %s\n", dlerror()); _exit(111); }
        using MainFn = int (*)(int, char **);
        MainFn bbmain = (MainFn)dlsym(h, "main");
        if (!bbmain) { dprintf(2, "dlsym main FAILED: %s\n", dlerror()); _exit(112); }
        char a0[] = "sh", a1[] = "-c";
        char *av[] = {a0, a1, cmd, nullptr};
        dprintf(2, "[child pid %d] calling busybox main...\n", getpid());
        int rc = bbmain(3, av);
        dprintf(2, "[child] busybox main returned %d\n", rc);
        _exit(rc & 0xff);
    } else if (pid > 0) {
        int st = 0; waitpid(pid, &st, 0);
        LOGI("child exit=%{public}d", WIFEXITED(st) ? WEXITSTATUS(st) : -WTERMSIG(st));
        FILE *f = fopen(OUT, "r");
        if (f) { char line[1024]; int ln = 0;
            while (fgets(line, sizeof(line), f)) { size_t l = strlen(line); if (l && line[l-1]=='\n') line[l-1]=0;
                LOGI("OUT| %{public}s", line); if (++ln > 200) break; }
            fclose(f);
        } else LOGI("no output file");
    } else LOGI("fork FAILED errno=%{public}d", errno);
    LOGI("=== J loader done ===");
    napi_value r; napi_create_int32(env, 0, &r); return r;
}
static napi_value Init(napi_env env, napi_value exports) {
    napi_property_descriptor d[] = {{"runBusybox", nullptr, RunBusybox, nullptr, nullptr, nullptr, napi_default, nullptr}};
    napi_define_properties(env, exports, 1, d); return exports;
}
static napi_module g_module = {.nm_version=1,.nm_flags=0,.nm_filename=nullptr,.nm_register_func=Init,.nm_modname="jl",.nm_priv=nullptr,.reserved={0}};
extern "C" __attribute__((constructor)) void RegisterModule(void){ napi_module_register(&g_module); }
