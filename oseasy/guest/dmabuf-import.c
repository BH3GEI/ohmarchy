// dmabuf-import: can Mesa's SVGA driver import a dma-buf that it exported itself?
// This is what a Wayland compositor does with every GPU client buffer
// (linux-dmabuf). Allocates an XRGB8888 buffer with GBM on DEVICE, exports it as
// a dma-buf fd, and imports it with eglCreateImageKHR(EGL_LINUX_DMA_BUF_EXT) on
// an EGL display of IMPORT_DEVICE: once without a modifier, once with the
// buffer's own modifier. Prints the EGL error of each attempt. With "fork", the
// import happens in a child process with its own device file and EGL display, as
// between a Wayland client and the compositor.
//   dmabuf-import [DEVICE] [IMPORT_DEVICE] [fork]  (default /dev/dri/renderD128 twice)
#include <fcntl.h>
#include <stdio.h>
#include <string.h>
#include <sys/wait.h>
#include <unistd.h>
#include <gbm.h>
#include <EGL/egl.h>
#include <EGL/eglext.h>
#include <drm_fourcc.h>

static EGLDisplay display_for(struct gbm_device *gbm)
{
	PFNEGLGETPLATFORMDISPLAYEXTPROC get = (void *)eglGetProcAddress("eglGetPlatformDisplayEXT");
	EGLDisplay d = get(EGL_PLATFORM_GBM_KHR, gbm, NULL);
	EGLint ma, mi;
	if (!eglInitialize(d, &ma, &mi)) {
		printf("eglInitialize failed 0x%x\n", eglGetError());
		return EGL_NO_DISPLAY;
	}
	return d;
}

static void try_import(EGLDisplay d, struct gbm_bo *bo, int fd, int with_mod)
{
	PFNEGLCREATEIMAGEKHRPROC create = (void *)eglGetProcAddress("eglCreateImageKHR");
	uint64_t mod = gbm_bo_get_modifier(bo);
	EGLint a[32], n = 0;
	a[n++] = EGL_WIDTH; a[n++] = gbm_bo_get_width(bo);
	a[n++] = EGL_HEIGHT; a[n++] = gbm_bo_get_height(bo);
	a[n++] = EGL_LINUX_DRM_FOURCC_EXT; a[n++] = DRM_FORMAT_XRGB8888;
	a[n++] = EGL_DMA_BUF_PLANE0_FD_EXT; a[n++] = fd;
	a[n++] = EGL_DMA_BUF_PLANE0_OFFSET_EXT; a[n++] = gbm_bo_get_offset(bo, 0);
	a[n++] = EGL_DMA_BUF_PLANE0_PITCH_EXT; a[n++] = gbm_bo_get_stride(bo);
	if (with_mod) {
		a[n++] = EGL_DMA_BUF_PLANE0_MODIFIER_LO_EXT; a[n++] = mod & 0xffffffff;
		a[n++] = EGL_DMA_BUF_PLANE0_MODIFIER_HI_EXT; a[n++] = mod >> 32;
	}
	a[n++] = EGL_NONE;
	EGLImageKHR img = create(d, EGL_NO_CONTEXT, EGL_LINUX_DMA_BUF_EXT, NULL, a);
	printf("import %s modifier (bo modifier 0x%llx, stride %u): %s (EGL error 0x%x)\n",
	       with_mod ? "with" : "without", (unsigned long long)mod, gbm_bo_get_stride(bo),
	       img != EGL_NO_IMAGE_KHR ? "OK" : "FAILED", eglGetError());
}

int main(int argc, char **argv)
{
	const char *dev = argc > 1 ? argv[1] : "/dev/dri/renderD128";
	const char *idev = argc > 2 ? argv[2] : dev;
	int forked = argc > 3 && !strcmp(argv[3], "fork");
	int fd = open(dev, O_RDWR);
	if (fd < 0) { perror("open"); return 1; }
	struct gbm_device *gbm = gbm_create_device(fd);
	struct gbm_bo *bo = gbm_bo_create(gbm, 300, 300, GBM_FORMAT_XRGB8888, GBM_BO_USE_RENDERING);
	if (!bo) { printf("gbm_bo_create failed\n"); return 1; }
	int dfd = gbm_bo_get_fd(bo);
	printf("exported dma-buf fd %d from %s%s\n", dfd, dev, forked ? ", importing in a child process" : "");
	if (forked && fork() > 0) {
		wait(NULL);
		return 0;
	}
	int ifd = open(idev, O_RDWR);
	if (ifd < 0) { perror("open"); return 1; }
	EGLDisplay d = display_for(gbm_create_device(ifd));
	if (d == EGL_NO_DISPLAY) return 1;
	printf("import on %s; EGL vendor %s\n", idev, eglQueryString(d, EGL_VENDOR));
	try_import(d, bo, dfd, 0);
	try_import(d, bo, dfd, 1);
	return 0;
}
