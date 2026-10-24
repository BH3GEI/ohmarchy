// Preloaded (ld.so.preload) msgrcv for the HongMeng kernel: a msgrcv that is
// already blocked is never woken by a later msgsnd (the message does arrive in the
// queue; a non-blocking msgrcv reads it). fakeroot's faked blocks exactly like
// that, so makepkg hangs. Blocking calls become non-blocking polls with a short
// backoff (50 us up to 1 ms); a signal still interrupts them with EINTR.
#define _GNU_SOURCE
#include <dlfcn.h>
#include <errno.h>
#include <sys/msg.h>
#include <time.h>

static ssize_t (*real_msgrcv)(int, void *, size_t, long, int);

ssize_t msgrcv(int id, void *msg, size_t size, long type, int flags)
{
    if (!real_msgrcv) {
        real_msgrcv = (ssize_t (*)(int, void *, size_t, long, int))dlsym(RTLD_NEXT, "msgrcv");
    }
    if (flags & IPC_NOWAIT) {
        return real_msgrcv(id, msg, size, type, flags);
    }
    long wait_ns = 50000;
    for (;;) {
        ssize_t n = real_msgrcv(id, msg, size, type, flags | IPC_NOWAIT);
        if (n >= 0 || errno != ENOMSG) {
            return n;
        }
        struct timespec ts = {0, wait_ns};
        if (nanosleep(&ts, NULL) < 0 && errno == EINTR) {
            return -1;
        }
        if (wait_ns < 1000000) {
            wait_ns *= 2;
        }
    }
}
