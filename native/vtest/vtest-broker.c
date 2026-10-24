// vtest-broker: accept Mesa vtest clients (virpipe in the Arch session) on a
// filesystem socket and hand each connection to the HarmonyOS display app, which
// runs the renderer in its own process and presents frames into its window.
// The app connects to the abstract socket @<name> and receives client fds over it
// (one byte plus SCM_RIGHTS each); clients wait in a queue until it is there.
// With --on-app CMD, each newly connected app runs CMD (through /system/bin/sh,
// at most every 10 s): `omarchy desktop restart`, so opening the app brings the
// desktop up, and reopening it after it was closed gives it a fresh Hyprland (the
// old one lost its GPU with the app and came back in safe mode).
// --app-uid UID: only a peer with that uid (SO_PEERCRED) counts as the app; the
// abstract socket is reachable from every process on the host, and whoever is
// "the app" receives the desktop's GPU connections.
// --user UID:GID: after binding, the broker drops to that user; a root parent
// stays only to run --on-app CMD when the unprivileged child asks over a pipe.
// --tcp ADDR:PORT (off by default): also take vtest clients over TCP, from a VM on
// the host (its Mesa virpipe reaches it through socat), only from --tcp-allow
// NET/BITS (default 172.16.100.0/24, 鸿融's network). The app only ever gets Unix
// sockets (a TCP socket passed to it fails on its first read): for each TCP client
// a forked pump copies between it and one end of a socketpair, and the other end
// goes to the app marked 'r'. The app's vtest serves those with protocol version 0:
// no shm fds can cross TCP, transfers are copied.
//   vtest-broker [--on-app CMD] [--app-uid UID] [--user UID:GID]
//                [--tcp ADDR:PORT [--tcp-allow NET/BITS]] <socket path> [name]
//   (default name: ohmarchy-vtest)
#define _GNU_SOURCE
#include <errno.h>
#include <arpa/inet.h>
#include <grp.h>
#include <netinet/in.h>
#include <stdlib.h>
#include <poll.h>
#include <stddef.h>
#include <stdio.h>
#include <string.h>
#include <sys/socket.h>
#include <sys/stat.h>
#include <sys/un.h>
#include <sys/wait.h>
#include <signal.h>
#include <time.h>
#include <unistd.h>

#define MAX_PENDING 16

static int listen_on(const char *path, const char *abstract)
{
    struct sockaddr_un a = {.sun_family = AF_UNIX};
    socklen_t len;
    int fd = socket(AF_UNIX, SOCK_STREAM | SOCK_CLOEXEC, 0);
    if (abstract) {
        size_t n = strlen(abstract);
        memcpy(a.sun_path + 1, abstract, n);
        len = offsetof(struct sockaddr_un, sun_path) + 1 + n;
    } else {
        snprintf(a.sun_path, sizeof(a.sun_path), "%s", path);
        unlink(path);
        len = sizeof(a);
    }
    if (fd < 0 || bind(fd, (struct sockaddr *)&a, len) < 0 || listen(fd, 8) < 0) {
        perror(abstract ? abstract : path);
        return -1;
    }
    if (!abstract)
        chmod(path, 0666);
    return fd;
}

static int listen_tcp(const char *spec)
{
    char host[64];
    unsigned port;
    struct sockaddr_in a = {.sin_family = AF_INET};
    if (sscanf(spec, "%63[^:]:%u", host, &port) != 2 || inet_pton(AF_INET, host, &a.sin_addr) != 1) {
        fprintf(stderr, "--tcp wants ADDR:PORT\n");
        return -1;
    }
    a.sin_port = htons(port);
    int one = 1, fd = socket(AF_INET, SOCK_STREAM | SOCK_CLOEXEC, 0);
    setsockopt(fd, SOL_SOCKET, SO_REUSEADDR, &one, sizeof(one));
    if (fd < 0 || bind(fd, (struct sockaddr *)&a, sizeof(a)) < 0 || listen(fd, 8) < 0) {
        perror(spec);
        return -1;
    }
    return fd;
}

/* Copy between a TCP client and the app's end of a socketpair until either closes. */
static void pump(int a, int b)
{
    static char buf[1 << 16];
    struct pollfd p[2] = {{a, POLLIN, 0}, {b, POLLIN, 0}};
    for (;;) {
        if (poll(p, 2, -1) < 0 && errno != EINTR)
            return;
        for (int i = 0; i < 2; i++) {
            if (!(p[i].revents & (POLLIN | POLLHUP | POLLERR)))
                continue;
            ssize_t n = read(p[i].fd, buf, sizeof(buf));
            if (n <= 0)
                return;
            for (ssize_t off = 0; off < n;) {
                ssize_t w = write(p[1 - i].fd, buf + off, n - off);
                if (w <= 0)
                    return;
                off += w;
            }
        }
    }
}

