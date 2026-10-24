#!/bin/bash
# Build the 铠大师 probe ISO: Debian 12 arm64 netboot mini.iso (Microsoft-signed
# shim, Debian-signed GRUB and kernel) plus a fake sources/install.wim whose XML
# metadata reads as Windows 11 24H2 ARM64, a probe initrd and a GRUB menu.
#   tools/kaidashi/probe-iso/build.sh WORKDIR [KERNEL_PKG]
#     -> WORKDIR/kds-probe.iso, or with a linux-aarch64 package (7.2.12 with the
#        HMV ID-register patches) WORKDIR/kds-k72.iso whose default entry boots
#        that kernel's Image with arm64.hmv_idreg_quirk.
# Needs curl, xorriso, wimlib-imagex, cpio, gzip.
set -euo pipefail
here=$(cd "$(dirname "$0")" && pwd)
W=${1:-work/kaidashi}; mkdir -p "$W"; W=$(cd "$W" && pwd)
MINI_URL=https://deb.debian.org/debian/dists/bookworm/main/installer-arm64/current/images/netboot/mini.iso
[ -f "$W/mini.iso" ] || curl -fsSL -o "$W/mini.iso" "$MINI_URL"
"$here/../make-fake-wim.sh" "$W/install.wim"
rm -rf "$W/probe-root"; mkdir -p "$W/probe-root"; cp "$here/probe.sh" "$W/probe-root/probe.sh"
(cd "$W/probe-root" && echo probe.sh | cpio -o -H newc 2>/dev/null | gzip -9 > "$W/probe.cpio.gz")
out=kds-probe.iso cfg=grub.cfg extra=()
if [ -n "${2:-}" ]; then
  rm -rf "$W/k"; mkdir -p "$W/k"; bsdtar -xf "$2" -C "$W/k" boot/Image
  out=kds-k72.iso cfg=grub-k72.cfg extra=(-map "$W/k/boot/Image" /k72/Image)
fi
rm -f "$W/$out"
xorriso -indev "$W/mini.iso" -outdev "$W/$out" "${extra[@]}" \
  -map "$W/install.wim" /sources/install.wim \
  -map "$W/probe.cpio.gz" /probe.cpio.gz \
  -map "$here/$cfg" /boot/grub/grub.cfg \
  -volid CCCOMA_A64FRE_ZH-CN_DV9 \
  -joliet on -boot_image any replay 2>&1 | tail -2
ls -l "$W/$out"
