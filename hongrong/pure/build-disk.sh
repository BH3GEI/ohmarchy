#!/bin/bash
# NOT YET TESTED end to end (2026-10-24): written, syntax-checked, first run pending.
# Build a disk image with Omarchy alone (no deepin) for the 鸿融 VM: GPT with an
# EFI system partition and an ext4 root, Arch Linux ARM's linux-aarch64 with the
# 鸿融 patches (hongrong/kernel/patches) installed as a package, and a
# standalone GRUB at the removable-media path so the VM's UEFI finds it without
# boot entries. Nothing is mounted except bind mounts for the chroot: the
# filesystems are made from directories (mkfs.ext4 -d, mtools) and placed at
# their partition offsets. pacstrap and arch-chroot are not used: they mount
# devtmpfs, which the HongMeng kernel does not have; /dev is bind-mounted.
#
# Runs as root in an Arch Linux ARM environment with network access (e.g. the
# native Arch environment on the HarmonyOS host, via arch.sh run).
# Usage: build-disk.sh WORKDIR USER PASSWORD KERNEL_PKG...
#   WORKDIR gets root/, esp.img, root.img and the result omarchy-pure.img
set -euo pipefail

W=${1:?workdir}; user=${2:?user}; password=${3:?password}; shift 3
pkgs=("$@"); [ ${#pkgs[@]} -gt 0 ] || { echo "no kernel packages given"; exit 1; }
here=$(cd "$(dirname "$0")/.." && pwd)        # hongrong/
disk_gib=${DISK_GIB:-64} esp_mib=${ESP_MIB:-512}
cmdline=${CMDLINE:-"rw arm64.hmv_idreg_quirk console=tty0 console=ttyAMA0,115200"}
R=$W/root

pacman -S --needed --noconfirm mtools dosfstools e2fsprogs grub >/dev/null
mkdir -p "$W" "$R"
chroot_up() {
  # / must be a mount point in the chroot, or pacman cannot check free space
  mountpoint -q "$R" || mount --bind "$R" "$R"
  mkdir -p "$R"/{proc,sys,dev,run,tmp,etc}
  mountpoint -q "$R/proc" || mount -t proc proc "$R/proc"
  # /sys is a tmpfs with only the VM's DMI identity: Omarchy's install steps
  # probe hardware there (under bash -e, a missing /sys/class/dmi aborts them),
  # and they should see the 鸿融 VM, not the machine building the image.
  if ! mountpoint -q "$R/sys"; then
    mount -t tmpfs sys "$R/sys"
    mkdir -p "$R/sys/class/dmi/id"
    echo "KVM Virtual Machine" > "$R/sys/class/dmi/id/product_name"
    : > "$R/sys/class/dmi/id/sys_vendor"; : > "$R/sys/class/dmi/id/product_family"; : > "$R/sys/class/dmi/id/board_name"
  fi
  mountpoint -q "$R/dev" || mount --bind /dev "$R/dev"
  mountpoint -q "$R/run" || mount -t tmpfs run "$R/run"
  # package cache outside the image, kept across runs
  mkdir -p "$W/../pkgcache" "$R/var/cache/pacman/pkg"
  mountpoint -q "$R/var/cache/pacman/pkg" || mount --bind "$W/../pkgcache" "$R/var/cache/pacman/pkg"
  cp -L /etc/resolv.conf "$R/etc/resolv.conf"
  # the build environment's HongMeng shims (ld.so.preload), for programs run in
  # the chroot; removed before the filesystem image is made
  if [ -s /etc/ld.so.preload ] && [ -d "$R/usr/lib" ]; then
    mkdir -p "$R/usr/local/lib/hmbuild"
    for l in $(cat /etc/ld.so.preload); do cp -f "$l" "$R/usr/local/lib/hmbuild/"; done
    for l in $(cat /etc/ld.so.preload); do echo "/usr/local/lib/hmbuild/$(basename "$l")"; done > "$R/etc/ld.so.preload"
  fi
}
chroot_down() { for m in var/cache/pacman/pkg run dev sys proc; do umount -l "$R/$m" 2>/dev/null || true; done; umount -l "$R" 2>/dev/null || true; }
in_root() { chroot "$R" /usr/bin/env -i HOME=/root TERM=xterm-256color LANG=C.UTF-8 PATH=/usr/local/sbin:/usr/local/bin:/usr/bin "$@"; }
trap chroot_down EXIT

root_uuid=$(cat /proc/sys/kernel/random/uuid)
esp_id=$(od -An -N4 -tx4 /dev/urandom | tr -d ' ' | tr a-f A-F)
esp_uuid="${esp_id:0:4}-${esp_id:4:4}"

# 1. Base system, the patched kernel, Omarchy's prerequisites. The [omarchy]
#    repository needs its key in the target first; 20-install-omarchy.sh adds it.
# pacman's download sandbox (user alpm, Landlock) cannot be set up on the
# HongMeng kernel, and slow mirrors trip its 10 s low-speed timeout:
# DisableSandbox and DisableDownloadTimeout while building, removed from the
# result.
awk '/^\[omarchy\]/{skip=1; next} /^\[/{skip=0} !skip' "$here/etc/pacman.conf" |
  sed 's/^\[options\]$/[options]\nDisableSandbox\nDisableDownloadTimeout/' > "$W/pacman-base.conf"
mkdir -p "$R/var/lib/pacman" "$R/var/cache/pacman/pkg"
chroot_up
# packages are verified with the build environment's keyring
pacman --root "$R" --config "$W/pacman-base.conf" --cachedir "$W/../pkgcache" \
  -Sy --noconfirm base archlinuxarm-keyring sudo openssh networkmanager mkinitcpio grub efibootmgr git curl
chroot_up
in_root bash -c 'pacman-key --init && pacman-key --populate archlinuxarm' >/dev/null
cp "${pkgs[@]}" "$R/tmp/"
# mkinitcpio in a chroot would autodetect the build host's modules
sed -i 's/^HOOKS=(\(.*\)autodetect \(.*\))/HOOKS=(\1\2)/' "$R/etc/mkinitcpio.conf"
in_root bash -c 'pacman -U --noconfirm /tmp/*.pkg.tar.* && rm /tmp/*.pkg.tar.*'
install -m 644 "$here/etc/mirrorlist" "$R/etc/pacman.d/mirrorlist"

# 2. Identity, user, network, ssh
echo omarchy > "$R/etc/hostname"
cat > "$R/etc/fstab" <<FSTAB
UUID=$root_uuid  /          ext4  rw,relatime  0 1
UUID=$esp_uuid   /boot/efi  vfat  rw,relatime,umask=0077  0 2
FSTAB
mkdir -p "$R/boot/efi"
in_root bash -c "
  ln -sf /usr/share/zoneinfo/Asia/Shanghai /etc/localtime
  sed -i 's/^#\(en_US.UTF-8\|zh_CN.UTF-8\)/\1/' /etc/locale.gen && locale-gen >/dev/null
  echo LANG=en_US.UTF-8 > /etc/locale.conf
  id $user >/dev/null 2>&1 || useradd -m -G wheel $user
  echo '$user:$password' | chpasswd
  echo '%wheel ALL=(ALL:ALL) ALL' > /etc/sudoers.d/wheel
  systemctl enable NetworkManager sshd
"
install -D -m 600 "$here/etc/lan.nmconnection" "$R/etc/NetworkManager/system-connections/lan.nmconnection"

# 3. Omarchy, the same way as on the deepin-based VM. omarchy-settings adds
#    mkinitcpio.conf.d/omarchy_hooks.conf with btrfs-overlayfs (for btrfs
#    snapshots; this root is ext4 and has no such hook) and autodetect (which
#    in a chroot picks the build host's modules). conf.d is read in order, so a
#    later file overrides HOOKS.
install -D -m 644 /dev/stdin "$R/etc/mkinitcpio.conf.d/zz-hongrong.conf" <<'HOOKS'
# 鸿融 VM (ohmarchy hongrong/pure/build-disk.sh): ext4 root, no btrfs-overlayfs;
# no autodetect so the image does not depend on where it was generated.
HOOKS=(base udev plymouth keyboard microcode modconf kms keymap consolefont block encrypt filesystems fsck)
HOOKS
mkdir -p "$R/root/hongrong"; cp -r "$here/20-install-omarchy.sh" "$here/etc" "$R/root/hongrong/"
sed -i 's/^\[options\]$/[options]\nDisableSandbox\nDisableDownloadTimeout/' "$R/root/hongrong/etc/pacman.conf" "$R/etc/pacman.conf"
in_root bash /root/hongrong/20-install-omarchy.sh "$user"
rm -rf "$R/root/hongrong"
# omarchy-apply-system may regenerate the initramfs with autodetect again
sed -i 's/^HOOKS=(\(.*\)autodetect \(.*\))/HOOKS=(\1\2)/' "$R/etc/mkinitcpio.conf"
in_root mkinitcpio -P

# 4. GRUB: a standalone EFI image that finds the root by UUID
mkdir -p "$R/boot/grub" "$W/esp/EFI/BOOT"
cat > "$R/boot/grub/grub.cfg" <<GRUB
set timeout=3
menuentry "Omarchy (linux-aarch64, 鸿融 patches)" --id omarchy {
    search --no-floppy --fs-uuid --set=root $root_uuid
    linux /boot/Image root=UUID=$root_uuid $cmdline
    initrd /boot/initramfs-linux.img
}
menuentry "Omarchy (fallback initramfs)" --id omarchy-fallback {
    search --no-floppy --fs-uuid --set=root $root_uuid
    linux /boot/Image root=UUID=$root_uuid $cmdline
    initrd /boot/initramfs-linux-fallback.img
}
GRUB
cat > "$W/grub-early.cfg" <<EARLY
search --no-floppy --fs-uuid --set=root $root_uuid
set prefix=(\$root)/boot/grub
configfile /boot/grub/grub.cfg
EARLY
grub-mkstandalone -O arm64-efi -o "$W/esp/EFI/BOOT/BOOTAA64.EFI" \
  --modules="part_gpt ext2 fat search search_fs_uuid configfile linux normal" \
  "boot/grub/grub.cfg=$W/grub-early.cfg"

# 5. Filesystem images and the disk
chroot_down; trap - EXIT
rm -f "$R/etc/resolv.conf" "$R/etc/ld.so.preload"; rm -rf "$R/usr/local/lib/hmbuild"
sed -i '/^DisableSandbox$/d; /^DisableDownloadTimeout$/d' "$R/etc/pacman.conf"
rm -f "$W/esp.img" "$W/root.img" "$W/omarchy-pure.img"
root_mib=$(( disk_gib * 1024 - esp_mib - 2 ))
truncate -s ${esp_mib}M "$W/esp.img"
mkfs.fat -F 32 -i "$esp_id" -n ESP "$W/esp.img" >/dev/null
mcopy -s -i "$W/esp.img" "$W/esp/EFI" ::/
truncate -s ${root_mib}M "$W/root.img"
mkfs.ext4 -q -F -U "$root_uuid" -L omarchy -d "$R" "$W/root.img"
truncate -s ${disk_gib}G "$W/omarchy-pure.img"
sfdisk -q "$W/omarchy-pure.img" <<PT
label: gpt
start=1MiB, size=${esp_mib}MiB, type=uefi, name=ESP
start=$(( 1 + esp_mib ))MiB, size=${root_mib}MiB, type=linux, name=omarchy
PT
dd if="$W/esp.img" of="$W/omarchy-pure.img" bs=1M seek=1 conv=notrunc,sparse status=none
dd if="$W/root.img" of="$W/omarchy-pure.img" bs=1M seek=$(( 1 + esp_mib )) conv=notrunc,sparse status=none
rm -f "$W/esp.img" "$W/root.img"
sfdisk -l "$W/omarchy-pure.img"
echo "root UUID $root_uuid, ESP $esp_uuid"
echo BUILD_DISK_DONE
