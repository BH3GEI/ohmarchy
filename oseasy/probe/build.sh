#!/bin/bash
# Build a small boot probe for the Oseasy VM: Arch Linux ARM's linux-aarch64
# (with the HMV patches), the vmwgfx-oseasy module, kmod, modetest and busybox
# in an initramfs, booted by a standalone GRUB. Two containers with the same
# ESP: probe.iso (El Torito, for Oseasy's ISO install) and probe.img (GPT disk,
# to wrap as qcow2 for Oseasy's import).
#
# Runs as root in an Arch Linux ARM environment. Nothing is installed there:
# busybox, mtools, grub and xorriso are downloaded with pacman -Sw into the
# work directory and unpacked.
#   [PROBE_DEFAULT=N] build.sh OUTDIR linux-aarch64-*.pkg.tar.* vmwgfx-oseasy-*.pkg.tar.*
set -euo pipefail
out=${1:?outdir}; kpkg=${2:?kernel package}; vpkg=${3:?vmwgfx-oseasy package}
here=$(cd "$(dirname "$0")" && pwd)
W=$(mktemp -d /tmp/oseasy-probe.XXXXXX)
trap 'rm -rf "$W"' EXIT
mkdir -p "$out" "$W/cache" "$W/t" "$W/k" "$W/ir" "$W/esp"

# 1. Tools, unpacked into $W/t
pacman -Sw --noconfirm --cachedir "$W/cache" busybox mtools grub libisoburn libburn libisofs >/dev/null
for p in "$W"/cache/*.pkg.tar.*; do
    case $p in *.sig) continue ;; esac
    bsdtar -xf "$p" -C "$W/t" --exclude .PKGINFO --exclude .MTREE --exclude .BUILDINFO --exclude .INSTALL
done
export PATH=$W/t/usr/bin:$PATH LD_LIBRARY_PATH=$W/t/usr/lib

# 2. Kernel and module
bsdtar -xf "$kpkg" -C "$W/k"
bsdtar -xf "$vpkg" -C "$W/k"
kver=$(ls "$W/k/usr/lib/modules" | head -1)
img=
for f in "$W/k/boot/Image" "$W/k/usr/lib/modules/$kver/vmlinuz"; do [ -f "$f" ] && { img=$f; break; }; done
[ -n "$img" ] || { echo "no kernel image in $kpkg"; exit 1; }
echo "kernel $kver from $img"

# 3. initramfs
R=$W/ir
mkdir -p "$R"/{bin,sbin,etc,proc,sys,dev,run,tmp,root,lib/modules,usr/bin,usr/lib,etc/modprobe.d}
install -m755 "$W/t/usr/bin/busybox" "$R/bin/busybox"
M=$W/k/usr/lib/modules/$kver
mkdir -p "$R/lib/modules/$kver"
cp -a "$M"/modules.order "$M"/modules.builtin* "$R/lib/modules/$kver/"
(cd "$M" && cp -a --parents kernel/drivers/gpu kernel/drivers/net/virtio_net.ko* \
    kernel/drivers/net/net_failover.ko* kernel/net/core/failover.ko* kernel/drivers/virtio \
    kernel/drivers/block/virtio_blk.ko* kernel/drivers/input kernel/drivers/hid \
    kernel/drivers/usb kernel/fs/fat kernel/fs/nls kernel/lib "$R/lib/modules/$kver/" 2>/dev/null || true)
cp -a "$M/updates" "$R/lib/modules/$kver/"
# only the patched vmwgfx: the kernel's own autoload would otherwise pick the in-tree one
rm -rf "$R/lib/modules/$kver/kernel/drivers/gpu/drm/vmwgfx"
cp "$W/k/etc/modprobe.d/vmwgfx-oseasy.conf" "$R/etc/modprobe.d/"
# for the install mode: the module and its options, copied into the written disk
install -D -m644 "$M/updates/vmwgfx.ko" "$R/oseasy/vmwgfx.ko"
install -D -m644 "$W/k/etc/modprobe.d/vmwgfx-oseasy.conf" "$R/oseasy/vmwgfx-oseasy.conf"
# added to the installed disk: desktop autostart (Route F's)
install -D -m755 "$here/../../emulator/guest/desktop-autostart.sh" "$R/oseasy/desktop-autostart.sh"
# the probe chooses the options on the kernel command line (see init); drop the package's line
sed -i 's/^options/#options/' "$R/etc/modprobe.d/vmwgfx-oseasy.conf"
depmod -b "$R" "$kver"
# dynamic tools with their libraries (kmod reads .ko.zst; busybox modprobe cannot)
copy_bin() {
    install -m755 "$1" "$R/usr/bin/"
    ldd "$1" | awk '/=> \//{print $3} /^\s*\/lib/{print $1}' | while read -r l; do
        cp -nL "$l" "$R/usr/lib/" 2>/dev/null || true
    done
}
# GPU rendering test on KMS (Mesa's SVGA gallium driver through GBM/EGL)
gcc -O2 -o "$W/kmsgl" "$here/kmsgl.c" $(pkg-config --cflags --libs libdrm gbm egl glesv2) -lm
copy_bin "$W/kmsgl"
for l in /usr/lib/dri/vmwgfx_dri.so /usr/lib/gbm/dri_gbm.so /usr/lib/libEGL_mesa.so.0; do
    install -D -m755 "$(readlink -f "$l")" "$R$l"
    ldd "$l" | awk '/=> \//{print $3}' | while read -r d; do cp -nL "$d" "$R/usr/lib/" 2>/dev/null || true; done
done
install -D -m644 /usr/share/glvnd/egl_vendor.d/50_mesa.json "$R/usr/share/glvnd/egl_vendor.d/50_mesa.json"
copy_bin /usr/bin/dd     # coreutils: conv=sparse keeps the VM's qcow2 small
copy_bin /usr/bin/zstd   # the install mode takes a zstd stream
copy_bin /usr/bin/kmod
copy_bin /usr/bin/modetest
copy_bin /usr/bin/kmsprint 2>/dev/null || true
cp -L /usr/lib/ld-linux-aarch64.so.1 "$R/usr/lib/"
ln -s usr/lib "$R/lib64" 2>/dev/null || true
ln -sf ../usr/lib/ld-linux-aarch64.so.1 "$R/lib/ld-linux-aarch64.so.1"
for t in modprobe insmod rmmod lsmod modinfo depmod; do ln -sf kmod "$R/usr/bin/$t"; done
install -m755 "$here/init" "$R/init"
(cd "$R" && find . | cpio -o -H newc --quiet | gzip -9) > "$W/esp/initramfs.img"
cp "$img" "$W/esp/Image"
touch "$W/esp/oseasy-probe"
ls -la "$W/esp"

# 4. GRUB: standalone image whose embedded config finds the files by marker
cat > "$W/grub-early.cfg" <<'EOF'
search --no-floppy --file /oseasy-probe --set=root
set prefix=($root)/
configfile ($root)/grub.cfg
EOF
# PROBE_DEFAULT picks the default menu entry (0-based; 4 = install mode)
sed "s/^set default=.*/set default=${PROBE_DEFAULT:-1}/" "$here/grub.cfg" > "$W/esp/grub.cfg"
mkdir -p "$W/esp/EFI/BOOT"
grub-mkstandalone -d "$W/t/usr/lib/grub/arm64-efi" -O arm64-efi \
    -o "$W/esp/EFI/BOOT/BOOTAA64.EFI" \
    --modules="part_gpt part_msdos fat iso9660 search search_fs_file configfile linux normal echo all_video" \
    "boot/grub/grub.cfg=$W/grub-early.cfg"

