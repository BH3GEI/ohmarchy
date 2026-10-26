// J+D loader for the display app. The app is multi-threaded, so fork+dlopen directly would
// risk deadlocking on another thread's loader/malloc lock. Instead, at module load we fork a
// single-threaded "spawner" child (a forked child inherits only the calling thread); the app
// talks to it over a socketpair, and the spawner fork+dlopens busybox per command. No root,
// no execve, no JIT: only dlopen of the HAP-signed libbusybox.so + fork.
#include <napi/native_api.h>
#include <hilog/log.h>
#include <dlfcn.h>
#include <unistd.h>
#include <sys/socket.h>
#include <sys/un.h>
#include <sys/wait.h>
#include <time.h>
#include <cstdint>
#include <cstdlib>
#include <cstring>
#include <cerrno>
#include <cstdio>
#include <dirent.h>
#include <fcntl.h>
#include <sys/stat.h>
#undef LOG_TAG
#define LOG_TAG "JLAPP"
#define LOGI(...) OH_LOG_Print(LOG_APP, LOG_INFO, 0xBEEF, LOG_TAG, __VA_ARGS__)

static const char *LIBDIR = "/data/storage/el1/bundle/libs/arm64";
static const char *BB = "/data/storage/el1/bundle/libs/arm64/libbusybox.so";
static const char *HY = "/data/storage/el1/bundle/libs/arm64/libhyprland.so";
// Short XDG_RUNTIME_DIR: Hyprland's socket is $XDG_RUNTIME_DIR/hypr/<~61-char sig>/.socket2.sock,
// and the sun_path limit is 108. files/run (…/base/files/run, 32) overflows ("Socket2 path is too
// long, IPC will not work" -> no hyprctl -> no output). base/r (24) -> worst case 105, fits.
static const char *RUNDIR = "/data/storage/el2/base/r";            // XDG_RUNTIME_DIR (0700)
static const char *VTEST_SOCK = "/data/storage/el2/base/files/vtest.sock"; // app's in-proc vtest
static int   g_sock = -1;      // app end of the socketpair
static pid_t g_spawner = -1;

// glvnd needs an EGL vendor JSON pointing at our mesa ICD. Our libs are renamed with an _ohm
// suffix to avoid binding to the system's libEGL/libGLESv2 (already loaded in the app process),
// but libEGL_mesa keeps its unique name. Write the JSON at launch and point glvnd at it.
static void write_egl_vendor(const char *dir){
    mkdir(dir, 0755);
    char path[512]; snprintf(path, sizeof(path), "%s/50_mesa.json", dir);
    int fd = open(path, O_CREAT|O_TRUNC|O_WRONLY, 0644);
    if(fd < 0) return;
    char j[256];
    int n = snprintf(j, sizeof(j),
        "{\n  \"file_format_version\":\"1.0.0\",\n  \"ICD\":{\"library_path\":\"%s/libEGL_mesa.so\"}\n}\n", LIBDIR);
    (void)!write(fd, j, n); close(fd);
}

