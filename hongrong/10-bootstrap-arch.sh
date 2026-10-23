#!/bin/bash
# Run as root in the deepin 25 guest of 鸿融. Puts Arch Linux ARM into /arch on
# deepin's data partition and makes it bootable with deepin's kernel as the
# default GRUB entry. Usage: 10-bootstrap-arch.sh USER PASSWORD
set -euo pipefail

user=${1:?user}; password=${2:?password}
here=$(cd "$(dirname "$0")" && pwd)
R=${ARCH_ROOT:-/persistent/arch}
kver=$(uname -r)
alarm=https://mirrors.tuna.tsinghua.edu.cn/archlinuxarm/os/ArchLinuxARM-aarch64-latest.tar.gz

apt-get install -y libarchive-tools >/dev/null

# 1. Arch Linux ARM root filesystem
if [[ ! -x $R/usr/bin/pacman ]]; then
  curl -fL -o /tmp/alarm.tar.gz "$alarm"
  curl -fsL "$alarm.md5" | sed 's|  .*|  /tmp/alarm.tar.gz|' | md5sum -c -
  mkdir -p "$R"
  bsdtar -xpf /tmp/alarm.tar.gz -C "$R"
fi
install -m 755 "$here/archroot.sh" /usr/local/bin/archroot
install -m 644 "$here/etc/mirrorlist" "$R/etc/pacman.d/mirrorlist"
ARCH_ROOT=$R archroot "pacman-key --init && pacman-key --populate archlinuxarm && pacman -Syu --noconfirm && pacman -S --noconfirm --needed sudo openssh git base-devel grub"

# 2. deepin's kernel modules and an Arch initramfs that mounts /arch as /
rm -rf "$R/usr/lib/modules/$kver"
cp -a "/usr/lib/modules/$kver" "$R/usr/lib/modules/"
install -m 644 "$here/initcpio/subroot.install" "$R/etc/initcpio/install/subroot"
install -m 644 "$here/initcpio/subroot.hook" "$R/etc/initcpio/hooks/subroot"
install -m 644 "$here/initcpio/subroot.conf" "$R/etc/mkinitcpio.conf.d/subroot.conf"
ARCH_ROOT=$R archroot "mkinitcpio -k $kver -g /boot/initramfs-deepinkernel.img"
cp "$R/boot/initramfs-deepinkernel.img" /boot/initramfs-deepinkernel.img

# 3. Base system: user, sudo, sshd, network, locale
install -d -m 700 "$R/etc/NetworkManager/system-connections"
install -m 600 "$here/etc/lan.nmconnection" "$R/etc/NetworkManager/system-connections/lan.nmconnection"
ARCH_ROOT=$R archroot "
set -e
userdel -r alarm 2>/dev/null || true
id $user >/dev/null 2>&1 || useradd -m -G wheel -s /bin/bash $user
echo '$user:$password' | chpasswd
echo '%wheel ALL=(ALL:ALL) ALL' > /etc/sudoers.d/10-wheel; chmod 440 /etc/sudoers.d/10-wheel
echo omarchy > /etc/hostname
ln -sf /usr/share/zoneinfo/Asia/Shanghai /etc/localtime
sed -i 's/^#en_US.UTF-8/en_US.UTF-8/; s/^#zh_CN.UTF-8/zh_CN.UTF-8/' /etc/locale.gen; locale-gen
echo LANG=en_US.UTF-8 > /etc/locale.conf
systemctl enable sshd
"
if [[ -f /home/$user/.ssh/authorized_keys ]]; then
  install -d -m 700 "$R/home/$user/.ssh"
  install -m 600 "/home/$user/.ssh/authorized_keys" "$R/home/$user/.ssh/authorized_keys"
  ARCH_ROOT=$R archroot "chown -R $user:$user /home/$user/.ssh"
fi
cp -a "$here/../hongrong" "$R/home/$user/hongrong"
ARCH_ROOT=$R archroot "chown -R $user:$user /home/$user/hongrong"

# 4. GRUB entry; deepin's grub.cfg sources custom.cfg
boot_uuid=$(blkid -s UUID -o value "$(findmnt -no SOURCE /boot)")
data_uuid=$(blkid -s UUID -o value "$(df --output=source "$R" | tail -1)")
sed -e "s/@BOOT_UUID@/$boot_uuid/" -e "s/@DATA_UUID@/$data_uuid/" -e "s/@KVER@/$kver/" \
  "$here/grub-custom.cfg.in" > /boot/grub/custom.cfg

# Unmount the chroot top-down before rebooting.
while m=$(grep " $R" /proc/mounts | awk '{print $2}' | tail -1); [[ -n $m ]]; do umount -l "$m"; done
echo "Done. Reboot to start Arch, then run 20-install-omarchy.sh there as root."
