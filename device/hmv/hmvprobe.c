/* hmvprobe: ask /dev/hmv (or another node) the read-only KVM questions.
 * No KVM_CREATE_VM, nothing that touches a running VM: API version, vCPU mmap size,
 * KVM_CHECK_EXTENSION for a few aarch64 capabilities. Static Linux aarch64 build. */
#include <errno.h>
#include <fcntl.h>
#include <stdio.h>
#include <string.h>
#include <sys/ioctl.h>
#include <unistd.h>

#define KVMIO 0xAE
#define KVM_GET_API_VERSION _IO(KVMIO, 0x00)
#define KVM_CHECK_EXTENSION _IO(KVMIO, 0x03)
#define KVM_GET_VCPU_MMAP_SIZE _IO(KVMIO, 0x04)

static const struct { int id; const char *name; } caps[] = {
    {3, "USER_MEMORY"}, {9, "NR_VCPUS"}, {66, "MAX_VCPUS"}, {70, "ONE_REG"},
    {102, "ARM_PSCI_0_2"}, {165, "ARM_VM_IPA_SIZE"}, {16, "IOEVENTFD"},
    {32, "IRQFD"}, {200, "ARM_PTRAUTH_ADDRESS"}, {123, "MAX_VCPU_ID"},
};

int main(int argc, char **argv)
{
    const char *dev = argc > 1 ? argv[1] : "/dev/hmv";
    int fd = open(dev, O_RDWR | O_CLOEXEC);
    if (fd < 0) { printf("open %s: %s (errno %d)\n", dev, strerror(errno), errno); return 1; }
    printf("open %s: ok\n", dev);
    int r = ioctl(fd, KVM_GET_API_VERSION, 0);
    printf("KVM_GET_API_VERSION = %d%s%s\n", r, r < 0 ? " " : "", r < 0 ? strerror(errno) : "");
    r = ioctl(fd, KVM_GET_VCPU_MMAP_SIZE, 0);
    printf("KVM_GET_VCPU_MMAP_SIZE = %d%s%s\n", r, r < 0 ? " " : "", r < 0 ? strerror(errno) : "");
    for (unsigned i = 0; i < sizeof caps / sizeof caps[0]; i++) {
        r = ioctl(fd, KVM_CHECK_EXTENSION, caps[i].id);
        printf("CHECK_EXTENSION %-20s = %d%s%s\n", caps[i].name, r, r < 0 ? " " : "", r < 0 ? strerror(errno) : "");
    }
    close(fd);
    return 0;
}
