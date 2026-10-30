// ohm-sandboxd --app-uid UID [--launcher PATH] [--name NAME]
// ohm-sandboxd --ask NAME CMD [FILE]   (a client, for tests and the installer; FILE: the
//                                        body of writepolicy)
// The sandbox's root helper, as the app sees it: on the abstract socket @NAME
// (default ohmsbx-ctl) it takes one line from the app com.ohmarchy.sandbox -- only
// from that uid (SO_PEERCRED) -- and only one of four fixed commands:
//   start   the sandbox and a new desktop     (ohm-sandbox desktop restart)
//   stop    the desktop and the sandbox       (ohm-sandbox desktop stop; ohm-sandbox stop)
//   reset   stop, then back to the snapshot   (... ohm-sandbox reset)
//   status  running or stopped                (ohm-sandbox status; ohm-sandbox desktop status)
// and, for the app's settings page, the sandbox's policy (policy.conf, policy.sh):
//   policycheck   what the next start applies    (ohm-sandbox policy check)
//   readpolicy    the policy's text              (ohm-sandbox policy show)
//   writepolicy   the line, then the new policy.conf's text until the client shuts
//                 its side: checked here line by line against a fixed grammar (7 keys,
//                 plain values, at most 4 KiB / 64 lines), written to the fixed file
//                 run/policy.new, checked again by policy.sh's parser (ohm-sandbox
//                 policy validate run/policy.new), and only then renamed over
//                 policy.conf; any failure leaves policy.conf as it was.
// Nothing the client sends reaches a command line; the policy text is only ever read
// by policy.sh's parser, never run. The reply is "ok" or "failed" (writepolicy:
// "invalid"), then the launcher's last output. Requests are handled one at a time.
#define _GNU_SOURCE
#include <errno.h>
#include <fcntl.h>
#include <signal.h>
#include <stddef.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/socket.h>
#include <sys/stat.h>
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

static int ask(const char *name, const char *cmd, const char *file)
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
    if (file != NULL) {
        FILE *f = fopen(file, "r");
        char b[512];
        size_t r;
        while (f != NULL && (r = fread(b, 1, sizeof b, f)) > 0)
            write(s, b, r);
        if (f != NULL)
            fclose(f);
        shutdown(s, SHUT_WR);
    }
    char buf[512];
    ssize_t r;
    while ((r = read(s, buf, sizeof buf)) > 0)
        fwrite(buf, 1, (size_t)r, stdout);
    return 0;
}

// writepolicy's own check, before policy.sh's: every line empty, a comment of plain
// characters, or "key = value" with one of the policy's keys and a plain value
static const char *policy_line_bad(const char *l, size_t n)
{
    static const char *const keys[] = {"network", "share", "abstract_allow", "cap_keep", "cap_drop_extra", "dev", "docker"};
    static const char plain[] = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789 ./_@+-";
    if (n > 200)
        return "line too long";
    size_t i = 0;
    while (i < n && l[i] == ' ')
        i++;
    if (i == n)
        return NULL;
    if (l[i] == '#') {
        for (; i < n; i++)
            if (strchr(plain, l[i]) == NULL && l[i] != '#' && l[i] != ',' && l[i] != ':' && l[i] != '=')
                return "a character not allowed in a comment";
        return NULL;
    }
    size_t k = i;
    while (k < n && l[k] != ' ' && l[k] != '=')
        k++;
    int known = 0;
    for (size_t j = 0; j < sizeof keys / sizeof keys[0]; j++)
        if (strlen(keys[j]) == k - i && memcmp(keys[j], l + i, k - i) == 0)
            known = 1;
    if (!known)
        return "not a policy key";
    while (k < n && l[k] == ' ')
        k++;
    if (k == n || l[k] != '=')
        return "expected key = value";
    for (k++; k < n; k++)
        if (strchr(plain, l[k]) == NULL)
            return "a character not allowed in a value";
    return NULL;
}

// read the new policy (until the client shuts its side), check it, write it to the
// fixed file run/policy.new; then policy.sh validates it and it replaces policy.conf.
// 0 and the reply in out, or -1 with the reason in out.
static int write_policy(int c, const char *dir, char **validate_step, char *out, size_t outlen)
{
    char body[4096 + 1];
    size_t n = 0;
    ssize_t r;
    while (n < sizeof body && (r = read(c, body + n, sizeof body - n)) > 0)
        n += (size_t)r;
    if (n == sizeof body) {
        snprintf(out, outlen, "more than 4 KiB");
        return -1;
    }
    int lines = 0;
    for (size_t i = 0; i < n;) {
        size_t e = i;
        while (e < n && body[e] != '\n')
            e++;
        for (size_t j = i; j < e; j++)
            if ((unsigned char)body[j] < 0x20 || (unsigned char)body[j] > 0x7e) {
                snprintf(out, outlen, "line %d: a character not allowed", lines + 1);
                return -1;
            }
        const char *bad = policy_line_bad(body + i, e - i);
        if (bad != NULL || ++lines > 64) {
            snprintf(out, outlen, "line %d: %s", lines + (bad != NULL), bad != NULL ? bad : "more than 64 lines");
            return -1;
        }
        i = e + 1;
    }
    char newp[512], conf[512], run_dir[512];
    snprintf(run_dir, sizeof run_dir, "%s/run", dir);
    snprintf(newp, sizeof newp, "%s/run/policy.new", dir);
    snprintf(conf, sizeof conf, "%s/policy.conf", dir);
    mkdir(run_dir, 0755);
    unlink(newp);
    int f = open(newp, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC, 0600);
    if (f < 0 || write(f, body, n) != (ssize_t)n || fsync(f) != 0) {
        if (f >= 0)
            close(f);
        unlink(newp);
        snprintf(out, outlen, "could not write %s", newp);
        return -1;
    }
    close(f);
    char **steps[] = {validate_step, NULL};
    if (run(steps, out, outlen) != 0) {
        unlink(newp);
        return -1;  // policy.sh's reason is in out
    }
    if (chmod(newp, 0644) != 0 || rename(newp, conf) != 0) {
        unlink(newp);
        snprintf(out, outlen, "could not replace %s", conf);
        return -1;
    }
    return 0;
}

