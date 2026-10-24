#!/bin/bash
# Build the 铠大师 Omarchy installer ISO: Debian 12 arm64 netboot mini.iso (for
# its GRUB and d-i initrd/busybox) + a fake Windows 11 24H2 ARM64 install.wim
# (passes 铠大师's ISO check) + the linux-aarch64 7.2.12 HMV-quirk kernel and the
# four modules the installer needs + write-disk.sh and probe.sh.
#   tools/kaidashi/installer/build.sh WORKDIR KERNEL_PKG  -> WORKDIR/kds-installer.iso
# Secure Boot is off in a fresh 铠大师 VM, so nothing needs signing.
# Needs curl, xorriso, wimlib-imagex, bsdtar, cpio, gzip, clang + lld (aarch64 target).
set -euo pipefail
here=$(cd "$(dirname "$0")" && pwd)
W=${1:?workdir}; PKG=${2:?linux-aarch64 package}
mkdir -p "$W"; W=$(cd "$W" && pwd)
MINI_URL=https://deb.debian.org/debian/dists/bookworm/main/installer-arm64/current/images/netboot/mini.iso
[ -f "$W/mini.iso" ] || curl -fsSL -o "$W/mini.iso" "$MINI_URL"
"$here/../make-fake-wim.sh" "$W/install.wim"
rm -rf "$W/k" "$W/inst-root"; mkdir -p "$W/k" "$W/inst-root/kmod"
bsdtar -xf "$PKG" -C "$W/k" boot/Image 'usr/lib/modules/*/kernel/net/core/failover.ko' \
  'usr/lib/modules/*/kernel/drivers/net/net_failover.ko' 'usr/lib/modules/*/kernel/drivers/net/virtio_net.ko' \
  'usr/lib/modules/*/kernel/fs/isofs/isofs.ko' 'usr/lib/modules/*/kernel/fs/fuse/fuse.ko' \
  'usr/lib/modules/*/kernel/fs/fuse/virtiofs.ko'
find "$W/k/usr" -name '*.ko' -exec cp {} "$W/inst-root/kmod/" \;
cp "$here/write-disk.sh" "$here/../probe-iso/probe.sh" "$W/inst-root/"
mkdir -p "$W/inst-root/kds"
clang --target=aarch64-linux-gnu -O2 -ffreestanding -fno-builtin -fno-stack-protector \
  -nostdlib -static -fuse-ld=lld -o "$W/inst-root/kds/sparsecp" "$here/sparsecp.c"
# Route B's patched vmwgfx for this kernel (VMWGFX_KO, e.g. extracted from
# oseasy-probe.iso's initramfs) and its packaged options, written into the
# Omarchy root after the disk write.
if [ -n "${VMWGFX_KO:-}" ]; then
  mkdir -p "$W/inst-root/kds"
  cp "$VMWGFX_KO" "$W/inst-root/kds/vmwgfx.ko"
  cp "$here/../../../oseasy/vmwgfx-7.2/vmwgfx-oseasy.conf" "$W/inst-root/kds/"
fi
(cd "$W/inst-root" && find . | cpio -o -H newc 2>/dev/null | gzip -9 > "$W/installer.cpio.gz")
rm -f "$W/kds-installer.iso"
xorriso -indev "$W/mini.iso" -outdev "$W/kds-installer.iso" \
  -map "$W/k/boot/Image" /k72/Image \
  -map "$W/install.wim" /sources/install.wim \
  -map "$W/installer.cpio.gz" /installer.cpio.gz \
  -map "$here/grub.cfg" /boot/grub/grub.cfg \
  -volid CCCOMA_A64FRE_ZH-CN_DV9 \
  -joliet on -boot_image any replay 2>&1 | tail -2
ls -l "$W/kds-installer.iso"
