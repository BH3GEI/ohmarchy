// Preload for Wayland clients on Mesa virpipe with the display app's GPU server
// (native/app/vtest-inapp.patch): the server keeps a client's frame on the GPU and
// writes only a tag ("OHCZ", snapshot id, width, height) into the first and last row
// of the read-back. Mesa still copies the whole frame twice on the CPU (into its
// display target, then row by row into the wl_shm buffer); this memcpy copies the
// tag rows of such a frame and skips the rows in between, which nobody looks at.
//   LD_PRELOAD=/opt/ohmarchy/lib/libohzc.so GALLIUM_DRIVER=virpipe app
#define _GNU_SOURCE
#include <dlfcn.h>
#include <stddef.h>
#include <stdint.h>
#include <string.h>

#define ZC_MAGIC 0x5a43484fu
#define MIN_ROW 1024 // bytes; smaller copies are never frame rows

static void *(*real_memcpy)(void *, const void *, size_t);

// The row copy in progress: rows of one tagged frame, from the first tag row on.
static __thread const uint8_t *frame_src;
static __thread size_t frame_row;
static __thread uint32_t rows_left, frame_h;

static int tagged(const void *p)
{
    uint32_t v;
    __builtin_memcpy(&v, p, 4);
    return v == ZC_MAGIC;
}

void *memcpy(void *dst, const void *src, size_t n)
{
    if (!real_memcpy) {
        real_memcpy = (void *(*)(void *, const void *, size_t))dlsym(RTLD_NEXT, "memcpy");
    }
    if (n < MIN_ROW) {
        return real_memcpy(dst, src, n);
    }
    const uint8_t *s = src;
    if (tagged(s)) {
        uint32_t tag[4];
        __builtin_memcpy(tag, s, sizeof(tag));
        const uint32_t w = tag[2], h = tag[3] & 0x7fffffffu;
        const size_t row = (size_t)w * 4;
        if (row && h > 1 && n >= row * h && n % h == 0) {
            // whole frame at once: its stride is n / h; first and last row only
            const size_t stride = n / h;
            real_memcpy(dst, s, row);
            real_memcpy((uint8_t *)dst + stride * (h - 1), s + stride * (h - 1), row);
            return dst;
        }
        if (!(tag[3] & 0x80000000u) && n <= row) {
            // first row of a row-by-row copy: skip the following rows of this frame
            frame_src = s;
            frame_row = n;
            frame_h = h;
            rows_left = h - 2;
        } else {
            rows_left = 0;
        }
        return real_memcpy(dst, src, n);
    }
    // rows of that frame: same length, after the first row, within a stride of at
    // most twice the row
    if (rows_left && n == frame_row && s > frame_src && s < frame_src + 2 * frame_row * frame_h) {
        rows_left--;
        return dst;
    }
    return real_memcpy(dst, src, n);
}