int main(int argc, char **argv)
{
    if ((argc == 4 || argc == 5) && strcmp(argv[1], "--ask") == 0)
        return ask(argv[2], argv[3], argc == 5 ? argv[4] : NULL);
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
    // The app asks for start when its process starts. A desktop still running from an
    // earlier app process (the app crashed or was reinstalled while Linux ran) drew
    // through that process's GPU renderer, which is gone: its picture would stay
    // black. So start always brings up a new desktop for the new app process.
    static char *a_dstart[] = {"sh", NULL, "desktop", "restart", NULL};
    static char *a_dstop[] = {"sh", NULL, "desktop", "stop", NULL};
    static char *a_stop[] = {"sh", NULL, "stop", NULL};
    static char *a_reset[] = {"sh", NULL, "reset", NULL};
    static char *a_status[] = {"sh", NULL, "status", NULL};
    static char *a_dstatus[] = {"sh", NULL, "desktop", "status", NULL};
    static char *a_pcheck[] = {"sh", NULL, "policy", "check", NULL};
    static char *a_pshow[] = {"sh", NULL, "policy", "show", NULL};
    // the app could not set the desktop's cursor as its pointer: the desktop draws it
    static char *a_soft[] = {"sh", NULL, "desktop", "softcursor", NULL};
    // the launcher's directory's parent is the sandbox's: its run/policy.new
    static char dir[512], newp[512];
    snprintf(dir, sizeof dir, "%s", launcher);
    for (int up = 0; up < 2; up++) {
        char *sl = strrchr(dir, '/');
        if (sl != NULL)
            *sl = '\0';
    }
    snprintf(newp, sizeof newp, "%s/run/policy.new", dir);
    static char *a_pvalidate[] = {"sh", NULL, "policy", "validate", newp, NULL};
    char **all[] = {a_dstart, a_dstop, a_stop, a_reset, a_status, a_dstatus, a_pcheck, a_pshow, a_pvalidate, a_soft};
    for (size_t i = 0; i < sizeof all / sizeof all[0]; i++)
        all[i][1] = (char *)launcher;
    static char **do_start[] = {a_dstart, NULL};
    static char **do_stop[] = {a_dstop, a_stop, NULL};
    static char **do_reset[] = {a_dstop, a_stop, a_reset, NULL};
    static char **do_status[] = {a_status, a_dstatus, NULL};
    static char **do_pcheck[] = {a_pcheck, NULL};
    static char **do_pshow[] = {a_pshow, NULL};
    static char **do_soft[] = {a_soft, NULL};
    struct { const char *cmd; char **const *steps; } table[] = {
        {"start", do_start}, {"stop", do_stop}, {"reset", do_reset}, {"status", do_status},
        {"policycheck", do_pcheck}, {"readpolicy", do_pshow}, {"writepolicy", NULL},
        {"softcursor", do_soft},
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
        int known = 0;
        for (size_t i = 0; i < sizeof table / sizeof table[0]; i++)
            if (strcmp(line, table[i].cmd) == 0) {
                steps = table[i].steps;
                known = 1;
            }
        if (known && strcmp(line, "writepolicy") == 0) {
            char out[4096];
            say("app: %s", line);
            if (write_policy(c, dir, a_pvalidate, out, sizeof out) == 0) {
                char **chk[] = {a_pcheck, NULL};
                run(chk, out, sizeof out);
                dprintf(c, "ok\n%s", out);
                say("%s: policy.conf written by the app", line);
            } else {
                dprintf(c, "invalid\n%s", out);
                say("%s: refused", line);
            }
            close(c);
            continue;
        }
        if (steps == NULL) {
            say("refused an unknown command from the app%s", "");
            write(c, "unknown\n", 8);
            close(c);
            continue;
        }
        say("app: %s", line);
        char out[4096];
        int rc = run(steps, out, sizeof out);
        dprintf(c, "%s\n%s", rc == 0 ? "ok" : "failed", out);
        say(rc == 0 ? "%s: ok" : "%s: failed", line);
        close(c);
    }
}