// Launch Hyprland as a dlopen'd shared library (no execve/PIE: HAP has no ELF interpreter and
// HongMeng blocks exec). Runs in a detached grandchild of the single-threaded spawner. Never
// returns on success (the compositor event loop takes over). Env matches D's chroot desktop
// (native/desktop/ohmarchy-desktop) + the J in-app GPU path (OHMARCHY_LOCAL_GPU server).
static void launch_hyprland(const char *cfg){
    mkdir(RUNDIR, 0700);
    // Capture Hyprland/aquamarine stdout+stderr (throwError text, backend logs) to a file —
    // the app log doesn't carry a dlopen'd lib's stderr.
    { char lp[512]; snprintf(lp,sizeof(lp),"%s/hyprland.stderr",RUNDIR);
      int lf=open(lp,O_CREAT|O_TRUNC|O_WRONLY,0644);
      if(lf>=0){ dup2(lf,1); dup2(lf,2); if(lf>2) close(lf); } }
    char vendordir[512]; snprintf(vendordir, sizeof(vendordir), "%s/egl_vendor.d", RUNDIR);
    write_egl_vendor(vendordir);
    setenv("XDG_RUNTIME_DIR", RUNDIR, 1);
    setenv("VTEST_SOCKET_NAME", VTEST_SOCK, 1);          // mesa virpipe -> app's in-proc vtest
    setenv("HYPRLAND_SURFACELESS_GALLIUM_DRIVER", "virpipe", 1); // not global GALLIUM_DRIVER
    setenv("HYPRLAND_READBACK_PRESENT", "1", 1);         // present-by-tag, no full readback
    setenv("AQ_HEADLESS_EXPORT", "ohmarchy-display", 1); // aquamarine export socket
    setenv("MESA_PROCESS_NAME", "Hyprland", 1);          // vtest client name (u_process.c)
    setenv("__EGL_VENDOR_LIBRARY_DIRS", vendordir, 1);   // glvnd finds our 50_mesa.json
    setenv("XDG_SESSION_TYPE", "wayland", 1);
    setenv("XDG_CURRENT_DESKTOP", "Hyprland", 1);
    setenv("OMARCHY_PATH", "/usr/share/omarchy", 1);
    setenv("XKB_CONFIG_ROOT", "/data/storage/el2/base/files/xkb", 1); // bundled xkeyboard-config data
    if(!getenv("HOME")) setenv("HOME", RUNDIR, 1);
    // Minimal J config (Lua, D's hl.* API): headless output + full-screen redraw. The caller
    // may override with an explicit path; otherwise we write our own so Hyprland has a monitor.
    char cfgpath[512];
    if(cfg && cfg[0]){
        snprintf(cfgpath, sizeof(cfgpath), "%s", cfg);
    } else {
        snprintf(cfgpath, sizeof(cfgpath), "%s/hypr-j.lua", RUNDIR);
        int cf=open(cfgpath,O_CREAT|O_TRUNC|O_WRONLY,0644);
        if(cf>=0){
            const char *lua=
                "hl.monitor({ output = \"HEADLESS-2\", mode = \"1920x1280@120\", position = \"0x0\", scale = 1 })\n"
                "hl.config({ debug = { damage_tracking = 1 } })\n";
            (void)!write(cf,lua,strlen(lua)); close(cf);
        }
    }
    void *h = dlopen(HY, RTLD_NOW | RTLD_GLOBAL);
    if(!h){ dprintf(2, "dlopen hyprland FAILED: %s\n", dlerror()); _exit(121); }
    int(*hymain)(int,char**) = (int(*)(int,char**))dlsym(h, "main");
    if(!hymain){ dprintf(2, "dlsym main FAILED: %s\n", dlerror()); _exit(122); }
    char a0[]="Hyprland", c1[]="-c"; char *av[]={a0,c1,cfgpath,nullptr};
    _exit(hymain(3,av)&0xff);
}

static int readn(int fd, void *p, size_t n){ char*b=(char*)p; size_t g=0; while(g<n){ ssize_t k=read(fd,b+g,n-g); if(k<=0) return -1; g+=k; } return 0; }
static int writen(int fd, const void *p, size_t n){ const char*b=(const char*)p; size_t s=0; while(s<n){ ssize_t k=write(fd,b+s,n-s); if(k<=0) return -1; s+=k; } return 0; }

// Close every inherited fd except `keep` (and 0/1/2): the app holds live connections
// (@ohmarchy-display, vtest, @ohmarchy-audio, XComponent/OHAudio). If the spawner or the
// busybox it runs kept them open, the app closing a connection would not deliver EOF to the
// peer (Hyprland/broker would not notice the app went away).
static void close_inherited_fds(int keep){
    DIR *d = opendir("/proc/self/fd");
    if(!d){ return; }
    int dfd = dirfd(d);
    struct dirent *e;
    while((e=readdir(d))){
        int fd = atoi(e->d_name);
        if(fd>2 && fd!=keep && fd!=dfd) close(fd);
    }
    closedir(d);
}

