// prime-close: the check Hyprland's linux-dmabuf makes on every client buffer:
// drmPrimeFDToHandle() on the compositor's DRM fd, then drmCloseBufferHandle()
// (DRM_IOCTL_GEM_CLOSE). The buffer comes from GBM on another open of the device,
// like a client's.
// With COUNT, repeats create/export/import/close/destroy COUNT times and
// reports failures (for leaks: compare vmwgfx's debugfs memory before and after).
//   prime-close [CLIENT_DEVICE] [COMPOSITOR_DEVICE] [COUNT]
#include <errno.h>
#include <fcntl.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <gbm.h>
#include <xf86drm.h>

int main(int argc, char **argv)
{
	const char *cdev = argc > 1 ? argv[1] : "/dev/dri/renderD128";
	const char *sdev = argc > 2 ? argv[2] : "/dev/dri/card0";
	int count = argc > 3 ? atoi(argv[3]) : 0;
	int cfd = open(cdev, O_RDWR), sfd = open(sdev, O_RDWR);
	struct gbm_device *gbm = gbm_create_device(cfd);
	if (!count) {
		struct gbm_bo *bo = gbm_bo_create(gbm, 300, 300, GBM_FORMAT_XRGB8888, GBM_BO_USE_RENDERING);
		int dfd = gbm_bo_get_fd(bo);
		uint32_t h = 0;
		int r = drmPrimeFDToHandle(sfd, dfd, &h);
		printf("drmPrimeFDToHandle on %s: %d (%s), handle %u\n", sdev, r, r ? strerror(errno) : "ok", h);
		r = drmCloseBufferHandle(sfd, h);
		printf("drmCloseBufferHandle: %d (%s)\n", r, r ? strerror(errno) : "ok");
		r = drmCloseBufferHandle(sfd, h);
		printf("second drmCloseBufferHandle (must fail): %d (%s)\n", r, r ? strerror(errno) : "ok");
		return 0;
	}
	int bad_import = 0, bad_close = 0;
	for (int i = 0; i < count; i++) {
		struct gbm_bo *bo = gbm_bo_create(gbm, 512, 512, GBM_FORMAT_XRGB8888, GBM_BO_USE_RENDERING);
		int dfd = gbm_bo_get_fd(bo);
		uint32_t h = 0;
		if (drmPrimeFDToHandle(sfd, dfd, &h))
			bad_import++;
		else if (drmCloseBufferHandle(sfd, h))
			bad_close++;
		close(dfd);
		gbm_bo_destroy(bo);
	}
	printf("%d rounds of create/export/import/close/destroy (512x512): %d import failures, %d close failures\n",
	       count, bad_import, bad_close);
	return 0;
}
