#!/bin/bash
# Ran end to end on 2026-10-24; the disk booted in a 鸿融-style VM (cold + 3 warm reboots).
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
#        BASE=1 build-disk.sh WORKDIR - - KERNEL_PKG...
#   WORKDIR gets root/, esp.img, root.img and the result omarchy-pure.img
# BASE=1 builds the release base image instead: Arch Linux ARM, the kernel,
# EDID and network, no Omarchy and no user. Its first boot
# (firstboot/ohmarchy-firstboot.sh, on tty1) asks for the password of the user
# "omarchy" and installs Omarchy from the network; the image stays under 2 GiB
# for a GitHub release asset. ROOT_IMG=1 also writes omarchy-root.img, the
# same tree as a bare ext4 filesystem of minimal size without / and /boot/efi
# in fstab, for route B (OSEasy loop-mounts it from the shared folder).
# NOPASS=1 (with the full install, not BASE): the user gets no password; at
# the first boot SDDM logs it in once and a terminal on the desktop asks for
# one (firstboot/ohmarchy-setpass-root.sh). KEEP_AUTOLOGIN (default 1 with
# NOPASS, route B's choice for its trial image): SDDM keeps logging the user
# in after that and the password is for sudo; 0 goes back to the SDDM prompt. With
# the docs, man pages and pacman cache left out this is the image route B
# ships. The user name is still the USER argument (omarchy for releases).
# TRIM_PKGS: packages removed after the Omarchy install (pacman -Rns, leaf
# apps only) to fit a size limit; SLIM=1 also keeps only the zh_CN and en
# locales (with NoExtract in pacman.conf so updates do not bring the rest
# back) and drops the user's mise caches and nvim plugins (downloaded again
# on first use).
# AI_ENV (demo machine only, never for a public image): env file for
# guest/setup-ai.sh, copied into the base image for its first boot.
# VMWGFX_KO: route B's patched vmwgfx.ko for this kernel (driver/
# vmwgfx-oseasy-7.2), installed under updates/ with oseasy/vmwgfx-7.2's options.
# Environment: DISK_GIB, ESP_MIB, CMDLINE; EDID (default hongrong/edid/
# omarchy-120.bin, empty for none): an EDID with a 2160x1440@120 mode for the
# virtio-gpu output, loaded with drm.edid_firmware (see hongrong/edid);
# EXTRA_PKGS (default "mesa-utils glmark2", the GPU checks in guest/gfx.sh);
# VM_TOOLS: 鸿融's entry.hap (or its vm_tools_*.iso, or the vm-agent .deb)
# copied into the build environment, for its guest agent (install-vm-agent.sh);
# empty: no agent, and 鸿融 then shows the running VM as 已关机.
# The EDID and EXTRA_PKGS steps were added 2026-10-25 and VM_TOOLS on
# 2026-10-25; none has been run in a full build yet. The EDID and packages
# done by hand in a running VM worked; the agent has not been tried at all.
set -euo pipefail

