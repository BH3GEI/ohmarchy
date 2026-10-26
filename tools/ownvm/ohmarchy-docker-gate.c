// ohmarchy-docker-gate: route D's docker CLI reaches route I's dockerd through
// this socket, and route I's VM runs only while it is used. Root on the host;
// `omarchy desktop start` (also at boot) runs it with the socket at /tmp in
// route D's Arch, reached as /proc/<session>/root/tmp/...: when that session
// ends, the path is gone and so is the gate, until the next desktop start.
// Each connection: only from uid --uid (SO_PEERCRED; route D's desktop user);
// if the VM is down, `ohmarchy-vm start` and wait for dockerd (about 10 s the
// first time), then the connection becomes the stdin/stdout of
// `ohmarchy-vm ssh docker system dial-stdio`, what docker's own ssh:// transport
// runs in the guest. A peer can do nothing but talk to that dockerd.
// Idle: when the gate started the VM, no connection has been open for --idle-s
// seconds and no container runs, `ohmarchy-vm stop`. A VM started by hand is
// never stopped. While another VM runs (HMV runs one at a time: 鸿融, OSEasy)
// the gate does not try, and the client gets an HTTP 503 that docker prints as
// "Error response from daemon: <the reason, in Chinese for the user>".
// --ctl PATH: a second socket, same peer check, one line per connection:
// `running` (quick), `status` or `stop` (only with no container running and
// no docker connection open); the answer is one line, "0 " or "1 " (failed/refused) and the text.
// route D's `docker-vm` command and its menu entry use it.
// --on-start CMD: run (detached, through /system/bin/sh) after the gate started
// the VM: route D's notification that the VM runs and how it stops.
// --on-refuse CMD: run as `CMD APP` (detached, at most every 20 s) when another
// VM runs, APP being the app that runs it (鸿融, OSEasy, or 另一个应用, from the
// bundle name in that StratoVirt's command line): a HarmonyOS notification.
//   ohmarchy-docker-gate [--uid UID] [--idle-s SEC | --idle MIN] [--ctl PATH]
//                        [--on-start CMD] [--on-refuse CMD] <socket path>
//   (defaults: uid 60000, 30 s: in the demo 鸿融 starts right after Docker, and
//   nobody types a command to stop the VM; supervisor, 2026-10-26)
#define _GNU_SOURCE
#include <dirent.h>
#include <errno.h>
#include <fcntl.h>
#include <poll.h>
#include <signal.h>
#include <stddef.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/socket.h>
#include <sys/stat.h>
#include <sys/time.h>
#include <sys/un.h>
#include <sys/wait.h>
#include <time.h>
#include <unistd.h>

#define VM "/data/local/kaidashi/bin/ohmarchy-vm"
#define ANOTHER_VM "后台 Docker 虚拟机启动不了：%s 的虚拟机正在运行（同一时间只能开一台虚拟机），请先关掉它"

/* sh -c CMD; with out, its stdout is captured there, else it goes to our log
 * (no pipe then: `ohmarchy-vm start` leaves the VM's processes behind) */
static int sh(const char *cmd, char *out, size_t outlen)
{
    int p[2] = {-1, -1};
    if (out && pipe(p) < 0)
        return -1;
    pid_t pid = fork();
    if (pid == 0) {
        dup2(open("/dev/null", 0), 0);
        if (out) {
            close(p[0]);
            dup2(p[1], 1);
        }
        execl("/system/bin/sh", "sh", "-c", cmd, (char *)NULL);
        _exit(127);
    }
    if (out) {
        close(p[1]);
        size_t n = 0;
        ssize_t r;
        while (n + 1 < outlen && (r = read(p[0], out + n, outlen - 1 - n)) > 0)
            n += r;
        out[n] = 0;
        close(p[0]);
    }
    int st;
    if (pid < 0 || waitpid(pid, &st, 0) < 0)
        return -1;
    return WIFEXITED(st) ? WEXITSTATUS(st) : -1;
}

static int vm_running(void) { return sh("sh " VM " running", NULL, 0) == 0; }

/* docker's output must not go straight into the ssh channel on this host
 * (it can hang there for good: docs/demo.md), hence the redirects and pipes */
static int dockerd_answers(void)
{
    return sh("timeout -s KILL 15 sh " VM " ssh 'docker info > /dev/null 2>&1' > /dev/null 2>&1", NULL, 0) == 0;
}

