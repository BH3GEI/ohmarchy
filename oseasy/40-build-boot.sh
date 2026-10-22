#!/usr/bin/env bash
# Build the 6.1 boot entries (UKIs) from Omarchy's own UKI and initramfs plus the
# Debian kernel, and install them with a Limine menu into the image's ESP.
set -euo pipefail
. "$(dirname "$0")/config.sh"
need mcopy mdir mmd cpio depmod python3
cd "$WORK"; . ./image.env
K=$WORK/k61 B=$WORK/boot L=$OHMARCHY_ROOT/oseasy/lib
E="omarchy.raw@@$ESP_OFFSET"
rm -rf "$B"; mkdir -p "$B"

# base: Omarchy's UKI (stub + its mkinitcpio initramfs, which is kernel-agnostic userspace)
BASE=EFI/Linux/omarchy_linux.efi
mdir -i "$E" "::/$BASE" >/dev/null 2>&1 || BASE=$(mdir -b -i "$E" ::/EFI/Linux | grep -i '\.efi$' | head -1 | sed 's#^::/##')
mcopy -o -i "$E" "::/$BASE" "$B/base.efi"
python3 "$L/uki.py" get "$B/base.efi" .initrd "$B/omarchy-initrd.img"

# 6.1 modules the initramfs needs (dependencies resolved from modules.dep)
python3 "$L/modsubset.py" "$K/modroot" "$KVER" "$B/sub" \
    virtio_pci virtio_blk virtio_net virtio_rng virtio_console btrfs vfat nls_ascii nls_cp437 \
    nls_iso8859_1 nls_utf8 xhci_pci usbhid hid_generic fuse virtiofs vmwgfx omarchy_efidrm
depmod -b "$B/sub" "$KVER" 2>/dev/null || depmod -b "$B/sub/usr" "$KVER"
( cd "$B/sub" && find . -mindepth 1 | LC_ALL=C sort | cpio --quiet -o -H newc -R 0:0 ) > "$B/modules.cpio"

# overlay: hooks, scripts, modprobe policy and the mkinitcpio /config
mkdir -p "$B/ov"; cp -a "$OHMARCHY_ROOT/oseasy/initramfs/." "$B/ov/"
mv "$B/ov/config-6.1" "$B/ov/config"
( cd "$B/ov" && find . -mindepth 1 | LC_ALL=C sort | cpio --quiet -o -H newc -R 0:0 ) > "$B/overlay.cpio"

CMD="root=UUID=$ROOT_UUID $KCMD_BASE"
mk() { python3 "$L/uki.py" build "$B/base.efi" "$B/$1" --linux "$K/Image" --uname "$KVER" \
        --initrd "$B/omarchy-initrd.img" --initrd "$B/modules.cpio" --initrd "$B/overlay.cpio" --cmdline "$CMD $2"; }
mk ohmarchy-6.1.efi        ""
mk ohmarchy-6.1-hold.efi   "omarchy_hold=1"
mk ohmarchy-6.1-efidrm.efi "omarchy_gpu=efidrm"
mk ohmarchy-6.1-svga.efi   "omarchy_gpu=svga"

# install: UKIs, module tarball, Limine menu; Limine becomes the fallback loader
for f in "$B"/ohmarchy-6.1*.efi; do mcopy -o -i "$E" "$f" ::/EFI/Linux/; done
mmd -i "$E" ::/ohmarchy 2>/dev/null || true
mcopy -o -i "$E" "$K/modules-$KVER.tar.gz" ::/ohmarchy/
mcopy -n -i "$E" ::/limine.conf "$B/limine.conf.omarchy" 2>/dev/null && mcopy -o -i "$E" "$B/limine.conf.omarchy" ::/ohmarchy/limine.conf.omarchy || true
mcopy -o -i "$E" "$OHMARCHY_ROOT/oseasy/limine.conf.in" ::/limine.conf
mcopy -o -i "$E" ::/EFI/limine/limine_aa64.efi "$B/limine_aa64.efi"
mcopy -o -i "$E" "$B/limine_aa64.efi" ::/EFI/BOOT/BOOTAA64.EFI
mdir -i "$E" ::/EFI/Linux | grep -i efi
mdir -i "$E" ::/ | tail -2