# 5. ESP image, ISO and GPT disk
mib=$(( $(du -sm "$W/esp" | cut -f1) + 32 ))
truncate -s ${mib}M "$W/efiboot.img"
mkfs.fat -F 32 -n PROBE "$W/efiboot.img" >/dev/null 2>&1 || mkfs.fat -n PROBE "$W/efiboot.img" >/dev/null
mcopy -s -i "$W/efiboot.img" "$W/esp/"* ::/
mkdir -p "$W/iso"; cp "$W/efiboot.img" "$W/iso/"; cp -r "$W/esp/"* "$W/iso/"
xorriso -as mkisofs -quiet -V OSEASY_PROBE -J -R -e efiboot.img -no-emul-boot \
    -isohybrid-gpt-basdat -o "$out/oseasy-probe.iso" "$W/iso"
truncate -s $(( mib + 2 ))M "$out/oseasy-probe.img"
sfdisk -q "$out/oseasy-probe.img" <<PT
label: gpt
start=1MiB, size=${mib}MiB, type=uefi, name=ESP
PT
dd if="$W/efiboot.img" of="$out/oseasy-probe.img" bs=1M seek=1 conv=notrunc status=none
sha256sum "$out"/oseasy-probe.iso "$out"/oseasy-probe.img
echo PROBE_DONE "$kver"
