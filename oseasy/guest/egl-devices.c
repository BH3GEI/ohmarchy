// egl-devices: which renderer each EGL device gives (EGL_EXT_platform_device),
// the way Hyprland picks its renderer, and whether that display imports a dma-buf
// from the vmwgfx render node.
#include <fcntl.h>
#include <stdio.h>
#include <string.h>
#include <gbm.h>
#include <EGL/egl.h>
#include <EGL/eglext.h>
#include <GLES2/gl2.h>
#include <drm_fourcc.h>

int main(void)
{
	PFNEGLQUERYDEVICESEXTPROC qd = (void *)eglGetProcAddress("eglQueryDevicesEXT");
	PFNEGLQUERYDEVICESTRINGEXTPROC qs = (void *)eglGetProcAddress("eglQueryDeviceStringEXT");
	PFNEGLGETPLATFORMDISPLAYEXTPROC gp = (void *)eglGetProcAddress("eglGetPlatformDisplayEXT");
	PFNEGLCREATEIMAGEKHRPROC ci = (void *)eglGetProcAddress("eglCreateImageKHR");
	EGLDeviceEXT devs[8];
	EGLint n = 0;
	qd(8, devs, &n);
	int fd = open("/dev/dri/renderD128", O_RDWR);
	struct gbm_bo *bo = gbm_bo_create(gbm_create_device(fd), 300, 300, GBM_FORMAT_XRGB8888, GBM_BO_USE_RENDERING);
	int dfd = gbm_bo_get_fd(bo);
	for (int i = 0; i < n; i++) {
		const char *file = qs(devs[i], EGL_DRM_DEVICE_FILE_EXT);
		const char *rfile = qs(devs[i], EGL_DRM_RENDER_NODE_FILE_EXT);
		const char *ext = qs(devs[i], EGL_EXTENSIONS);
		EGLDisplay d = gp(EGL_PLATFORM_DEVICE_EXT, devs[i], NULL);
		EGLint ma, mi;
		if (!eglInitialize(d, &ma, &mi)) {
			printf("device %d (%s, %s): eglInitialize failed 0x%x\n", i, file ? file : "-", rfile ? rfile : "-", eglGetError());
			continue;
		}
		eglBindAPI(EGL_OPENGL_ES_API);
		EGLint ca[] = { EGL_CONTEXT_CLIENT_VERSION, 2, EGL_NONE };
		EGLContext c = eglCreateContext(d, EGL_NO_CONFIG_KHR, EGL_NO_CONTEXT, ca);
		eglMakeCurrent(d, EGL_NO_SURFACE, EGL_NO_SURFACE, c);
		EGLint a[] = { EGL_WIDTH, 300, EGL_HEIGHT, 300, EGL_LINUX_DRM_FOURCC_EXT, DRM_FORMAT_XRGB8888,
			       EGL_DMA_BUF_PLANE0_FD_EXT, dfd, EGL_DMA_BUF_PLANE0_OFFSET_EXT, 0,
			       EGL_DMA_BUF_PLANE0_PITCH_EXT, (EGLint)gbm_bo_get_stride(bo), EGL_NONE };
		EGLImageKHR img = ci(d, EGL_NO_CONTEXT, EGL_LINUX_DMA_BUF_EXT, NULL, a);
		printf("device %d (%s, %s): GL_RENDERER %s; dma-buf import %s (0x%x); software ext %s\n", i,
		       file ? file : "-", rfile ? rfile : "-", (const char *)glGetString(GL_RENDERER),
		       img != EGL_NO_IMAGE_KHR ? "OK" : "FAILED", eglGetError(),
		       ext && strstr(ext, "EGL_MESA_device_software") ? "yes" : "no");
	}
	return 0;
}
