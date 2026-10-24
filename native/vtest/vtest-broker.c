// vtest-broker: accept Mesa vtest clients (virpipe in the Arch session) on a
// filesystem socket and hand each connection to the HarmonyOS display app, which
// runs the renderer in its own process and presents frames into its window.
// The app connects to the abstract socket @<name> and receives client fds over it
// (one byte plus SCM_RIGHTS each); clients wait in a queue until it is there.
// With --on-app CMD, each newly connected app runs CMD (through /system/bin/sh,
// at most every 10 s): `omarchy desktop restart`, so opening the app brings the
// desktop up, and reopening it after it was closed gives it a fresh Hyprland (the
// old one lost its GPU with the app and came back in safe mode).
//   vtest-broker [--on-app CMD] <socket path> [name]   (default name: ohmarchy-vtest)
#include <errno.h>
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

int main(int argc, char **argv)
{
    const char *on_app = NULL;
    time_t last_hook = 0;
    if (argc > 2 && strcmp(argv[1], "--on-app") == 0) {
        on_app = argv[2];
        argv += 2;
        argc -= 2;
    }
    if (argc < 2) {
        fprintf(stderr, "usage: %s [--on-app CMD] <socket path> [name]\n", argv[0]);
        return 2;
    }
    signal(SIGCHLD, SIG_IGN); /* no zombies from --on-app */
    int clients = listen_on(argv[1], NULL);
    int apps = listen_on(NULL, argc > 2 ? argv[2] : "ohmarchy-vtest");
    if (clients < 0 || apps < 0)
        return 1;
    int app = -1, pending[MAX_PENDING], npending = 0;
    setvbuf(stdout, NULL, _IOLBF, 0);
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
            if (fd >= 0) {
                if (app >= 0)
                    close(app);
                app = fd;
                printf("app connected\n");
                if (on_app && time(NULL) - last_hook >= 10) {
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
