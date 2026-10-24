#!/bin/bash
# Run in the session as root: sh arch.sh run 20-setup-arch.sh USER [UID]
# Base system on a fresh Arch Linux ARM root: DNS, pacman without sandbox,
# keys, full upgrade, catatonit, user with sudo, locales.
set -euo pipefail

user=${1:?user}
# No user namespace: uids are the host's, and HarmonyOS uses most of those
# below 10000 for its services (1000 system, 1001 radio, ...). 60000 is free.
uid=${2:-60000}
here=$(cd "$(dirname "$0")" && pwd)

# The tarball's resolv.conf links into systemd-resolved, which never runs here.
rm -f /etc/resolv.conf
printf 'nameserver 223.5.5.5\nnameserver 119.29.29.29\n' > /etc/resolv.conf
install -m 644 "$here/etc/mirrorlist" /etc/pacman.d/mirrorlist
# No Landlock in the HongMeng kernel: pacman's download sandbox fails.
grep -q '^DisableSandbox' /etc/pacman.conf || sed -i '/^\[options\]/a DisableSandbox' /etc/pacman.conf

pacman-key --init
pacman-key --populate archlinuxarm
pacman -Syu --noconfirm
pacman -S --noconfirm --needed base-devel git sudo catatonit

# HongMeng: splice() from a drained pipe whose writers are gone into another
# pipe fails with EPIPE instead of returning 0. coreutils cat splices through
# a pipe, so every `cat > file <<EOF` exits 1. Preload a fix that reports EOF.
gcc -O2 -shared -fPIC -o /usr/local/lib/libsplice-eof.so -x c - -ldl <<'EOF'
#define _GNU_SOURCE
#include <dlfcn.h>
#include <errno.h>
#include <fcntl.h>
#include <poll.h>
#include <sys/ioctl.h>
#include <sys/stat.h>
#include <unistd.h>

ssize_t splice(int in, __off64_t *off_in, int out, __off64_t *off_out, size_t len, unsigned int flags)
{
    static ssize_t (*real)(int, __off64_t *, int, __off64_t *, size_t, unsigned int);
    if (!real)
        real = dlsym(RTLD_NEXT, "splice");
    ssize_t n = real(in, off_in, out, off_out, len, flags);
    if (n < 0 && errno == EPIPE) {
        int avail = -1;
        struct stat st;
        struct pollfd p = { .fd = in, .events = POLLIN };
        if (fstat(in, &st) == 0 && S_ISFIFO(st.st_mode) &&
            ioctl(in, FIONREAD, &avail) == 0 && avail == 0 &&
            poll(&p, 1, 0) == 1 && (p.revents & POLLHUP))
            return 0;
        errno = EPIPE;
    }
    return n;
}
EOF
echo /usr/local/lib/libsplice-eof.so > /etc/ld.so.preload

userdel -r alarm 2>/dev/null || true
id "$user" >/dev/null 2>&1 || useradd -m -u "$uid" -U -G wheel -s /bin/bash "$user"
# passwordless only while installing: 40-install-desktop.sh ends it
echo '%wheel ALL=(ALL:ALL) NOPASSWD: ALL' > /etc/sudoers.d/10-wheel
chmod 440 /etc/sudoers.d/10-wheel
ln -sf /usr/share/zoneinfo/Asia/Shanghai /etc/localtime
sed -i 's/^#en_US.UTF-8/en_US.UTF-8/; s/^#zh_CN.UTF-8/zh_CN.UTF-8/' /etc/locale.gen
locale-gen
echo LANG=en_US.UTF-8 > /etc/locale.conf

echo "Done. Restart the session (arch.sh stop; arch.sh start) so catatonit is pid 1."
