// ohm-sandboxd --app-uid UID [--launcher PATH] [--name NAME]
// ohm-sandboxd --ask NAME CMD     (a client, for tests and the installer)
// The sandbox's root helper, as the app sees it: on the abstract socket @NAME
// (default ohmsbx-ctl) it takes one line from the app com.ohmarchy.sandbox -- only
// from that uid (SO_PEERCRED) -- and only one of four fixed commands:
//   start   the sandbox and its desktop       (ohm-sandbox desktop start)
//   stop    the desktop and the sandbox       (ohm-sandbox desktop stop; ohm-sandbox stop)
//   reset   stop, then back to the snapshot   (... ohm-sandbox reset)
//   status  running or stopped                (ohm-sandbox status; ohm-sandbox desktop status)
// Nothing the client sends reaches a command line. The reply is "ok" or "failed",
// then the launcher's last output. Requests are handled one at a time.
#define _GNU_SOURCE
#include <errno.h>
#include <fcntl.h>
#include <signal.h>
#include <stddef.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/socket.h>
#include <sys/un.h>
#include <sys/wait.h>
#include <time.h>
#include <unistd.h>

static const char *launcher = "/data/local/ohm-sandbox/bin/ohm-sandbox";

static void say(const char *fmt, const char *a)
{
    time_t t = time(NULL);
    char ts[32];
    strftime(ts, sizeof ts, "%F %T", localtime(&t));
    printf("%s ", ts);
    printf(fmt, a);
    putchar('\n');
    fflush(stdout);
}

// run the launcher with the fixed argument lists; output (the tail) into out
static int run(char **const *steps, char *out, size_t outlen)
{
    int p[2];
    if (pipe2(p, O_CLOEXEC) != 0)
        return -1;
    pid_t c = fork();
    if (c < 0)
        return -1;
    if (c == 0) {
        dup2(p[1], 1);
        dup2(p[1], 2);
        int null = open("/dev/null", O_RDONLY);
        dup2(null, 0);
        // every step runs (desktop stop fails when there is nothing left to stop);
        // the last one's status counts, and reset refuses by itself if stop did not
        int rc = 0;
        for (int i = 0; steps[i] != NULL; i++) {
            pid_t s = fork();
            if (s == 0) {
                execv("/system/bin/sh", steps[i]);
                _exit(127);
            }
            int st = 0;
            waitpid(s, &st, 0);
            rc = WIFEXITED(st) ? WEXITSTATUS(st) : 1;
        }
        _exit(rc);
    }
    close(p[1]);
    size_t n = 0;
    char buf[512];
    ssize_t r;
    while ((r = read(p[0], buf, sizeof buf)) > 0) {
        for (ssize_t i = 0; i < r; i++) {  // keep the last outlen-1 bytes
            if (n == outlen - 1) {
                memmove(out, out + 1, n - 1);
                n--;
            }
            out[n++] = buf[i];
        }
    }
    out[n] = '\0';
    close(p[0]);
    int st = 0;
    waitpid(c, &st, 0);
    return WIFEXITED(st) ? WEXITSTATUS(st) : 1;
}

static int ask(const char *name, const char *cmd)
{
    int s = socket(AF_UNIX, SOCK_STREAM | SOCK_CLOEXEC, 0);
    struct sockaddr_un a = {.sun_family = AF_UNIX};
    size_t len = strlen(name);
    if (s < 0 || len + 1 > sizeof a.sun_path)
        return 1;
    memcpy(a.sun_path + 1, name, len);
    if (connect(s, (struct sockaddr *)&a, (socklen_t)(offsetof(struct sockaddr_un, sun_path) + 1 + len)) != 0) {
        perror("ohm-sandboxd: connect");
        return 1;
    }
    dprintf(s, "%s\n", cmd);
    char buf[512];
    ssize_t r;
    while ((r = read(s, buf, sizeof buf)) > 0)
        fwrite(buf, 1, (size_t)r, stdout);
    return 0;
}

