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
    kernel/drivers/block/virtio_blk.ko* kernel/drivers/block/loop.ko* \
    kernel/drivers/input kernel/drivers/hid \
    kernel/drivers/usb kernel/fs/fat kernel/fs/nls kernel/lib \
    kernel/drivers/scsi/scsi_mod.ko* kernel/drivers/scsi/sr_mod.ko* \
    kernel/drivers/cdrom kernel/fs/isofs kernel/fs/fuse \
    "$R/lib/modules/$kver/" 2>/dev/null || true)
cp -a "$M/updates" "$R/lib/modules/$kver/"
# only the patched vmwgfx: the kernel's own autoload would otherwise pick the in-tree one
rm -rf "$R/lib/modules/$kver/kernel/drivers/gpu/drm/vmwgfx"
cp "$W/k/etc/modprobe.d/vmwgfx-oseasy.conf" "$R/etc/modprobe.d/"
# for the install mode: the module and its options, copied into the written disk
install -D -m644 "$M/updates/vmwgfx.ko" "$R/oseasy/vmwgfx.ko"
install -D -m644 "$W/k/etc/modprobe.d/vmwgfx-oseasy.conf" "$R/oseasy/vmwgfx-oseasy.conf"
# added to the installed disk: desktop autostart (Route F's)
install -D -m755 "$here/../../emulator/guest/desktop-autostart.sh" "$R/oseasy/desktop-autostart.sh"
install -D -m755 "$here/../guest/boot-diag.sh" "$R/oseasy/boot-diag.sh"
install -D -m644 "$here/../guest/ohmarchy-boot-diag.service" "$R/oseasy/ohmarchy-boot-diag.service"
# API relay config, baked in for PRIVATE builds only: PROBE_AI_ENV points at a
# KEY=value file of OHM_AI_* (from /data/local/secrets/ai.env). Public builds get
# an empty file, so the key never ships in the ISO. NEVER commit a filled ai.env.
if [ -n "${PROBE_AI_ENV:-}" ] && [ -f "$PROBE_AI_ENV" ]; then
    install -D -m600 "$PROBE_AI_ENV" "$R/oseasy/ai.env"
else
    : > "$W/empty.aienv"; install -D -m600 "$W/empty.aienv" "$R/oseasy/ai.env"
fi
# Shared agent-tool setup (Claude Code / Codex / opencode), same config on every
# line. The install runs it as the desktop user with /oseasy/ai.env.
install -D -m755 "$here/../../hongrong/pure/guest/setup-ai.sh" "$R/oseasy/setup-ai.sh"
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
copy_bin /usr/bin/e2fsck     # root-on-image boot: fsck the loop-mounted ext4
copy_bin /usr/bin/resize2fs  # and grow it to fill the truncated image
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
# PROBE_DEFAULT picks the default menu entry (0-based). Entries: 0 = smart boot
# (boot an installed Omarchy on vda, else install) -- the install ISO's default;
# 1 = EFI framebuffer; 2-4 = vmwgfx diagnostics; 5 = plain install mode.
sed "s/^set default=.*/set default=${PROBE_DEFAULT:-0}/" "$here/grub.cfg" > "$W/esp/grub.cfg"
mkdir -p "$W/esp/EFI/BOOT"
# ext2 + search_fs_uuid let the smart entry read the ext4 vda and run the disk's
# own grub.cfg (which finds its root by fs-uuid); see oseasy/probe/grub.cfg.
grub-mkstandalone -d "$W/t/usr/lib/grub/arm64-efi" -O arm64-efi \
    -o "$W/esp/EFI/BOOT/BOOTAA64.EFI" \
    --modules="part_gpt part_msdos ext2 fat iso9660 search search_fs_file search_fs_uuid configfile chain linux normal echo all_video" \
    "boot/grub/grub.cfg=$W/grub-early.cfg"

# 5. ESP image, ISO and GPT disk
# The El Torito EFI boot image only needs the GRUB binary: GRUB then finds the
# ISO9660 volume by the /oseasy-probe marker and reads grub.cfg, Image and
# initramfs.img from it (the loose files copied into $W/iso below). Keeping the
# ~160 MB kernel+initramfs OUT of this FAT image avoids duplicating them, so an
# ISO carrying a ~1.7 GiB embedded disk image still fits under the 2 GiB limit.
mkdir -p "$W/espmin"; cp -r "$W/esp/EFI" "$W/espmin/"
# The FAT image must be a valid FAT32 ESP or the firmware will not boot BOOTAA64
# (it drops to the EFI shell). FAT32 needs >=65525 clusters, i.e. roughly >=36 MB
# at 512 B/cluster, so floor the size at 48 MB even though BOOTAA64 alone is small.
mib=$(( $(du -sm "$W/espmin" | cut -f1) + 4 )); [ "$mib" -lt 48 ] && mib=48
truncate -s ${mib}M "$W/efiboot.img"
mkfs.fat -F 32 -n PROBE "$W/efiboot.img" >/dev/null
mcopy -s -i "$W/efiboot.img" "$W/espmin/"* ::/
mkdir -p "$W/iso"; cp "$W/efiboot.img" "$W/iso/"; cp -r "$W/esp/"* "$W/iso/"
# PROBE_IMGZST embeds a zstd-compressed raw disk image in the ISO data area (not in
# the El Torito ESP, which stays small). The install mode mounts this same CD and
# writes it to /dev/vda, so installing needs no host and no network. Makes the ISO
# roughly image-sized; check that Oseasy accepts an ISO that large.
[ -n "${PROBE_IMGZST:-}" ] && [ -f "$PROBE_IMGZST" ] && \
    cp "$PROBE_IMGZST" "$W/iso/omarchy-pure.img.zst"
xorriso -as mkisofs -quiet -V OSEASY_PROBE -J -R -e efiboot.img -no-emul-boot \
    -isohybrid-gpt-basdat -o "$out/oseasy-probe.iso" "$W/iso"
truncate -s $(( mib + 2 ))M "$out/oseasy-probe.img"
sfdisk -q "$out/oseasy-probe.img" <<PT
label: gpt
start=1MiB, size=${mib}MiB, type=uefi, name=ESP
PT
dd if="$W/efiboot.img" of="$out/oseasy-probe.img" bs=1M seek=1 conv=notrunc status=none
# Report sizes (not sha256: integrity on ohdev is cp rc + byte-size, per Yao).
ls -ln "$out"/oseasy-probe.iso "$out"/oseasy-probe.img
echo PROBE_DONE "$kver"