// After Hyprland starts, its headless backend has no output until one is created. There is no
// Lua API to create one and J can't execve hyprctl, so talk the hyprctl socket1 protocol
// directly: poll $XDG_RUNTIME_DIR/hypr/<sig>/.socket.sock for up to ~10s, then send the command.
// Runs in the spawner (parent of the Hyprland grandchild); blocking here is fine during bring-up.
static int hyprctl_cmd(const char *cmd){
    char base[512]; snprintf(base,sizeof(base),"%s/hypr",RUNDIR);
    char sockpath[640]={0};
    for(int tries=0; tries<100 && !sockpath[0]; tries++){
        DIR *d=opendir(base);
        if(d){ struct dirent *e;
            while((e=readdir(d))){
                if(e->d_name[0]=='.') continue;
                char cand[640]; snprintf(cand,sizeof(cand),"%s/%s/.socket.sock",base,e->d_name);
                if(access(cand,F_OK)==0){ snprintf(sockpath,sizeof(sockpath),"%s",cand); break; }
            }
            closedir(d);
        }
        if(!sockpath[0]){ struct timespec ts={0,100*1000*1000}; nanosleep(&ts,nullptr); } // 100ms
    }
    if(!sockpath[0]){ LOGI("hyprctl: socket never appeared (%{public}s)",base); return -1; }
    int fd=socket(AF_UNIX,SOCK_STREAM,0); if(fd<0) return -1;
    struct sockaddr_un sa; memset(&sa,0,sizeof(sa)); sa.sun_family=AF_UNIX;
    snprintf(sa.sun_path,sizeof(sa.sun_path),"%s",sockpath);
    if(connect(fd,(struct sockaddr*)&sa,sizeof(sa))!=0){ LOGI("hyprctl connect fail errno=%{public}d",errno); close(fd); return -1; }
    writen(fd,cmd,strlen(cmd));
    char rep[256]={0}; ssize_t k=read(fd,rep,sizeof(rep)-1); if(k>0) rep[k]=0;
    LOGI("hyprctl '%{public}s' -> %{public}s", cmd, rep);
    close(fd); return 0;
}

// runs in the single-threaded spawner child; never returns
static void spawner_loop(int s){
    for(;;){
        uint32_t len; if(readn(s,&len,4)!=0) _exit(0);
        if(len>1u<<20) _exit(0);
        char *cmd=(char*)malloc(len+1); if(!cmd||readn(s,cmd,len)!=0) _exit(0); cmd[len]=0;
        // opcode 0x01 = launch Hyprland (long-running, detached): rest is the config path.
        if(len>=1 && (unsigned char)cmd[0]==0x01){
            pid_t hp=fork();
            if(hp==0){ // detach from the spawner: own session, drop stdio to the app log
                setsid(); close(s); launch_hyprland(cmd+1); _exit(0); // launch_hyprland never returns on success
            }
            free(cmd);
            // headless backend creates no output on its own; make one via the hyprctl socket.
            hyprctl_cmd("output create headless HEADLESS-2");
            uint32_t ok=0; writen(s,&ok,4);   // ack: launched. Hyprland runs for the app's
            continue;                         // lifetime; we don't wait on it (one zombie at most).
        }
        int pp[2]; if(pipe(pp)!=0){ free(cmd); continue; }
        pid_t g=fork();
        if(g==0){ // grandchild: run busybox sh -c cmd, output to the pipe
            close(pp[0]); dup2(pp[1],1); dup2(pp[1],2); if(pp[1]>2) close(pp[1]); close(s);
            void*h=dlopen(BB,RTLD_NOW|RTLD_GLOBAL);
            if(!h){ dprintf(2,"dlopen busybox FAILED: %s\n",dlerror()); _exit(111); }
            int(*bbmain)(int,char**)=(int(*)(int,char**))dlsym(h,"main");
            if(!bbmain){ dprintf(2,"dlsym main FAILED: %s\n",dlerror()); _exit(112); }
            char a0[]="sh",a1[]="-c"; char*av[]={a0,a1,cmd,nullptr};
            _exit(bbmain(3,av)&0xff);
        }
        close(pp[1]);
        size_t cap=8192,tot=0; char*out=(char*)malloc(cap); ssize_t k;
        while(out && (k=read(pp[0],out+tot,cap-tot))>0){ tot+=k; if(tot>=cap){ cap*=2; char*n2=(char*)realloc(out,cap); if(!n2)break; out=n2; } }
        close(pp[0]); int st=0; waitpid(g,&st,0);
        uint32_t olen=(uint32_t)tot; writen(s,&olen,4); if(tot) writen(s,out,tot);
        free(cmd); free(out);
    }
}

static void ensure_spawner(){
    if(g_spawner>0) return;
    int sv[2]; if(socketpair(AF_UNIX,SOCK_STREAM,0,sv)!=0){ LOGI("socketpair FAIL errno=%{public}d",errno); return; }
    pid_t p=fork();
    if(p==0){ close(sv[0]); close_inherited_fds(sv[1]); spawner_loop(sv[1]); _exit(0); }
    if(p<0){ LOGI("fork spawner FAIL errno=%{public}d",errno); close(sv[0]); close(sv[1]); return; }
    close(sv[1]); g_sock=sv[0]; g_spawner=p;
    LOGI("spawner forked pid=%{public}d (single-threaded; busybox=%{public}s)", p, BB);
}

