#!/bin/bash
# NOT YET TESTED end to end (2026-10-24): written, syntax-checked, first run pending.
# Build a disk image with Omarchy alone (no deepin) for the 鸿融 VM: GPT with an
# EFI system partition and an ext4 root, Arch Linux ARM's linux-aarch64 with the
# 鸿融 patches (hongrong/kernel/patches) installed as a package, and a
# standalone GRUB at the removable-media path so the VM's UEFI finds it without
# boot entries. Nothing is mounted except bind mounts for the chroot: the
# filesystems are made from directories (mkfs.ext4 -d, mtools) and placed at
# their partition offsets.
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

pacman -S --needed --noconfirm arch-install-scripts mtools dosfstools e2fsprogs grub >/dev/null
mkdir -p "$W" "$R"
mountpoint -q "$R" || mount --bind "$R" "$R"
trap 'umount -R "$R" 2>/dev/null || true' EXIT

root_uuid=$(cat /proc/sys/kernel/random/uuid)
esp_id=$(od -An -N4 -tx4 /dev/urandom | tr -d ' ' | tr a-f A-F)
esp_uuid="${esp_id:0:4}-${esp_id:4:4}"

# 1. Base system, the patched kernel, Omarchy's prerequisites. The [omarchy]
#    repository needs its key in the target first; 20-install-omarchy.sh adds it.
awk '/^\[omarchy\]/{skip=1; next} /^\[/{skip=0} !skip' "$here/etc/pacman.conf" > "$W/pacman-base.conf"
pacstrap -C "$W/pacman-base.conf" -K "$R" base archlinuxarm-keyring sudo openssh networkmanager mkinitcpio grub efibootmgr git curl
arch-chroot "$R" pacman-key --populate archlinuxarm >/dev/null
cp "${pkgs[@]}" "$R/tmp/"
# mkinitcpio in a chroot would autodetect the build host's modules
sed -i 's/^HOOKS=(\(.*\)autodetect \(.*\))/HOOKS=(\1\2)/' "$R/etc/mkinitcpio.conf"
arch-chroot "$R" bash -c 'pacman -U --noconfirm /tmp/*.pkg.tar.* && rm /tmp/*.pkg.tar.*'
install -m 644 "$here/etc/mirrorlist" "$R/etc/pacman.d/mirrorlist"

# 2. Identity, user, network, ssh
echo omarchy > "$R/etc/hostname"
cat > "$R/etc/fstab" <<FSTAB
UUID=$root_uuid  /          ext4  rw,relatime  0 1
UUID=$esp_uuid   /boot/efi  vfat  rw,relatime,umask=0077  0 2
FSTAB
mkdir -p "$R/boot/efi"
arch-chroot "$R" bash -c "
  ln -sf /usr/share/zoneinfo/Asia/Shanghai /etc/localtime
  sed -i 's/^#\(en_US.UTF-8\|zh_CN.UTF-8\)/\1/' /etc/locale.gen && locale-gen >/dev/null
  echo LANG=en_US.UTF-8 > /etc/locale.conf
  id $user >/dev/null 2>&1 || useradd -m -G wheel $user
  echo '$user:$password' | chpasswd
  echo '%wheel ALL=(ALL:ALL) ALL' > /etc/sudoers.d/wheel
  systemctl enable NetworkManager sshd
"
install -D -m 600 "$here/etc/lan.nmconnection" "$R/etc/NetworkManager/system-connections/lan.nmconnection"

# 3. Omarchy, the same way as on the deepin-based VM
mkdir -p "$R/root/hongrong"; cp -r "$here/20-install-omarchy.sh" "$here/etc" "$R/root/hongrong/"
arch-chroot "$R" bash /root/hongrong/20-install-omarchy.sh "$user"
rm -rf "$R/root/hongrong"
# omarchy-apply-system may regenerate the initramfs with autodetect again
sed -i 's/^HOOKS=(\(.*\)autodetect \(.*\))/HOOKS=(\1\2)/' "$R/etc/mkinitcpio.conf"
arch-chroot "$R" mkinitcpio -P

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
umount -R "$R"; trap - EXIT
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
