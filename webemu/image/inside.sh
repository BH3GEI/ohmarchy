#!/bin/sh
# Runs in the Alpine container started by build-image.sh. /w is webemu/image.
set -e
apk add --no-cache pacman arch-install-scripts e2fsprogs zstd bash >/dev/null

cat > /tmp/pacman.conf <<'EOF'
[options]
Architecture = i686
SigLevel = Never
CacheDir = /var/cache/pacman/pkg
ParallelDownloads = 4
[core]
Server = https://mirror.archlinux32.org/$arch/$repo
[extra]
Server = https://mirror.archlinux32.org/$arch/$repo
EOF

R=/rootfs
mkdir -p $R /var/cache/pacman/pkg
# base: systemd, pacman, coreutils, bash...; linux: Arch's own i686 kernel.
pacstrap -C /tmp/pacman.conf -M $R base linux archlinux32-keyring less which

# Guest pacman: the distro's normal config, one archlinux32 mirror
echo 'Server = https://mirror.archlinux32.org/$arch/$repo' > $R/etc/pacman.d/mirrorlist
# and its keyring (signature checks stay on).
arch-chroot $R sh -c 'pacman-key --init && pacman-key --populate archlinux32' >/dev/null
# Sync databases are part of the image, so pacman -Ss/-Si work offline in the guest.
arch-chroot $R pacman -Sy || true

# Initramfs without autodetect (it would pick the build host's modules) and only
# the drivers v86 offers: PIIX IDE disk, virtio, ne2k, 9p.
cat > $R/etc/mkinitcpio.conf <<'EOF'
MODULES=(ata_piix ata_generic sd_mod ext4 virtio_pci virtio_net virtio_console ne2k-pci 9p 9pnet_virtio)
BINARIES=()
FILES=()
HOOKS=(base)
COMPRESSION="gzip"
EOF
cat > $R/etc/mkinitcpio.d/linux.preset <<'EOF'
ALL_kver="/boot/vmlinuz-linux"
PRESETS=('default')
default_image="/boot/initramfs-linux.img"
EOF
rm -f $R/boot/initramfs-linux*.img
arch-chroot $R mkinitcpio -p linux

# System setup.
echo ohmarchy-l > $R/etc/hostname
echo 'LANG=C.UTF-8' > $R/etc/locale.conf
ln -sf /usr/share/zoneinfo/UTC $R/etc/localtime
echo '/dev/sda / ext4 rw,noatime 0 0' > $R/etc/fstab
# Root logs in on the serial console without a password prompt (there is no password).
d=$R/etc/systemd/system/serial-getty@ttyS0.service.d
mkdir -p $d
cat > $d/autologin.conf <<'EOF'
[Service]
ExecStart=
ExecStart=-/sbin/agetty -o '-p -f -- \\u' --noclear --autologin root --keep-baud 115200,57600,38400,9600 - $TERM
EOF
# Units that only cost boot time in a browser VM.
for u in systemd-timesyncd.service systemd-networkd-wait-online.service \
         systemd-homed.service systemd-userdbd.socket ldconfig.service man-db.timer \
         shadow.timer archlinux-keyring-wkd-sync.timer; do
  ln -sf /dev/null $R/etc/systemd/system/$u
done
cat > $R/root/.bash_profile <<'EOF'
[ -f ~/.bashrc ] && . ~/.bashrc
echo "route L: Arch Linux 32 in v86 inside ArkWeb. Try: routel-bench, pacman -Q | wc -l"
EOF
install -m 755 /w/routel-bench $R/usr/local/bin/routel-bench

# Keep the image small: docs, man pages and package cache are not needed.
rm -rf $R/var/cache/pacman/pkg/* $R/usr/share/man/* $R/usr/share/doc/* $R/usr/share/info/*

cp $R/boot/vmlinuz-linux /w/out/vmlinuz
cp $R/boot/initramfs-linux.img /w/out/initramfs.img
chmod 644 /w/out/*
used=$(du -sm $R | cut -f1); echo "rootfs ${used} MiB"
rm -f /w/out/arch32.img
mke2fs -q -t ext4 -O ^has_journal,^metadata_csum -L arch32 -d $R /w/out/arch32.img "${IMG_MB:-$((used * 13 / 10 + 256))}M"
