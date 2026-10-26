// ohmarchy-docker-gate: route D's docker CLI reaches route I's dockerd through
// this socket, and route I's VM runs only while it is used. Root on the host,
// started at boot by route D's boot-start.sh.
// Each connection: only from uid --uid (SO_PEERCRED; route D's desktop user);
// if the VM is down, `ohmarchy-vm start` and wait for dockerd (about 10 s the
// first time), then the connection becomes the stdin/stdout of
// `ohmarchy-vm ssh docker system dial-stdio`, what docker's own ssh:// transport
// runs in the guest. A peer can do nothing but talk to that dockerd.
// Idle: when the gate started the VM, no connection has been open for --idle
// minutes and no container runs, `ohmarchy-vm stop`. A VM started by hand is
// never stopped. While another VM runs (HMV runs one at a time: 鸿融, OSEasy)
// the gate does not try, and the client gets an HTTP 503 that docker prints as
// "Error response from daemon: <the reason, in Chinese for the user>".
//   ohmarchy-docker-gate [--uid UID] [--idle MIN] <socket path>
//   (defaults: uid 60000, 3 min: 鸿融 and OSEasy need the hypervisor soon after)
#define _GNU_SOURCE
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
#define ANOTHER_VM "后台 Docker 虚拟机启动不了：鸿融或者 OSEasy 的虚拟机正在运行，请先关掉它"

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

static void say(const char *fmt, const char *arg)
{
    char t[32];
    time_t now = time(NULL);
    strftime(t, sizeof(t), "%F %T", localtime(&now));
    printf("%s ", t);
    printf(fmt, arg);
    printf("\n");
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
    long uid = 60000, idle_min = 3;
    while (argc > 2 && strncmp(argv[1], "--", 2) == 0) {
        if (strcmp(argv[1], "--uid") == 0)
            uid = strtol(argv[2], NULL, 10);
        else if (strcmp(argv[1], "--idle") == 0)
            idle_min = strtol(argv[2], NULL, 10);
        else
            break;
        argv += 2;
        argc -= 2;
    }
    if (argc != 2) {
        fprintf(stderr, "usage: %s [--uid UID] [--idle MIN] <socket path>\n", argv[0]);
        return 2;
    }
    signal(SIGPIPE, SIG_IGN);
    setvbuf(stdout, NULL, _IOLBF, 0);
    struct sockaddr_un a = {.sun_family = AF_UNIX};
    snprintf(a.sun_path, sizeof(a.sun_path), "%s", argv[1]);
    unlink(argv[1]);
    int ls = socket(AF_UNIX, SOCK_STREAM | SOCK_CLOEXEC, 0);
    if (ls < 0 || bind(ls, (struct sockaddr *)&a, sizeof(a)) < 0 || listen(ls, 32) < 0) {
        perror(argv[1]);
        return 1;
    }
    /* the peer check is what counts; the mode keeps others from even connecting */
    if (chown(argv[1], uid, uid) < 0 || chmod(argv[1], 0600) < 0)
        perror("chown/chmod");
    printf("gate on %s for uid %ld, idle stop after %ld min\n", argv[1], uid, idle_min);

    int ours = 0, active = 0;
    time_t last_used = time(NULL), last_fail = 0, last_check = 0;
    for (;;) {
        struct pollfd p = {ls, POLLIN, 0};
        int r = poll(&p, 1, 5000);
        while (waitpid(-1, NULL, WNOHANG) > 0)
            if (--active == 0)
                last_used = time(NULL);
        if (r < 0 && errno != EINTR) {
            perror("poll");
            return 1;
        }
        if (r > 0 && (p.revents & POLLIN)) {
            int fd = accept4(ls, NULL, NULL, SOCK_CLOEXEC);
            struct ucred cr = {0};
            socklen_t crlen = sizeof(cr);
            if (fd < 0)
                continue;
            if (getsockopt(fd, SOL_SOCKET, SO_PEERCRED, &cr, &crlen) < 0 || (long)cr.uid != uid) {
                printf("refused pid %d uid %u\n", (int)cr.pid, (unsigned)cr.uid);
                close(fd);
                continue;
            }
            last_used = time(NULL);
            if (!vm_running()) {
                ours = 0;
                if (sh("pidof stratovirt > /dev/null", NULL, 0) == 0) {
                    printf("another VM runs: not starting\n");
                    refuse(fd, ANOTHER_VM);
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
        if (stat(argv[1], &sb) < 0) {
            say("%s is gone (session ended), exiting", argv[1]);
            return 0;
        }
        /* idle: checked once a minute after the idle time is up */
        time_t now = time(NULL);
        if (ours && active == 0 && now - last_used >= idle_min * 60 && now - last_check >= 60) {
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
