/* __cxa_thread_atexit_impl for OHOS musl (its libc omits it). Runs C++ thread_local
   destructors at thread exit via a pthread TSD destructor. Merged into libc++_ohm.so. */
#include <pthread.h>
#include <stdlib.h>
struct dtor { void (*func)(void *); void *obj; struct dtor *next; };
static pthread_key_t key;
static pthread_once_t once = PTHREAD_ONCE_INIT;
static void run_dtors(void *head) {
    for (struct dtor *d = head; d;) { struct dtor *n = d->next; d->func(d->obj); free(d); d = n; }
}
static void make_key(void) { pthread_key_create(&key, run_dtors); }
int __cxa_thread_atexit_impl(void (*func)(void *), void *obj, void *dso) {
    (void)dso;
    pthread_once(&once, make_key);
    struct dtor *d = (struct dtor *)malloc(sizeof *d);
    if (!d) return -1;
    d->func = func; d->obj = obj; d->next = (struct dtor *)pthread_getspecific(key);
    pthread_setspecific(key, d);
    return 0;
}