static napi_value Start(napi_env env, napi_callback_info){
    // Tell the app's in-process GPU server (gpu.cpp) to act as the vtest broker on
    // VTEST_SOCK. Set in the app process BEFORE the window/XComponent is created.
    setenv("OHMARCHY_LOCAL_GPU", "1", 1);
    ensure_spawner(); napi_value r; napi_create_int32(env, g_spawner>0?0:-1, &r); return r;
}

// Launch Hyprland via the single-threaded spawner (opcode 0x01 + optional config path).
static napi_value StartHyprland(napi_env env, napi_callback_info info){
    size_t argc=1; napi_value a[1]={nullptr}; napi_get_cb_info(env,info,&argc,a,nullptr,nullptr);
    char cfg[1024]={0}; size_t n=0; if(argc>=1) napi_get_value_string_utf8(env,a[0],cfg,sizeof(cfg),&n);
    ensure_spawner();
    napi_value res;
    if(g_spawner<=0){ napi_create_int32(env,-1,&res); return res; }
    uint32_t len=(uint32_t)(1+n); char *buf=(char*)malloc(len); buf[0]=0x01; if(n) memcpy(buf+1,cfg,n);
    int rc = (writen(g_sock,&len,4)==0 && writen(g_sock,buf,len)==0) ? 0 : -1; free(buf);
    uint32_t ack=0; if(rc==0) readn(g_sock,&ack,4);   // wait for the "launched" ack
    LOGI("startHyprland(cfg=%{public}s) rc=%{public}d", cfg[0]?cfg:"(none)", rc);
    napi_create_int32(env, rc, &res); return res;
}

static napi_value RunSh(napi_env env, napi_callback_info info){
    size_t argc=1; napi_value a[1]={nullptr}; napi_get_cb_info(env,info,&argc,a,nullptr,nullptr);
    char cmd[8192]={0}; size_t n=0; if(argc>=1) napi_get_value_string_utf8(env,a[0],cmd,sizeof(cmd),&n);
    ensure_spawner();
    napi_value res;
    if(g_spawner<=0){ napi_create_string_utf8(env,"[jl] spawner unavailable",NAPI_AUTO_LENGTH,&res); return res; }
    uint32_t len=(uint32_t)n; if(writen(g_sock,&len,4)!=0||writen(g_sock,cmd,len)!=0){ napi_create_string_utf8(env,"[jl] send failed",NAPI_AUTO_LENGTH,&res); return res; }
    uint32_t olen=0; if(readn(g_sock,&olen,4)!=0){ napi_create_string_utf8(env,"[jl] recv failed",NAPI_AUTO_LENGTH,&res); return res; }
    char*out=(char*)malloc(olen+1); if(!out||(olen&&readn(g_sock,out,olen)!=0)){ free(out); napi_create_string_utf8(env,"[jl] recv body failed",NAPI_AUTO_LENGTH,&res); return res; }
    out[olen]=0; LOGI("runSh(%{public}s) -> %{public}u bytes", cmd, olen);
    napi_create_string_utf8(env,out,NAPI_AUTO_LENGTH,&res); free(out); return res;
}

static napi_value Init(napi_env env, napi_value exports){
    // Do NOT fork here: loading the module (switch off) must behave exactly as before.
    // The spawner is forked lazily in start()/runSh(), i.e. only when the jl switch is on.
    napi_property_descriptor d[]={
        {"start",nullptr,Start,nullptr,nullptr,nullptr,napi_default,nullptr},
        {"runSh",nullptr,RunSh,nullptr,nullptr,nullptr,napi_default,nullptr},
        {"startHyprland",nullptr,StartHyprland,nullptr,nullptr,nullptr,napi_default,nullptr},
    };
    napi_define_properties(env,exports,3,d); return exports;
}
static napi_module g_module={.nm_version=1,.nm_flags=0,.nm_filename=nullptr,.nm_register_func=Init,.nm_modname="bbload",.nm_priv=nullptr,.reserved={0}};
extern "C" __attribute__((constructor)) void RegisterBbload(void){ napi_module_register(&g_module); }