/* A TCP client becomes a Unix socket for the app; returns the app's end. */
static int bridge(int tcp_fd)
{
    int sv[2];
    if (socketpair(AF_UNIX, SOCK_STREAM | SOCK_CLOEXEC, 0, sv) < 0) {
        close(tcp_fd);
        return -1;
    }
    pid_t child = fork();
    if (child == 0) {
        for (int fd = 3; fd < 1024; fd++) /* not the broker's sockets, only these two */
            if (fd != tcp_fd && fd != sv[1])
                close(fd);
        pump(tcp_fd, sv[1]);
        _exit(0);
    }
    close(tcp_fd);
    close(sv[1]);
    if (child < 0) {
        close(sv[0]);
        return -1;
    }
    return sv[0];
}

static int send_fd(int sock, int fd, char byte)
{
    char cbuf[CMSG_SPACE(sizeof(int))];
    struct iovec iov = {&byte, 1};
    struct msghdr msg = {.msg_iov = &iov, .msg_iovlen = 1, .msg_control = cbuf, .msg_controllen = sizeof(cbuf)};
    struct cmsghdr *c = CMSG_FIRSTHDR(&msg);
    c->cmsg_level = SOL_SOCKET;
    c->cmsg_type = SCM_RIGHTS;
    c->cmsg_len = CMSG_LEN(sizeof(int));
    memcpy(CMSG_DATA(c), &fd, sizeof(int));
    return sendmsg(sock, &msg, MSG_NOSIGNAL) == 1 ? 0 : -1;
}

static void run_detached(const char *cmd)
{
    pid_t pid = fork();
    if (pid == 0) {
        setsid();
        execl("/system/bin/sh", "sh", "-c", cmd, (char *)NULL);
        _exit(127);
    }
}

/* Root side of --user: run CMD whenever the child writes a byte, at most every
 * 10 s; nothing else. Returns when the child is gone. */
static void hook_runner(int pipe_rd, const char *cmd)
{
    time_t last = 0;
    char b;
    while (read(pipe_rd, &b, 1) == 1) {
        if (time(NULL) - last >= 10) {
            last = time(NULL);
            printf("running: %s\n", cmd);
            run_detached(cmd);
        }
    }
}