W=${1:?workdir}; user=${2:?user}; password=${3:?password}; shift 3
trim_pkgs=${TRIM_PKGS:-} slim=${SLIM:-0} keep_autologin=${KEEP_AUTOLOGIN:-1}
base=${BASE:-0} nopass=${NOPASS:-0} root_img=${ROOT_IMG:-0} ai_env=${AI_ENV:-} vmwgfx_ko=${VMWGFX_KO:-}
pkgs=("$@"); [ ${#pkgs[@]} -gt 0 ] || { echo "no kernel packages given"; exit 1; }
here=$(cd "$(dirname "$0")/.." && pwd)        # hongrong/
disk_gib=${DISK_GIB:-64} esp_mib=${ESP_MIB:-512}
cmdline=${CMDLINE:-"rw arm64.hmv_idreg_quirk console=tty0 console=ttyAMA0,115200"}
edid=${EDID-$here/edid/omarchy-120.bin}
extra_pkgs=${EXTRA_PKGS-mesa-utils glmark2}
vm_tools=${VM_TOOLS:-}
# the EDID is set at boot for virtio-gpu only (firstboot/ohmarchy-edid.sh): on
# the command line it also reached route B's vmwgfx connector (also Virtual-1)
R=$W/root

pacman -S --needed --noconfirm mtools dosfstools e2fsprogs grub libarchive >/dev/null
mkdir -p "$W" "$R"
chroot_up() {
  # / must be a mount point in the chroot, or pacman cannot check free space
  mountpoint -q "$R" || mount --bind "$R" "$R"
  mkdir -p "$R"/{proc,sys,dev,run,tmp,etc}
  mountpoint -q "$R/proc" || mount -t proc proc "$R/proc"
  # /sys is a tmpfs with only the VM's DMI identity and no devices: Omarchy's install steps
  # probe hardware there (under bash -e, a missing /sys/class/dmi aborts them),
  # and they should see the 鸿融 VM, not the machine building the image.
  if ! mountpoint -q "$R/sys"; then
    mount -t tmpfs sys "$R/sys"
    # an empty PCI bus: lspci (used by the hardware steps) needs one to exist
    mkdir -p "$R/sys/class/dmi/id" "$R/sys/bus/pci/devices" "$R/sys/bus/pci/slots"
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
  systemctl enable NetworkManager sshd
"
# the base image gets its user (and password) at first boot
if [ "$base" != 1 ]; then
  in_root bash -c "id $user >/dev/null 2>&1 || useradd -m -G wheel $user
    echo '%wheel ALL=(ALL:ALL) ALL' > /etc/sudoers.d/wheel"
  if [ "$nopass" = 1 ]; then in_root passwd -l "$user"
  else in_root bash -c "echo '$user:$password' | chpasswd"; fi
fi
install -D -m 600 "$here/etc/lan.nmconnection" "$R/etc/NetworkManager/system-connections/lan.nmconnection"

# 3. Omarchy, the same way as on the deepin-based VM. omarchy-settings adds
#    mkinitcpio.conf.d/omarchy_hooks.conf with btrfs-overlayfs (for btrfs
#    snapshots; this root is ext4 and has no such hook) and autodetect (which
#    in a chroot picks the build host's modules). conf.d is read in order, so a
#    later file overrides HOOKS.
L=$R/usr/local/lib/ohmarchy
mkdir -p "$L"
install -D -m 644 /dev/stdin "$L/zz-hongrong.conf" <<'HOOKS'
# 鸿融 VM (ohmarchy hongrong/pure/build-disk.sh): ext4 root, no btrfs-overlayfs, no LUKS;
# no autodetect so the image does not depend on where it was generated.
# No kms and plymouth either: with them route B's vmwgfx loaded from the
# initramfs and its HVM poll raced vmw_kms_init(); virtio-gpu (鸿融) still
# comes in early through the virtio modules.
HOOKS=(base udev keyboard microcode modconf keymap consolefont block filesystems fsck)
HOOKS
firstboot_files() {
  mkdir -p "$L"
  cp -r "$here/20-install-omarchy.sh" "$here/etc" "$here/pure/install-vm-agent.sh" \
    "$here/pure/guest/setup-ai.sh" "$here/pure/firstboot/ohmarchy-firstboot.sh" "$L/"
  install -m 644 "$here/pure/firstboot/ohmarchy-firstboot.service" "$R/etc/systemd/system/"
  in_root systemctl enable ohmarchy-firstboot.service
  [ -z "$ai_env" ] || install -m 600 "$ai_env" "$L/ai.env"
  # documentation is the bulk of what is not needed to run
  rm -rf "$R"/usr/share/{doc,man,info,gtk-doc}
}
if [ "$base" = 1 ]; then
  # first boot does step 3 (plymouth, named in the hooks above, comes with
  # Omarchy, so the hooks file goes in place only then)
  firstboot_files
else
  install -m 644 "$L/zz-hongrong.conf" "$R/etc/mkinitcpio.conf.d/zz-hongrong.conf"; rm -rf "$L"
  mkdir -p "$R/root/hongrong"; cp -r "$here/20-install-omarchy.sh" "$here/etc" "$R/root/hongrong/"
  sed -i 's/^\[options\]$/[options]\nDisableSandbox\nDisableDownloadTimeout/' "$R/root/hongrong/etc/pacman.conf" "$R/etc/pacman.conf"
  in_root bash /root/hongrong/20-install-omarchy.sh "$user"
  rm -rf "$R/root/hongrong"
  [ -z "$extra_pkgs" ] || in_root pacman -S --needed --noconfirm $extra_pkgs
  for p in $trim_pkgs; do
    in_root pacman -Q "$p" >/dev/null 2>&1 || continue
    in_root pacman -Rns --noconfirm "$p" || echo "WARNING: could not remove $p (something depends on it)"
  done
  if [ "$slim" = 1 ]; then
    find "$R/usr/share/locale" -mindepth 1 -maxdepth 1 -type d ! -name 'zh_CN' ! -name 'en' ! -name 'en_US' -exec rm -rf {} +
    sed -i '/^\[options\]$/a NoExtract = usr/share/locale/* !usr/share/locale/zh_CN/* !usr/share/locale/en/* !usr/share/locale/en_US/* !usr/share/locale/locale.alias' "$R/etc/pacman.conf"
    rm -rf "$R/home/$user/.cache/mise" "$R/home/$user/.local/share/mise" "$R/home/$user/.local/share/nvim"
  fi
  if [ -n "$vm_tools" ]; then "$here/pure/install-vm-agent.sh" "$R" "$vm_tools"
  else echo "VM_TOOLS not set: no 鸿融 guest agent in the image"; fi
  if [ "$nopass" = 1 ]; then
    # Omarchy is in place. First boot: SDDM logs the user in once without a
    # password and a terminal on the desktop asks for one (route B's vmwgfx
    # hides the text console, so tty1 cannot be used); see
    # firstboot/ohmarchy-setpass-root.sh. The coding agents get the relay
    # config now and install on first use.
    mkdir -p "$L" "$R/var/lib/ohmarchy"
    # a reused tree may still have the tty1 first-boot service of earlier builds
    in_root systemctl disable ohmarchy-firstboot.service 2>/dev/null || true
    rm -rf "$R/etc/systemd/system/ohmarchy-firstboot.service" "$L"/{ohmarchy-firstboot.sh,20-install-omarchy.sh,etc}
    cp "$here/pure/install-vm-agent.sh" "$here/pure/guest/setup-ai.sh" "$L/"
    install -m 755 "$here/pure/firstboot/ohmarchy-setpass-root.sh" "$L/"
    [ -z "$ai_env" ] || install -m 600 "$ai_env" "$L/ai.env"
    touch "$R/var/lib/ohmarchy/omarchy-installed" "$R/var/lib/ohmarchy/setpass-pending"
    if [ "$keep_autologin" = 1 ]; then touch "$R/var/lib/ohmarchy/keep-autologin"
    else rm -f "$R/var/lib/ohmarchy/keep-autologin"; fi
    # login: tty1 autologin and Omarchy's uwsm session from the login shell, as
    # route B's bare image does (SDDM's Hyprland greeter left vmwgfx black).
    # With keep-autologin it stays; otherwise ohmarchy-setpass-root.sh goes back
    # to SDDM.
    rm -f "$R/etc/sddm.conf.d/zz-ohmarchy-firstboot.conf"
    in_root systemctl disable sddm.service
    install -D -m 644 /dev/stdin "$R/etc/systemd/system/getty@tty1.service.d/ohmarchy-autologin.conf" <<GETTY
[Service]
ExecStart=
ExecStart=-/usr/bin/agetty -o '-p -f -- \\\\u' --noclear --autologin $user %I \$TERM
GETTY
    p=$R/home/$user/.bash_profile
    touch "$p"
    grep -q ohmarchy-tty1-session "$p" || cat >> "$p" <<'PROFILE'
# ohmarchy-tty1-session: start Omarchy's Hyprland session on tty1
if [ -z "${WAYLAND_DISPLAY:-}" ] && [ "$(tty)" = /dev/tty1 ]; then
    exec uwsm start -g -1 -e -D Hyprland hyprland.desktop > /tmp/uwsm.log 2>&1
fi
PROFILE
    in_root chown "$user:$user" "/home/$user/.bash_profile"
    install -D -m 440 /dev/stdin "$R/etc/sudoers.d/ohmarchy-setpass" <<SUDO
$user ALL=(root) NOPASSWD: /usr/local/lib/ohmarchy/ohmarchy-setpass-root.sh
SUDO
    in_root visudo -cf /etc/sudoers.d/ohmarchy-setpass
    u=$R/home/$user/.config/systemd/user
    install -D -m 644 "$here/pure/firstboot/ohmarchy-setpass.service" "$u/ohmarchy-setpass.service"
    mkdir -p "$u/graphical-session.target.wants"
    ln -sf ../ohmarchy-setpass.service "$u/graphical-session.target.wants/ohmarchy-setpass.service"
    in_root chown -R "$user:$user" "/home/$user/.config"
    in_root runuser -u "$user" -- bash /usr/local/lib/ohmarchy/setup-ai.sh ${ai_env:+/usr/local/lib/ohmarchy/ai.env}
    rm -f "$L/ai.env"
    rm -rf "$R"/usr/share/{doc,man,info,gtk-doc}
  fi
fi
kver=$(ls "$R/usr/lib/modules" | grep -v '^\.' | head -1)
if [ -n "$vmwgfx_ko" ]; then
  install -D -m 644 "$vmwgfx_ko" "$R/usr/lib/modules/$kver/updates/vmwgfx.ko"
  install -D -m 644 "$here/../oseasy/vmwgfx-7.2/vmwgfx-oseasy.conf" "$R/etc/modprobe.d/vmwgfx-oseasy.conf"
  in_root depmod "$kver"
fi
# virtio-gpu loads from the initramfs (kms hook), so the EDID goes in there too
if [ -n "$edid" ]; then
  install -D -m 644 "$edid" "$R/usr/lib/firmware/edid/omarchy-120.bin"
  rm -f "$R/etc/mkinitcpio.conf.d/zz-edid.conf"
  install -D -m 644 "$here/pure/firstboot/ohmarchy-edid.service" "$R/etc/systemd/system/ohmarchy-edid.service"
  install -D -m 755 "$here/pure/firstboot/ohmarchy-edid.sh" "$R/usr/local/lib/ohmarchy/ohmarchy-edid.sh"
  in_root systemctl enable ohmarchy-edid.service
fi
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
if [ "$root_img" = 1 ]; then
  # minimal size: the files plus a quarter for ext4 metadata and slack; route
  # B grows the file (truncate + resize2fs) before it mounts it
  used=$(du -sxm "$R" | cut -f1); size=$(( used * 5 / 4 + 128 ))
  cp "$R/etc/fstab" "$W/fstab.disk"
  printf '%s\n' "# / and /boot/efi: mounted by route B's probe (loop on the shared folder)" > "$R/etc/fstab"
  rm -f "$W/omarchy-root.img"; truncate -s ${size}M "$W/omarchy-root.img"
  mkfs.ext4 -q -F -m 1 -L omarchy -d "$R" "$W/omarchy-root.img"
  cp "$W/fstab.disk" "$R/etc/fstab"; rm -f "$W/fstab.disk"
  ls -l "$W/omarchy-root.img"
  [ $size -lt 2048 ] || echo "WARNING: omarchy-root.img is ${size} MiB, over 2 GiB"
fi
sfdisk -l "$W/omarchy-pure.img"
echo "root UUID $root_uuid, ESP $esp_uuid"
echo BUILD_DISK_DONE
