/*
 * swtest SURFACE_ID [SECONDS]: can a process other than the app that owns a
 * surface (here: root on the host, as vhost-device-gpu would be) draw into it?
 * Route I, option A in docs/vm-own.md. Creates a native window from the
 * surface id that route D's app logs ("xcomponent surface id"), then requests,
 * fills and flushes buffers: alternating red/blue for SECONDS (default 5),
 * reporting each step's return code.
 *
 * Built with the OpenHarmony NDK (DevEco), linked against libnative_window:
 *   $NDK/llvm/bin/clang --target=aarch64-linux-ohos --sysroot=$NDK/sysroot \
 *     -O2 -o swtest swtest.c -lnative_window -lnative_buffer
 */
#include <native_window/external_window.h>
#include <native_buffer/native_buffer.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/mman.h>
#include <time.h>
#include <unistd.h>

static double now(void)
{
	struct timespec t;
	clock_gettime(CLOCK_MONOTONIC, &t);
	return t.tv_sec + t.tv_nsec / 1e9;
}

int main(int argc, char **argv)
{
	if (argc < 2) { fprintf(stderr, "usage: swtest SURFACE_ID [SECONDS]\n"); return 2; }
	uint64_t id = strtoull(argv[1], NULL, 0);
	double secs = argc > 2 ? atof(argv[2]) : 5;
	OHNativeWindow *w = NULL;
	int32_t r = OH_NativeWindow_CreateNativeWindowFromSurfaceId(id, &w);
	printf("CreateNativeWindowFromSurfaceId(%llu) = %d, window %p\n", (unsigned long long)id, r, (void *)w);
	if (r || !w) return 1;
	int32_t width = 0, height = 0;
	r = OH_NativeWindow_NativeWindowHandleOpt(w, GET_BUFFER_GEOMETRY, &height, &width);
	printf("geometry %dx%d (rc %d)\n", width, height, r);
	if (width <= 0 || height <= 0) {
		width = 640; height = 480;
		OH_NativeWindow_NativeWindowHandleOpt(w, SET_BUFFER_GEOMETRY, width, height);
	}
	OH_NativeWindow_NativeWindowHandleOpt(w, SET_FORMAT, NATIVEBUFFER_PIXEL_FMT_RGBA_8888);
	OH_NativeWindow_NativeWindowHandleOpt(w, SET_USAGE,
		(uint64_t)(NATIVEBUFFER_USAGE_CPU_READ | NATIVEBUFFER_USAGE_CPU_WRITE | NATIVEBUFFER_USAGE_MEM_DMA));
	int frames = 0, fails = 0;
	double t0 = now();
	while (now() - t0 < secs) {
		OHNativeWindowBuffer *b = NULL;
		int fence = -1;
		r = OH_NativeWindow_NativeWindowRequestBuffer(w, &b, &fence);
		if (r || !b) { if (fails++ < 3) printf("RequestBuffer = %d\n", r); usleep(10000); continue; }
		if (fence >= 0) close(fence);
		BufferHandle *h = OH_NativeWindow_GetBufferHandleFromNative(b);
		void *p = h ? mmap(NULL, h->size, PROT_READ | PROT_WRITE, MAP_SHARED, h->fd, 0) : MAP_FAILED;
		if (p != MAP_FAILED) {
			uint32_t c = (frames / 30) % 2 ? 0xffff0000u : 0xff0000ffu; /* ABGR: blue / red */
			for (int y = 0; y < h->height; y++) {
				uint32_t *row = (uint32_t *)((char *)p + (size_t)y * h->stride);
				for (int x = 0; x < h->width; x++) row[x] = c;
			}
			munmap(p, h->size);
		} else if (frames == 0) {
			printf("mmap of the buffer failed (handle %p)\n", (void *)h);
		}
		Region region = { NULL, 0 };
		r = OH_NativeWindow_NativeWindowFlushBuffer(w, b, -1, region);
		if (r && fails++ < 3) printf("FlushBuffer = %d\n", r);
		if (!r) frames++;
	}
	printf("%d buffers flushed in %.1f s (%.1f/s), %d failures\n", frames, secs, frames / secs, fails);
	OH_NativeWindow_DestroyNativeWindow(w);
	return frames ? 0 : 1;
}
