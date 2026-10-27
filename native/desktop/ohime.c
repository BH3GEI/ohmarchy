// ohime: input method for the native desktop. The HarmonyOS display app runs the
// system IME (Chinese and other scripts) and sends its text here over the abstract
// socket @ohmarchy-ime; this client commits it through zwp_input_method_v2 to the
// focused text-input-v3 client (GTK, Qt, foot, Chromium with --enable-wayland-ime).
//
// Messages: {uint32 type, uint32 length} + UTF-8 bytes, host byte order.
//   1 commit text   2 preedit text (empty clears it)
#define _GNU_SOURCE
#include <errno.h>
#include <poll.h>
#include <stddef.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/socket.h>
#include <sys/un.h>
#include <unistd.h>
#include <wayland-client.h>

#include "input-method-unstable-v2-client-protocol.h"

// "<OHMARCHY_SOCKET_PREFIX>-ime" (default ohmarchy), the app's name for it
static char kName[64];

static void SetName(void)
{
    const char *p = getenv("OHMARCHY_SOCKET_PREFIX");
    snprintf(kName, sizeof(kName), "%s-ime", p != NULL && *p != '\0' ? p : "ohmarchy");
}

static struct wl_seat *seat;
static struct zwp_input_method_manager_v2 *manager;
static struct zwp_input_method_v2 *im;
static uint32_t serial;
static int active, pendingActive;

static void imActivate(void *d, struct zwp_input_method_v2 *m) { pendingActive = 1; }
static void imDeactivate(void *d, struct zwp_input_method_v2 *m) { pendingActive = 0; }
static void imSurrounding(void *d, struct zwp_input_method_v2 *m, const char *t, uint32_t c, uint32_t a) {}
static void imCause(void *d, struct zwp_input_method_v2 *m, uint32_t cause) {}
static void imContentType(void *d, struct zwp_input_method_v2 *m, uint32_t hint, uint32_t purpose) {}
static void imDone(void *d, struct zwp_input_method_v2 *m)
{
    serial++;
    active = pendingActive;
}
static void imUnavailable(void *d, struct zwp_input_method_v2 *m)
{
    fprintf(stderr, "ohime: another input method is running\n");
    exit(1);
}

static const struct zwp_input_method_v2_listener imListener = {
    .activate = imActivate,
    .deactivate = imDeactivate,
    .surrounding_text = imSurrounding,
    .text_change_cause = imCause,
    .content_type = imContentType,
    .done = imDone,
    .unavailable = imUnavailable,
};

static void global(void *d, struct wl_registry *r, uint32_t name, const char *iface, uint32_t version)
{
    if (strcmp(iface, wl_seat_interface.name) == 0 && !seat)
        seat = wl_registry_bind(r, name, &wl_seat_interface, 1);
    else if (strcmp(iface, zwp_input_method_manager_v2_interface.name) == 0)
        manager = wl_registry_bind(r, name, &zwp_input_method_manager_v2_interface, 1);
}
static void globalRemove(void *d, struct wl_registry *r, uint32_t name) {}
static const struct wl_registry_listener registryListener = {global, globalRemove};

static void handle(uint32_t type, const char *text)
{
    if (!active) {
        fprintf(stderr, "ohime: no focused text input, dropped \"%s\"\n", text);
        return;
    }
    if (type == 1) {
        zwp_input_method_v2_set_preedit_string(im, "", 0, 0);
        zwp_input_method_v2_commit_string(im, text);
    } else if (type == 2) {
        int len = (int)strlen(text);
        zwp_input_method_v2_set_preedit_string(im, text, len, len);
    }
    zwp_input_method_v2_commit(im, serial);
}

static int readAll(int fd, void *buf, size_t n)
{
    char *p = buf;
    while (n > 0) {
        ssize_t r = read(fd, p, n);
        if (r <= 0)
            return -1;
        p += r;
        n -= (size_t)r;
    }
    return 0;
}

int main(void)
{
    SetName();
    struct wl_display *display = wl_display_connect(NULL);
    if (!display) {
        fprintf(stderr, "ohime: no wayland display\n");
        return 1;
    }
    struct wl_registry *registry = wl_display_get_registry(display);
    wl_registry_add_listener(registry, &registryListener, NULL);
    wl_display_roundtrip(display);
    if (!seat || !manager) {
        fprintf(stderr, "ohime: compositor lacks a seat or zwp_input_method_manager_v2\n");
        return 1;
    }
    im = zwp_input_method_manager_v2_get_input_method(manager, seat);
    zwp_input_method_v2_add_listener(im, &imListener, NULL);
    wl_display_roundtrip(display);

    int lfd = socket(AF_UNIX, SOCK_STREAM | SOCK_CLOEXEC, 0);
    struct sockaddr_un a = {.sun_family = AF_UNIX};
    size_t len = strlen(kName);
    memcpy(a.sun_path + 1, kName, len);
    if (bind(lfd, (struct sockaddr *)&a, offsetof(struct sockaddr_un, sun_path) + 1 + len) < 0 || listen(lfd, 2) < 0) {
        perror("ohime: @ohmarchy-ime");
        return 1;
    }

    int cfd = -1;
    for (;;) {
        wl_display_flush(display);
        struct pollfd p[3] = {
            {wl_display_get_fd(display), POLLIN, 0},
            {lfd, POLLIN, 0},
            {cfd, POLLIN, 0},
        };
        if (poll(p, cfd >= 0 ? 3 : 2, -1) < 0 && errno != EINTR)
            return 1;
        if (p[0].revents & POLLIN) {
            if (wl_display_dispatch(display) < 0)
                return 1;
        }
        if (p[1].revents & POLLIN) {
            int n = accept4(lfd, NULL, NULL, SOCK_CLOEXEC);
            if (n >= 0) {
                if (cfd >= 0)
                    close(cfd);
                cfd = n;  // one app at a time; the newest wins
            }
        }
        if (cfd >= 0 && (p[2].revents & (POLLIN | POLLHUP))) {
            uint32_t hdr[2];
            char *text = NULL;
            if (readAll(cfd, hdr, sizeof(hdr)) < 0 || hdr[1] > 65536 || !(text = calloc(1, hdr[1] + 1)) ||
                readAll(cfd, text, hdr[1]) < 0) {
                free(text);
                close(cfd);
                cfd = -1;
                continue;
            }
            handle(hdr[0], text);
            free(text);
        }
    }
}