int main(int argc, char **argv)
{
    const char *on_app = NULL, *user = NULL, *tcp = NULL, *tcp_allow = "172.16.100.0/24";
    long app_uid = -1;
    time_t last_hook = 0;
    int hook_pipe = -1;
    while (argc > 2 && strncmp(argv[1], "--", 2) == 0) {
        if (strcmp(argv[1], "--on-app") == 0)
            on_app = argv[2];
        else if (strcmp(argv[1], "--app-uid") == 0)
            app_uid = strtol(argv[2], NULL, 10);
        else if (strcmp(argv[1], "--user") == 0)
            user = argv[2];
        else if (strcmp(argv[1], "--tcp") == 0)
            tcp = argv[2];
        else if (strcmp(argv[1], "--tcp-allow") == 0)
            tcp_allow = argv[2];
        else
            break;
        argv += 2;
        argc -= 2;
    }
    if (argc < 2) {
        fprintf(stderr, "usage: %s [--on-app CMD] [--app-uid UID] [--user UID:GID] <socket path> [name]\n", argv[0]);
        return 2;
    }
    signal(SIGCHLD, SIG_IGN); /* no zombies from --on-app */
    setvbuf(stdout, NULL, _IOLBF, 0);
    int clients = listen_on(argv[1], NULL);
    int apps = listen_on(NULL, argc > 2 ? argv[2] : "ohmarchy-vtest");
    if (clients < 0 || apps < 0)
        return 1;
    int remote = -1;
    struct in_addr net = {0};
    unsigned bits = 32;
    if (tcp) {
        char n[32];
        if (sscanf(tcp_allow, "%31[^/]/%u", n, &bits) != 2 || inet_pton(AF_INET, n, &net) != 1 || bits > 32) {
            fprintf(stderr, "--tcp-allow wants NET/BITS\n");
            return 2;
        }
        if ((remote = listen_tcp(tcp)) < 0)
            return 1;
        printf("vtest clients over TCP on %s from %s\n", tcp, tcp_allow);
    }
    uint32_t mask = bits ? htonl(~0u << (32 - bits)) : 0;
    if (user) {
        unsigned uid, gid;
        int fds[2];
        if (sscanf(user, "%u:%u", &uid, &gid) != 2 || pipe(fds) < 0) {
            fprintf(stderr, "--user wants UID:GID\n");
            return 2;
        }
        pid_t child = fork();
        if (child > 0) { /* root: only the hook */
            close(fds[1]);
            close(clients);
            close(apps);
            if (remote >= 0)
                close(remote);
            hook_runner(fds[0], on_app ? on_app : "true");
            return 0;
        }
        close(fds[0]);
        hook_pipe = fds[1];
        if (setgroups(0, NULL) < 0 || setgid(gid) < 0 || setuid(uid) < 0) {
            perror("dropping to --user");
            return 1;
        }
        printf("running as uid %u\n", uid);
    }
    int app = -1, pending[MAX_PENDING], npending = 0;
    char kind[MAX_PENDING]; /* 'c' local, 'r' over TCP */
    for (;;) {
        struct pollfd p[4] = {{clients, POLLIN, 0}, {apps, POLLIN, 0}, {remote, POLLIN, 0}, {app, POLLIN, 0}};
        if (poll(p, app >= 0 ? 4 : 3, -1) < 0) {
            if (errno == EINTR)
                continue;
            perror("poll");
            return 1;
        }
        if (p[1].revents & POLLIN) {
            int fd = accept4(apps, NULL, NULL, SOCK_CLOEXEC);
            struct ucred cr = {0};
            socklen_t crlen = sizeof(cr);
            if (fd >= 0 && app_uid >= 0 &&
                (getsockopt(fd, SOL_SOCKET, SO_PEERCRED, &cr, &crlen) < 0 || (long)cr.uid != app_uid)) {
                printf("refused app pid %d uid %u (only uid %ld)\n", (int)cr.pid, (unsigned)cr.uid, app_uid);
                close(fd);
                fd = -1;
            }
            if (fd >= 0) {
                if (app >= 0)
                    close(app);
                app = fd;
                printf("app connected\n");
                if (hook_pipe >= 0) {
                    (void)!write(hook_pipe, "r", 1); /* the root parent runs --on-app */
                } else if (on_app && time(NULL) - last_hook >= 10) {
                    last_hook = time(NULL);
                    printf("running: %s\n", on_app);
                    run_detached(on_app);
                }
            }
        }
        if (app >= 0 && (p[3].revents & (POLLIN | POLLHUP | POLLERR))) {
            char b;
            if (recv(app, &b, 1, MSG_DONTWAIT) <= 0) {
                close(app);
                app = -1;
                printf("app gone\n");
            }
        }
        if (p[2].revents & POLLIN) { /* a VM: only from the allowed network */
            struct sockaddr_in from;
            socklen_t fl = sizeof(from);
            int fd = accept4(remote, (struct sockaddr *)&from, &fl, SOCK_CLOEXEC);
            if (fd >= 0 && (from.sin_addr.s_addr & mask) != (net.s_addr & mask)) {
                printf("refused TCP client %s\n", inet_ntoa(from.sin_addr));
                close(fd);
            } else if (fd >= 0) {
                int one = 1;
                setsockopt(fd, IPPROTO_TCP, 1 /* TCP_NODELAY */, &one, sizeof(one));
                int u = npending == MAX_PENDING ? -1 : bridge(fd);
                if (u >= 0) {
                    kind[npending] = 'r';
                    pending[npending++] = u;
                    printf("TCP client %s queued\n", inet_ntoa(from.sin_addr));
                }
            }
        }
        if (p[0].revents & POLLIN) {
            int fd = accept4(clients, NULL, NULL, SOCK_CLOEXEC);
            if (fd >= 0) {
                if (npending == MAX_PENDING) {
                    close(fd);
                } else {
                    kind[npending] = 'c';
                    pending[npending++] = fd;
                    printf("client queued\n");
                }
            }
        }
        while (app >= 0 && npending > 0) {
            if (send_fd(app, pending[0], kind[0]) < 0) {
                close(app);
                app = -1;
                break;
            }
            close(pending[0]);
            memmove(kind, kind + 1, npending - 1);
            memmove(pending, pending + 1, --npending * sizeof(int));
            printf("client passed to app\n");
        }
    }
}
