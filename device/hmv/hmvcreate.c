/* hmvcreate: Route H HMV permission test. RUN ONLY UNDER /data/local/vm.lock with the
 * 鸿融 main VM stopped. Opens /dev/hmv and attempts the create-VM ioctl (magic 0xAE, nr
 * 0x01 — the HMV analogue of KVM_CREATE_VM, from stratovirt's decoded 0xAE set) in a few
 * encodings, reporting errno only. It does NOT create vCPUs, set memory, or run anything,
 * to minimise impact. Interpretation:
 *   EPERM/EACCES -> permission gate blocks create outside the ohsw_stratovirt domain
 *   ENOSYS/ENOTTY -> that nr/encoding is not the create-VM call
 *   success(>=0) or EINVAL/EFAULT -> the call is REACHABLE (permission allows it) */
#include <errno.h>
#include <fcntl.h>
#include <stdint.h>
#include <stdio.h>
#include <string.h>
#include <sys/ioctl.h>
#include <unistd.h>

#define KVMIO 0xAE
#define _IO_(nr)        _IO(KVMIO, nr)
#define _IOW4(nr)       _IOW(KVMIO, nr, uint32_t)
#define _IOWR24(nr)     _IOWR(KVMIO, nr, struct s24)
struct s24 { uint8_t b[24]; };

static void try_ioctl(int fd, const char *name, unsigned long req, void *arg) {
    int r = ioctl(fd, req, arg);
    printf("%-26s req=0x%08lx -> ret=%d errno=%d (%s)\n",
           name, req, r, r < 0 ? errno : 0, r < 0 ? strerror(errno) : "ok");
    if (r >= 0) { printf("  REACHABLE: got fd/handle %d; closing it, NOT proceeding\n", r); close(r); }
}

int main(int argc, char **argv) {
    const char *dev = argc > 1 ? argv[1] : "/dev/hmv";
    int fd = open(dev, O_RDWR | O_CLOEXEC);
    if (fd < 0) { printf("open %s: %s (errno %d)\n", dev, strerror(errno), errno); return 1; }
    printf("open %s: ok\n", dev);
    uint32_t zero32 = 0; struct s24 zero24; memset(&zero24, 0, sizeof zero24);
    try_ioctl(fd, "create-vm _IO(0x01)",     _IO_(0x01),    (void *)0);
    try_ioctl(fd, "create-vm _IOW(0x01,u32)", _IOW4(0x01),   &zero32);
    try_ioctl(fd, "create-vm _IOWR(0x01,24)", _IOWR24(0x01), &zero24);
    close(fd);
    return 0;
}
