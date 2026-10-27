#!/bin/bash
# build-ram-usb.sh: the all-in-RAM Omarchy for a USB stick (route E,
# docs/route-e.md "All-in-RAM USB stick"). Runs as root in an aarch64 Arch
# Linux ARM (route D's container on ohdev), needs gcc/make, debugfs (e2fsprogs),
# bsdtar (libarchive), zstd, grub (arm64-efi).
#   build-ram-usb.sh ROOT-IMAGE [WORK]
# ROOT-IMAGE is route B's disk (omarchy-small.img: GPT, root = partition 2).
# Output in WORK/out (default /var/tmp/ohm-e): BOOTAA64.EFI (standalone GRUB),
# grub.cfg, Image, dev.cpio, omarchy-root.cpio.zst, omarchy-ram.id. Copy
# BOOTAA64.EFI to /EFI/BOOT/ and the rest to /Omarchy-arm64/ of a FAT32 stick.
# The kernel is Arch Linux ARM's generic linux-aarch64. The drivers it lacks
# (efidrm, simpledrm, pcie-kirin, the HiSilicon PHYs) are built here as modules
# from the same kernel.org release against its headers. -j2 / -T2: the host
# is shared.
set -euo pipefail
here=$(cd "$(dirname "$0")" && pwd)
img=$1 W=${2:-/var/tmp/ohm-e}
PKGVER=${PKGVER:-7.3-1} SRCVER=${SRCVER:-7.3}
MIRROR=${MIRROR:-https://mirrors.tuna.tsinghua.edu.cn}
mkdir -p "$W/pkg" && cd "$W"

# 1. generic kernel and its headers
for p in linux-aarch64 linux-aarch64-headers; do
    f=pkg/$p-$PKGVER-aarch64.pkg.tar.xz
    [ -s "$f" ] || curl -sSf -m 1800 -o "$f" "$MIRROR/archlinuxarm/aarch64/core/${f#pkg/}"
done
rm -rf k h && mkdir k h
bsdtar -C k -xf pkg/linux-aarch64-$PKGVER-aarch64.pkg.tar.xz
bsdtar -C h -xf pkg/linux-aarch64-headers-$PKGVER-aarch64.pkg.tar.xz
KV=$(ls k/usr/lib/modules); H=$W/h/usr/lib/modules/$KV/build

# 2. the drivers it does not have, as out-of-tree modules
s=pkg/linux-$SRCVER.tar.xz
[ -s "$s" ] || curl -sSf -m 1800 -o "$s" "$MIRROR/kernel/v${SRCVER%%.*}.x/linux-$SRCVER.tar.xz"
rm -rf src mods && mkdir src
tar -C src --strip-components=1 -xJf "$s" linux-$SRCVER/drivers/gpu/drm/sysfb \
    linux-$SRCVER/drivers/pci/pci.h linux-$SRCVER/drivers/pci/controller/dwc linux-$SRCVER/drivers/phy/hisilicon
mkdir -p mods/sysfb mods/pci/controller/dwc mods/phy
cp src/drivers/gpu/drm/sysfb/*.[ch] mods/sysfb/
printf '%s\n' 'drm_sysfb_helper-y := drm_sysfb.o drm_sysfb_modeset.o drm_sysfb_screen_info.o' \
    'obj-m += drm_sysfb_helper.o efidrm.o simpledrm.o' > mods/sysfb/Kbuild
cp src/drivers/pci/pci.h mods/pci/
cp src/drivers/pci/controller/dwc/pcie-kirin.c src/drivers/pci/controller/dwc/pcie-designware.h mods/pci/controller/dwc/
echo 'obj-m += pcie-kirin.o' > mods/pci/controller/dwc/Kbuild
cp src/drivers/phy/hisilicon/*.c mods/phy/
echo "obj-m += $(cd mods/phy && ls *.c | sed 's/\.c$/.o/' | tr '\n' ' ')" > mods/phy/Kbuild
for d in sysfb pci/controller/dwc phy; do make -C "$H" M="$W/mods/$d" -j2 modules; done

# 3. route B's root, without loop devices (HongMeng has none): debugfs rdump
off=$(( $(sfdisk -d "$img" | awk -F'[=,]' '/start=/{n++; if (n == 2) print $2}') * 512 ))
rm -rf root && mkdir root
debugfs -c -R "rdump / $W/root" "$img?offset=$off"
R=$W/root

# 4. the generic kernel in place of route B's VM kernel; no disks; our /init
rm -rf "$R"/boot/Image* "$R"/boot/dtbs "$R"/boot/initramfs-linux*.img
for m in "$R"/usr/lib/modules/*; do [ "${m##*/}" = "$KV" ] || rm -rf "$m"; done
cp -a k/usr/lib/modules/"$KV" "$R"/usr/lib/modules/
mkdir -p "$R/usr/lib/modules/$KV/extra/ohm"
cp $(find mods -name '*.ko') "$R/usr/lib/modules/$KV/extra/ohm/"
depmod -b "$R" "$KV"
sed -i 's/^\(UUID=\)/# all in RAM: no disks (route E)  \1/' "$R/etc/fstab"
install -m 755 "$here/init" "$R/init"
install -m 644 "$here/ohmarchy-ram.sh" "$R/etc/profile.d/ohmarchy-ram.sh"
mkdir -p "$R/dev" "$R/proc" "$R/sys" "$R/run" "$R/tmp" && chmod 1777 "$R/tmp"

# 5. initrd (console and null first, the kernel opens /dev/console before
# /init), GRUB, kernel
rm -rf out && mkdir out
printf '%s\n' '#mtree' './dev type=dir mode=0755 uname=root gname=root' \
    './dev/console type=char device=native,5,1 mode=0600 uname=root gname=root' \
    './dev/null type=char device=native,1,3 mode=0666 uname=root gname=root' > dev.mtree
bsdtar -c --format newc -f out/dev.cpio @dev.mtree
bsdtar -c --format newc -f - -C "$R" . | zstd -q -T2 -10 -o out/omarchy-root.cpio.zst
cp k/boot/Image out/Image
grub-mkstandalone -O arm64-efi -o out/BOOTAA64.EFI \
    --modules="part_gpt part_msdos fat exfat search search_fs_file configfile linux normal echo test sleep efi_gop efifwsetup reboot read" \
    --locales= --fonts= --themes= "boot/grub/grub.cfg=$here/early.cfg"
cp "$here/grub.cfg" out/grub.cfg
echo "Omarchy in RAM (route E), kernel $KV, built $(date '+%F %T')" > out/omarchy-ram.id
ls -ln out
