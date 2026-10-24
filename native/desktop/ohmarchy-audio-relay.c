// ohmarchy-audio-relay: the session's sound output for the display app, on the
// abstract Unix socket @ohmarchy-audio instead of a TCP port. The session shares the
// host's network namespace, so a TCP port on 127.0.0.1 (PipeWire's protocol-simple)
// lets any process on the HarmonyOS host listen in. Here the kernel tells who
// connected (SO_PEERCRED): only the display app's uid is served. For it, pw-record
// captures the "HarmonyOS" sink's monitor (raw S16LE, 48 kHz, stereo) straight into
// the socket. One client at a time; a new one replaces the old.
//   OHMARCHY_APP_UID=<uid> ohmarchy-audio-relay      (started by ohmarchy-desktop)
#define _GNU_SOURCE
#include <errno.h>
#include <signal.h>
#include <stddef.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/socket.h>
#include <sys/un.h>
#include <sys/wait.h>
#include <unistd.h>

static const char *kName = "ohmarchy-audio";

int main(void)
{
    const char *u = getenv("OHMARCHY_APP_UID");
    if (u == NULL || *u == '\0') {
        fprintf(stderr, "ohmarchy-audio-relay: OHMARCHY_APP_UID not set; serving nobody\n");
        return 1;
    }
    uid_t app = (uid_t)strtoul(u, NULL, 10);
    signal(SIGCHLD, SIG_IGN);  // no zombies from replaced captures
    int s = socket(AF_UNIX, SOCK_STREAM | SOCK_CLOEXEC, 0);
    struct sockaddr_un a = {.sun_family = AF_UNIX};
    size_t n = strlen(kName);
    memcpy(a.sun_path + 1, kName, n);  // abstract namespace
    if (s < 0 || bind(s, (struct sockaddr *)&a, offsetof(struct sockaddr_un, sun_path) + 1 + n) < 0 ||
        listen(s, 4) < 0) {
        perror("ohmarchy-audio-relay: @ohmarchy-audio");  // taken: fail, never pick another name
        return 1;
    }
    pid_t capture = 0;
    for (;;) {
        int c = accept4(s, NULL, NULL, SOCK_CLOEXEC);
        if (c < 0) {
            if (errno == EINTR) {
                continue;
            }
            perror("accept");
            return 1;
        }
        struct ucred cr;
        socklen_t len = sizeof(cr);
        if (getsockopt(c, SOL_SOCKET, SO_PEERCRED, &cr, &len) < 0 || cr.uid != app) {
            fprintf(stderr, "ohmarchy-audio-relay: refused pid %d uid %u (only uid %u)\n", (int)cr.pid,
                    (unsigned)cr.uid, (unsigned)app);
            close(c);
            continue;
        }
        if (capture > 0) {
            kill(capture, SIGTERM);
        }
        capture = fork();
        if (capture == 0) {
            dup2(c, 1);
            // unbuffered: pw-record writes through stdio, which buffers a non-tty
            // stdout; that added 50-100 ms
            execlp("stdbuf", "stdbuf", "-o0", "pw-record", "--raw", "--target", "ohmarchy-out", "-P",
                   "{ stream.capture.sink = true node.passive = true node.name = ohmarchy-app-out }",
                   "--latency", "5ms", "--rate", "48000", "--channels", "2", "--format", "s16", "-", (char *)NULL);
            perror("pw-record");
            _exit(127);
        }
        close(c);
    }
}
