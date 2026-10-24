#!/bin/bash
# Build the 铠大师 probe ISO: Debian 12 arm64 netboot mini.iso (Microsoft-signed
# shim, Debian-signed GRUB and kernel) plus a fake sources/install.wim whose XML
# metadata reads as Windows 11 24H2 ARM64, a probe initrd and a GRUB menu.
#   tools/kaidashi/probe-iso/build.sh WORKDIR   -> WORKDIR/kds-probe.iso
# Needs curl, xorriso, wimlib-imagex, cpio, gzip.
set -euo pipefail
here=$(cd "$(dirname "$0")" && pwd)
W=${1:-work/kaidashi}; mkdir -p "$W"; W=$(cd "$W" && pwd)
MINI_URL=https://deb.debian.org/debian/dists/bookworm/main/installer-arm64/current/images/netboot/mini.iso
[ -f "$W/mini.iso" ] || curl -fsSL -o "$W/mini.iso" "$MINI_URL"
"$here/../make-fake-wim.sh" "$W/install.wim"
rm -rf "$W/probe-root"; mkdir -p "$W/probe-root"; cp "$here/probe.sh" "$W/probe-root/probe.sh"
(cd "$W/probe-root" && echo probe.sh | cpio -o -H newc 2>/dev/null | gzip -9 > "$W/probe.cpio.gz")
rm -f "$W/kds-probe.iso"
xorriso -indev "$W/mini.iso" -outdev "$W/kds-probe.iso" \
  -map "$W/install.wim" /sources/install.wim \
  -map "$W/probe.cpio.gz" /probe.cpio.gz \
  -map "$here/grub.cfg" /boot/grub/grub.cfg \
  -volid CCCOMA_A64FRE_ZH-CN_DV9 \
  -joliet on -boot_image any replay 2>&1 | tail -2
ls -l "$W/kds-probe.iso"