static int containers_running(void)
{
    char out[32] = "";
    if (sh("timeout -s KILL 20 sh " VM " ssh 'docker ps -q | wc -l' 2>/dev/null", out, sizeof(out)) != 0)
        return -1; /* unknown: treated as busy */
    return atoi(out);
}

/* the app whose VM runs, NULL if no StratoVirt runs: the VM apps' StratoVirt
 * command lines name their bundle in every socket and disk path */
static const char *other_vm(void)
{
    static const char *apps[][2] = {{"com.huawei.medivh", "鸿融"}, {"com.oseasy1.ohvm", "OSEasy"}};
    const char *who = NULL;
    DIR *d = opendir("/proc");
    struct dirent *e;
    while (d && (e = readdir(d))) {
        char path[64], c[8192];
        if (e->d_name[0] < '0' || e->d_name[0] > '9')
            continue;
        snprintf(path, sizeof(path), "/proc/%s/cmdline", e->d_name);
        int fd = open(path, O_RDONLY);
        if (fd < 0)
            continue;
        ssize_t n = read(fd, c, sizeof(c) - 1);
        close(fd);
        if (n <= 0)
            continue;
        c[n] = 0; /* argv[0] alone, then the rest with the NULs made spaces */
        const char *base = strrchr(c, '/') ? strrchr(c, '/') + 1 : c;
        if (strcmp(base, "stratovirt") != 0)
            continue;
        for (ssize_t i = 0; i < n; i++)
            if (!c[i])
                c[i] = ' ';
        who = "另一个应用";
        for (size_t i = 0; i < sizeof(apps) / sizeof(apps[0]); i++)
            if (strstr(c, apps[i][0]))
                who = apps[i][1];
        break;
    }
    if (d)
        closedir(d);
    return who;
}

static void say(const char *fmt, const char *arg)
{
    char t[32];
    time_t now = time(NULL);
    strftime(t, sizeof(t), "%F %T", localtime(&now));
    printf("%s ", t);
    printf(fmt, arg);
    printf("\n");
}

/* CMD in a grandchild, so that waitpid(-1) in the main loop only sees proxies */
static void run_detached(const char *cmd)
{
    pid_t pid = fork();
    if (pid == 0) {
        if (fork() == 0) {
            setsid();
            dup2(open("/dev/null", 0), 0);
            execl("/system/bin/sh", "sh", "-c", cmd, (char *)NULL);
            _exit(127);
        }
        _exit(0);
    }
    if (pid > 0)
        waitpid(pid, NULL, 0);
}

static int listen_on(const char *path, long uid)
{
    struct sockaddr_un a = {.sun_family = AF_UNIX};
    snprintf(a.sun_path, sizeof(a.sun_path), "%s", path);
    unlink(path);
    int fd = socket(AF_UNIX, SOCK_STREAM | SOCK_CLOEXEC, 0);
    if (fd < 0 || bind(fd, (struct sockaddr *)&a, sizeof(a)) < 0 || listen(fd, 32) < 0) {
        perror(path);
        return -1;
    }
    /* the peer check is what counts; the mode keeps others from even connecting */
    if (chown(path, uid, uid) < 0 || chmod(path, 0600) < 0)
        perror("chown/chmod");
    return fd;
}

/* accept, and keep the connection only from uid */
static int accept_from(int ls, long uid)
{
    int fd = accept4(ls, NULL, NULL, SOCK_CLOEXEC);
    struct ucred cr = {0};
    socklen_t crlen = sizeof(cr);
    if (fd >= 0 && (getsockopt(fd, SOL_SOCKET, SO_PEERCRED, &cr, &crlen) < 0 || (long)cr.uid != uid)) {
        printf("refused pid %d uid %u\n", (int)cr.pid, (unsigned)cr.uid);
        close(fd);
        return -1;
    }
    return fd;
}

static void reply(int fd, int code, const char *text)
{
    char b[512];
    int n = snprintf(b, sizeof(b), "%d %s\n", code, text);
    (void)!write(fd, b, n);
    close(fd);
}

