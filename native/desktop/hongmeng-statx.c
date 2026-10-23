// Preloaded in the chroot: HongMeng returns EFAULT for statx(fd, "", AT_EMPTY_PATH),
// which Rust's File::metadata uses; glycin's image loaders then fail and GTK 3 apps
// abort on their first icon. Fall back to fstat for that case.
#define _GNU_SOURCE
#include <errno.h>
#include <fcntl.h>
#include <string.h>
#include <sys/stat.h>
#include <sys/syscall.h>
#include <sys/sysmacros.h>
#include <unistd.h>

int statx(int dirfd, const char *path, int flags, unsigned int mask, struct statx *x)
{
	long r = syscall(SYS_statx, dirfd, path, flags, mask, x);
	if (r == 0 || errno != EFAULT || !x || !path || path[0] || !(flags & AT_EMPTY_PATH))
		return r;
	struct stat s;
	if ((dirfd == AT_FDCWD ? stat(".", &s) : fstat(dirfd, &s)) != 0)
		return -1;
	memset(x, 0, sizeof *x);
	x->stx_mask = STATX_BASIC_STATS;
	x->stx_blksize = s.st_blksize; x->stx_nlink = s.st_nlink;
	x->stx_uid = s.st_uid; x->stx_gid = s.st_gid; x->stx_mode = s.st_mode;
	x->stx_ino = s.st_ino; x->stx_size = s.st_size; x->stx_blocks = s.st_blocks;
	x->stx_atime.tv_sec = s.st_atim.tv_sec; x->stx_atime.tv_nsec = s.st_atim.tv_nsec;
	x->stx_mtime.tv_sec = s.st_mtim.tv_sec; x->stx_mtime.tv_nsec = s.st_mtim.tv_nsec;
	x->stx_ctime.tv_sec = s.st_ctim.tv_sec; x->stx_ctime.tv_nsec = s.st_ctim.tv_nsec;
	x->stx_rdev_major = major(s.st_rdev); x->stx_rdev_minor = minor(s.st_rdev);
	x->stx_dev_major = major(s.st_dev); x->stx_dev_minor = minor(s.st_dev);
	return 0;
}
