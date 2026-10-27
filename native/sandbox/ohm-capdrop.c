// ohm-capdrop [--enter PID] CAP[,CAP..] -- CMD [ARG..]
// Drop capabilities from the bounding set (by number), then exec CMD. With --enter,
// first join PID's ipc, uts, pid and mount namespaces (CMD runs in a child, as the
// pid namespace applies to children only).
// Every fd above 2 is closed first: whatever the caller held (a host shell's
// /dev/kmsg, say) must not cross into the sandbox.
// util-linux setpriv cannot be used: it first asks for PR_SET_KEEPCAPS, which HongMeng
// refuses (EPERM). toybox nsenter cannot either: it opens /proc/PID/ns/* one by one,
// after the mount namespace has already switched /proc to the sandbox's.
#define _GNU_SOURCE
#include <dirent.h>
#include <errno.h>
#include <fcntl.h>
#include <sched.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/prctl.h>
#include <sys/wait.h>
#include <unistd.h>

static void close_inherited(void)
{
    DIR *d = opendir("/proc/self/fd");
    if (d == NULL)
        return;
    struct dirent *e;
    while ((e = readdir(d)) != NULL) {
        int fd = atoi(e->d_name);
        if (e->d_name[0] >= '0' && e->d_name[0] <= '9' && fd > 2 && fd != dirfd(d))
            close(fd);
    }
    closedir(d);
}

static int enter(const char *pid)
{
    static const char *const ns[] = {"ipc", "uts", "pid", "mnt"};  // mnt last
    int fd[4];
    for (int i = 0; i < 4; i++) {  // open all before any setns
        char path[64];
        snprintf(path, sizeof(path), "/proc/%s/ns/%s", pid, ns[i]);
        if ((fd[i] = open(path, O_RDONLY | O_CLOEXEC)) < 0) {
            fprintf(stderr, "ohm-capdrop: %s: %s\n", path, strerror(errno));
            return -1;
        }
    }
    for (int i = 0; i < 4; i++) {
        if (setns(fd[i], 0) != 0) {
            fprintf(stderr, "ohm-capdrop: setns %s: %s\n", ns[i], strerror(errno));
            return -1;
        }
        close(fd[i]);
    }
    return chdir("/");  // the mount namespace's root (the image)
}

int main(int argc, char **argv)
{
    int a = 1;
    const char *pid = NULL;
    if (argc > 2 && strcmp(argv[1], "--enter") == 0) {
        pid = argv[2];
        a = 3;
    }
    if (argc < a + 3 || strcmp(argv[a + 1], "--") != 0) {
        fprintf(stderr, "usage: ohm-capdrop [--enter PID] CAP[,CAP..] -- CMD [ARG..]\n");
        return 2;
    }
    close_inherited();
    if (pid != NULL && enter(pid) != 0) {
        return 1;
    }
    char *list = strdup(argv[a]);
    for (char *t = strtok(list, ","); t != NULL; t = strtok(NULL, ",")) {
        long cap = strtol(t, NULL, 10);
        if (prctl(PR_CAPBSET_DROP, cap, 0, 0, 0) != 0 && errno != EINVAL) {
            fprintf(stderr, "ohm-capdrop: drop %ld: %s\n", cap, strerror(errno));
            return 1;
        }
    }
    char **cmd = argv + a + 2;
    if (pid != NULL) {
        pid_t c = fork();
        if (c < 0) {
            perror("ohm-capdrop: fork");
            return 1;
        }
        if (c > 0) {
            int st = 0;
            while (waitpid(c, &st, 0) < 0 && errno == EINTR) {
            }
            return WIFEXITED(st) ? WEXITSTATUS(st) : 128 + WTERMSIG(st);
        }
    }
    execv(cmd[0], cmd);
    fprintf(stderr, "ohm-capdrop: %s: %s\n", cmd[0], strerror(errno));
    return 127;
}