int main(int argc, char **argv)
{
    if (argc == 4 && strcmp(argv[1], "--ask") == 0)
        return ask(argv[2], argv[3]);
    long app_uid = -1;
    const char *name = "ohmsbx-ctl";
    for (int i = 1; i + 1 < argc; i += 2) {
        if (strcmp(argv[i], "--app-uid") == 0)
            app_uid = strtol(argv[i + 1], NULL, 10);
        else if (strcmp(argv[i], "--launcher") == 0)
            launcher = argv[i + 1];
        else if (strcmp(argv[i], "--name") == 0)
            name = argv[i + 1];
    }
    if (app_uid < 0) {
        fprintf(stderr, "usage: ohm-sandboxd --app-uid UID [--launcher PATH] [--name NAME]\n");
        return 2;
    }
    signal(SIGPIPE, SIG_IGN);  // the app may be gone before the reply (stop on close)
    int s = socket(AF_UNIX, SOCK_STREAM | SOCK_CLOEXEC, 0);
    struct sockaddr_un a = {.sun_family = AF_UNIX};
    size_t len = strlen(name);
    if (s < 0 || len + 1 > sizeof a.sun_path) {
        perror("ohm-sandboxd: socket");
        return 1;
    }
    memcpy(a.sun_path + 1, name, len);  // abstract namespace
    if (bind(s, (struct sockaddr *)&a, (socklen_t)(offsetof(struct sockaddr_un, sun_path) + 1 + len)) != 0 ||
        listen(s, 4) != 0) {
        perror("ohm-sandboxd: bind");
        return 1;
    }
    say("listening on @%s", name);

    // fixed argument lists; the launcher's path goes in at [1]
    static char *a_dstart[] = {"sh", NULL, "desktop", "start", NULL};
    static char *a_dstop[] = {"sh", NULL, "desktop", "stop", NULL};
    static char *a_stop[] = {"sh", NULL, "stop", NULL};
    static char *a_reset[] = {"sh", NULL, "reset", NULL};
    static char *a_status[] = {"sh", NULL, "status", NULL};
    static char *a_dstatus[] = {"sh", NULL, "desktop", "status", NULL};
    char **all[] = {a_dstart, a_dstop, a_stop, a_reset, a_status, a_dstatus};
    for (size_t i = 0; i < sizeof all / sizeof all[0]; i++)
        all[i][1] = (char *)launcher;
    static char **do_start[] = {a_dstart, NULL};
    static char **do_stop[] = {a_dstop, a_stop, NULL};
    static char **do_reset[] = {a_dstop, a_stop, a_reset, NULL};
    static char **do_status[] = {a_status, a_dstatus, NULL};
    struct { const char *cmd; char **const *steps; } table[] = {
        {"start", do_start}, {"stop", do_stop}, {"reset", do_reset}, {"status", do_status},
    };

    for (;;) {
        int c = accept4(s, NULL, NULL, SOCK_CLOEXEC);
        if (c < 0)
            continue;
        struct ucred cr;
        socklen_t cl = sizeof cr;
        if (getsockopt(c, SOL_SOCKET, SO_PEERCRED, &cr, &cl) != 0 || (long)cr.uid != app_uid) {
            say("refused a client (not the app's uid)%s", "");
            write(c, "refused\n", 8);
            close(c);
            continue;
        }
        struct timeval tv = {.tv_sec = 5};
        setsockopt(c, SOL_SOCKET, SO_RCVTIMEO, &tv, sizeof tv);
        char line[16];
        size_t n = 0;
        while (n < sizeof line - 1) {
            ssize_t r = read(c, line + n, 1);
            if (r <= 0 || line[n] == '\n')
                break;
            n++;
        }
        line[n] = '\0';
        char **const *steps = NULL;
        for (size_t i = 0; i < sizeof table / sizeof table[0]; i++)
            if (strcmp(line, table[i].cmd) == 0)
                steps = table[i].steps;
        if (steps == NULL) {
            say("refused an unknown command from the app%s", "");
            write(c, "unknown\n", 8);
            close(c);
            continue;
        }
        say("app: %s", line);
        char out[2048];
        int rc = run(steps, out, sizeof out);
        dprintf(c, "%s\n%s", rc == 0 ? "ok" : "failed", out);
        say(rc == 0 ? "%s: ok" : "%s: failed", line);
        close(c);
    }
}