static void refuse(int fd, const char *why)
{
    char req[4096], resp[512];
    struct timeval tv = {2, 0};
    setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &tv, sizeof(tv));
    (void)!read(fd, req, sizeof(req)); /* the request, so that closing does not reset it */
    int n = snprintf(resp, sizeof(resp), "{\"message\":\"%s\"}\n", why);
    char head[256];
    int h = snprintf(head, sizeof(head),
                     "HTTP/1.1 503 Service Unavailable\r\nContent-Type: application/json\r\n"
                     "Content-Length: %d\r\nConnection: close\r\n\r\n", n);
    (void)!write(fd, head, h);
    (void)!write(fd, resp, n);
    close(fd);
}

int main(int argc, char **argv)
{
    long uid = 60000, idle_s = 30;
    const char *ctl = NULL, *on_start = NULL, *on_refuse = NULL;
    while (argc > 2 && strncmp(argv[1], "--", 2) == 0) {
        if (strcmp(argv[1], "--uid") == 0)
            uid = strtol(argv[2], NULL, 10);
        else if (strcmp(argv[1], "--idle") == 0)
            idle_s = 60 * strtol(argv[2], NULL, 10);
        else if (strcmp(argv[1], "--idle-s") == 0)
            idle_s = strtol(argv[2], NULL, 10);
        else if (strcmp(argv[1], "--ctl") == 0)
            ctl = argv[2];
        else if (strcmp(argv[1], "--on-start") == 0)
            on_start = argv[2];
        else if (strcmp(argv[1], "--on-refuse") == 0)
            on_refuse = argv[2];
        else
            break;
        argv += 2;
        argc -= 2;
    }
    if (argc != 2) {
        fprintf(stderr, "usage: %s [--uid UID] [--idle-s SEC] [--ctl PATH] [--on-start CMD] [--on-refuse CMD] <socket path>\n", argv[0]);
        return 2;
    }
    signal(SIGPIPE, SIG_IGN);
    setvbuf(stdout, NULL, _IOLBF, 0);
    int ls = listen_on(argv[1], uid), cs = ctl ? listen_on(ctl, uid) : -1;
    if (ls < 0 || (ctl && cs < 0))
        return 1;
    printf("gate on %s for uid %ld, idle stop after %ld s%s%s\n", argv[1], uid, idle_s,
           ctl ? ", control on " : "", ctl ? ctl : "");

    int ours = 0, active = 0;
    time_t last_used = time(NULL), last_fail = 0, last_check = 0, last_refused = 0;
    for (;;) {
        struct pollfd p[2] = {{ls, POLLIN, 0}, {cs, POLLIN, 0}};
        int r = poll(p, cs >= 0 ? 2 : 1, 5000);
        while (waitpid(-1, NULL, WNOHANG) > 0)
            if (--active == 0)
                last_used = time(NULL);
        if (r < 0 && errno != EINTR) {
            perror("poll");
            return 1;
        }
        if (r > 0 && cs >= 0 && (p[1].revents & POLLIN)) {
            int fd = accept_from(cs, uid);
            char line[32] = "";
            struct timeval tv = {2, 0};
            if (fd < 0)
                continue;
            setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &tv, sizeof(tv));
            ssize_t n = read(fd, line, sizeof(line) - 1);
            line[n > 0 ? n : 0] = 0;
            line[strcspn(line, "\r\n")] = 0;
            int up = vm_running();
            if (!up)
                ours = 0;
            if (strcmp(line, "running") == 0) { /* cheap, for menu conditions */
                reply(fd, up ? 0 : 1, up ? "running" : "stopped");
            } else if (strcmp(line, "status") == 0) {
                char t[256];
                if (!up) {
                    const char *who = other_vm();
                    if (who)
                        snprintf(t, sizeof(t), "Docker 虚拟机没有运行（%s 的虚拟机正在运行）", who);
                    reply(fd, 0, who ? t : "Docker 虚拟机没有运行，下次用 docker 时自动启动");
                    continue;
                }
                int c = containers_running();
                long left = idle_s - (time(NULL) - last_used);
                if (!ours)
                    snprintf(t, sizeof(t), "Docker 虚拟机正在运行（手动启动的，不会自动关闭），%d 个容器在运行", c);
                else if (active > 0 || c != 0)
                    snprintf(t, sizeof(t), "Docker 虚拟机正在运行，%d 个容器在运行，%d 个 docker 连接；都结束 %ld 秒后自动关闭", c, active, idle_s);
                else
                    snprintf(t, sizeof(t), "Docker 虚拟机正在运行，没有容器；约 %ld 秒后自动关闭", left > 0 ? left : 0);
                reply(fd, 0, t);
            } else if (strcmp(line, "stop") == 0) {
                char t[256];
                int c = up ? containers_running() : 0;
                if (!up) {
                    reply(fd, 0, "Docker 虚拟机没有运行");
                } else if (active > 0) {
                    snprintf(t, sizeof(t), "没有关闭：还有 %d 个 docker 连接在用（比如 docker logs -f），先结束它们", active);
                    reply(fd, 1, t);
                } else if (c != 0) {
                    if (c > 0)
                        snprintf(t, sizeof(t), "没有关闭：还有 %d 个容器在运行，先用 docker stop 停掉（docker ps 查看）", c);
                    else
                        snprintf(t, sizeof(t), "没有关闭：查不到容器状态");
                    reply(fd, 1, t);
                } else {
                    say("stop asked by %s", "docker-vm");
                    int ok = sh("sh " VM " stop", NULL, 0) == 0 && !vm_running();
                    ours = 0;
                    reply(fd, ok ? 0 : 1, ok ? "Docker 虚拟机已关闭，现在可以开鸿融或 OSEasy 的虚拟机" : "关闭失败，见 /data/local/kaidashi/ownvm/svc/gate.log");
                }
            } else {
                reply(fd, 1, "usage: running | status | stop");
            }
            continue;
        }
        if (r > 0 && (p[0].revents & POLLIN)) {
            int fd = accept_from(ls, uid);
            if (fd < 0)
                continue;
            last_used = time(NULL);
            if (!vm_running()) {
                ours = 0;
                const char *who = other_vm();
                if (who) {
                    char why[256];
                    snprintf(why, sizeof(why), ANOTHER_VM, who);
                    say("another VM runs (%s): not starting", who);
                    refuse(fd, why);
                    if (on_refuse && time(NULL) - last_refused >= 20) {
                        char cmd[512];
                        snprintf(cmd, sizeof(cmd), "%s '%s'", on_refuse, who);
                        run_detached(cmd);
                        last_refused = time(NULL);
                    }
                    continue;
                }
                if (time(NULL) - last_fail < 30) {
                    refuse(fd, "后台 Docker 虚拟机刚才没能启动，请稍后再试（日志：/data/local/kaidashi/ownvm/svc/gate.log）");
                    continue;
                }
                say("starting the VM for %s", "a client");
                int ok = sh("sh " VM " start", NULL, 0) == 0;
                ours = ok; /* also when dockerd fails: the idle stop takes it down */
                for (int i = 0; ok && i < 40 && !dockerd_answers(); i++)
                    sleep(1);
                if (!ok || !dockerd_answers()) {
                    last_fail = time(NULL);
                    say("%s", ok ? "dockerd does not answer" : "start failed");
                    refuse(fd, ok ? "后台 Docker 虚拟机已开机，但 dockerd 没有响应（日志：/data/local/kaidashi/ownvm/svc/gate.log）"
                              : "后台 Docker 虚拟机启动失败（日志：/data/local/kaidashi/ownvm/svc/gate.log）");
                    continue;
                }
                say("%s", "VM up, dockerd answers");
                if (on_start)
                    run_detached(on_start);
            }
            pid_t pid = fork();
            if (pid == 0) {
                dup2(fd, 0);
                dup2(fd, 1);
                execl("/system/bin/sh", "sh", VM, "ssh", "docker", "system", "dial-stdio", (char *)NULL);
                _exit(127);
            }
            close(fd);
            if (pid > 0)
                active++;
            continue;
        }
        struct stat sb;
        if (stat(argv[1], &sb) < 0 || (ctl && stat(ctl, &sb) < 0)) {
            say("%s is gone (session ended), exiting", argv[1]);
            return 0;
        }
        /* idle: checked every 10 s once the idle time is up (each check asks the
         * guest for its running containers) */
        time_t now = time(NULL);
        if (ours && active == 0 && now - last_used >= idle_s && now - last_check >= 10) {
            last_check = now;
            if (!vm_running()) {
                ours = 0;
                continue;
            }
            int c = containers_running();
            if (c != 0) {
                if (c > 0)
                    printf("idle, but %d container(s) running: VM stays\n", c);
                continue;
            }
            say("idle for %s, stopping the VM", "a while");
            sh("sh " VM " stop", NULL, 0);
            ours = 0;
        }
    }
}
