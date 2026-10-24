// prime-close: the check Hyprland's linux-dmabuf makes on every client buffer:
// drmPrimeFDToHandle() on the compositor's DRM fd, then drmCloseBufferHandle()
// (DRM_IOCTL_GEM_CLOSE). The buffer comes from GBM on another open of the device,
// like a client's.
//   prime-close [CLIENT_DEVICE] [COMPOSITOR_DEVICE]
#include <errno.h>
#include <fcntl.h>
#include <stdio.h>
#include <string.h>
#include <gbm.h>
#include <xf86drm.h>

int main(int argc, char **argv)
{
	const char *cdev = argc > 1 ? argv[1] : "/dev/dri/renderD128";
	const char *sdev = argc > 2 ? argv[2] : "/dev/dri/card0";
	int cfd = open(cdev, O_RDWR), sfd = open(sdev, O_RDWR);
	struct gbm_bo *bo = gbm_bo_create(gbm_create_device(cfd), 300, 300, GBM_FORMAT_XRGB8888,
					  GBM_BO_USE_RENDERING);
	int dfd = gbm_bo_get_fd(bo);
	uint32_t h = 0;
	int r = drmPrimeFDToHandle(sfd, dfd, &h);
	printf("drmPrimeFDToHandle on %s: %d (%s), handle %u\n", sdev, r, r ? strerror(errno) : "ok", h);
	r = drmCloseBufferHandle(sfd, h);
	printf("drmCloseBufferHandle: %d (%s)\n", r, r ? strerror(errno) : "ok");
	return 0;
}
