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
#include <sys/wait.h>
#include <cstdint>
#include <cstdlib>
#include <cstring>
#include <cerrno>
#include <cstdio>
#undef LOG_TAG
#define LOG_TAG "JLAPP"
#define LOGI(...) OH_LOG_Print(LOG_APP, LOG_INFO, 0xBEEF, LOG_TAG, __VA_ARGS__)

static const char *BB = "/data/storage/el1/bundle/libs/arm64/libbusybox.so";
static int   g_sock = -1;      // app end of the socketpair
static pid_t g_spawner = -1;

static int readn(int fd, void *p, size_t n){ char*b=(char*)p; size_t g=0; while(g<n){ ssize_t k=read(fd,b+g,n-g); if(k<=0) return -1; g+=k; } return 0; }
static int writen(int fd, const void *p, size_t n){ const char*b=(const char*)p; size_t s=0; while(s<n){ ssize_t k=write(fd,b+s,n-s); if(k<=0) return -1; s+=k; } return 0; }

// runs in the single-threaded spawner child; never returns
static void spawner_loop(int s){
    for(;;){
        uint32_t len; if(readn(s,&len,4)!=0) _exit(0);
        if(len>1u<<20) _exit(0);
        char *cmd=(char*)malloc(len+1); if(!cmd||readn(s,cmd,len)!=0) _exit(0); cmd[len]=0;
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
    if(p==0){ close(sv[0]); spawner_loop(sv[1]); _exit(0); }
    if(p<0){ LOGI("fork spawner FAIL errno=%{public}d",errno); close(sv[0]); close(sv[1]); return; }
    close(sv[1]); g_sock=sv[0]; g_spawner=p;
    LOGI("spawner forked pid=%{public}d (single-threaded; busybox=%{public}s)", p, BB);
}

static napi_value Start(napi_env env, napi_callback_info){ ensure_spawner(); napi_value r; napi_create_int32(env, g_spawner>0?0:-1, &r); return r; }

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
    ensure_spawner();   // fork the spawner as early as possible (at module load)
    napi_property_descriptor d[]={
        {"start",nullptr,Start,nullptr,nullptr,nullptr,napi_default,nullptr},
        {"runSh",nullptr,RunSh,nullptr,nullptr,nullptr,napi_default,nullptr},
    };
    napi_define_properties(env,exports,2,d); return exports;
}
static napi_module g_module={.nm_version=1,.nm_flags=0,.nm_filename=nullptr,.nm_register_func=Init,.nm_modname="bbload",.nm_priv=nullptr,.reserved={0}};
extern "C" __attribute__((constructor)) void RegisterBbload(void){ napi_module_register(&g_module); }
