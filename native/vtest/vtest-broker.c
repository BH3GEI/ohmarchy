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
//   vtest-broker [--on-app CMD] [--app-uid UID] [--user UID:GID] <socket path> [name]
//   (default name: ohmarchy-vtest)
#define _GNU_SOURCE
#include <errno.h>
#include <grp.h>
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

static int send_fd(int sock, int fd)
{
    char byte = 'c';
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
    const char *on_app = NULL, *user = NULL;
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
    for (;;) {
        struct pollfd p[3] = {{clients, POLLIN, 0}, {apps, POLLIN, 0}, {app, POLLIN, 0}};
        if (poll(p, app >= 0 ? 3 : 2, -1) < 0) {
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
        if (app >= 0 && (p[2].revents & (POLLIN | POLLHUP | POLLERR))) {
            char b;
            if (recv(app, &b, 1, MSG_DONTWAIT) <= 0) {
                close(app);
                app = -1;
                printf("app gone\n");
            }
        }
        if (p[0].revents & POLLIN) {
            int fd = accept4(clients, NULL, NULL, SOCK_CLOEXEC);
            if (fd >= 0) {
                if (npending == MAX_PENDING) {
                    close(fd);
                } else {
                    pending[npending++] = fd;
                    printf("client queued\n");
                }
            }
        }
        while (app >= 0 && npending > 0) {
            if (send_fd(app, pending[0]) < 0) {
                close(app);
                app = -1;
                break;
            }
            close(pending[0]);
            memmove(pending, pending + 1, --npending * sizeof(int));
            printf("client passed to app\n");
        }
    }
}
