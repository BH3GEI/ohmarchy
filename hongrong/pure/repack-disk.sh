#!/bin/bash
# Pack build-disk.sh's file tree into a small disk image and compress it, for
# images that are written to a bigger disk later (route B's installer) and
# grown at their first boot (firstboot/ohmarchy-growroot.service, installed
# here). Reuses the root and ESP UUIDs from the tree's fstab, so grub.cfg and
# fstab stay valid. Compressing a 64 GiB image with zstd -22 spent most of an
# hour on the zeros at its end; a disk sized to the data avoids that.
# Runs where build-disk.sh ran. Not run yet.
# Usage: repack-disk.sh WORKDIR [DISK_GIB, default 12]
# Environment: EXTRA_CMDLINE, appended to the kernel command line in
# boot/grub/grub.cfg (once), e.g. vmwgfx.hvm_flip_watchdog_us=0 until
# vmwgfx-oseasy stops walking the CRTCs before vmw_kms_init().
#   WORKDIR as given to build-disk.sh (has root/ and esp/); writes
#   omarchy-small.img and omarchy-small.img.zst there
set -euo pipefail
W=${1:?workdir}; gib=${2:-12}; R=$W/root
here=$(cd "$(dirname "$0")" && pwd)
esp_mib=512

root_uuid=$(awk '$2 == "/" { sub("UUID=", "", $1); print $1 }' "$R/etc/fstab")
esp_uuid=$(awk '$2 == "/boot/efi" { sub("UUID=", "", $1); print $1 }' "$R/etc/fstab")
[ -n "$root_uuid" ] && [ -n "$esp_uuid" ] || { echo "no / or /boot/efi UUID in $R/etc/fstab"; exit 1; }
used=$(du -sxm "$R" | cut -f1)
root_mib=$(( gib * 1024 - esp_mib - 2 ))
[ $(( used * 5 / 4 )) -lt $root_mib ] || { echo "$used MiB of files do not fit ${gib} GiB"; exit 1; }

install -D -m 644 "$here/firstboot/ohmarchy-growroot.service" "$R/etc/systemd/system/ohmarchy-growroot.service"
install -D -m 755 "$here/firstboot/ohmarchy-growroot.sh" "$R/usr/local/lib/ohmarchy/ohmarchy-growroot.sh"
mkdir -p "$R/etc/systemd/system/multi-user.target.wants"
ln -sf ../ohmarchy-growroot.service "$R/etc/systemd/system/multi-user.target.wants/ohmarchy-growroot.service"
rm -f "$R/var/lib/ohmarchy/growroot.done"
# the EDID goes to virtio-gpu only, at boot (firstboot/ohmarchy-edid.sh), not
# on the command line, where it also reached route B's vmwgfx
sed -i 's| drm.edid_firmware=[^ ]*||' "$R/boot/grub/grub.cfg"
rm -f "$R/etc/mkinitcpio.conf.d/zz-edid.conf"
install -D -m 644 "$here/firstboot/ohmarchy-edid.service" "$R/etc/systemd/system/ohmarchy-edid.service"
install -D -m 755 "$here/firstboot/ohmarchy-edid.sh" "$R/usr/local/lib/ohmarchy/ohmarchy-edid.sh"
ln -sf ../ohmarchy-edid.service "$R/etc/systemd/system/multi-user.target.wants/ohmarchy-edid.service"
for a in ${EXTRA_CMDLINE:-}; do
  grep -q " ${a%%=*}=" "$R/boot/grub/grub.cfg" || sed -i "/^ *linux /s|\$| $a|" "$R/boot/grub/grub.cfg"
done
grep -n 'linux ' "$R/boot/grub/grub.cfg"

rm -f "$W/esp-small.img" "$W/root-small.img" "$W/omarchy-small.img"
truncate -s ${esp_mib}M "$W/esp-small.img"
mkfs.fat -F 32 -i "${esp_uuid/-/}" -n ESP "$W/esp-small.img" >/dev/null
mcopy -s -i "$W/esp-small.img" "$W/esp/EFI" ::/
truncate -s ${root_mib}M "$W/root-small.img"
mkfs.ext4 -q -F -U "$root_uuid" -L omarchy -d "$R" "$W/root-small.img"
truncate -s ${gib}G "$W/omarchy-small.img"
sfdisk -q "$W/omarchy-small.img" <<PT
label: gpt
start=1MiB, size=${esp_mib}MiB, type=uefi, name=ESP
start=$(( 1 + esp_mib ))MiB, size=${root_mib}MiB, type=linux, name=omarchy
PT
dd if="$W/esp-small.img" of="$W/omarchy-small.img" bs=1M seek=1 conv=notrunc,sparse status=none
dd if="$W/root-small.img" of="$W/omarchy-small.img" bs=1M seek=$(( 1 + esp_mib )) conv=notrunc,sparse status=none
rm -f "$W/esp-small.img" "$W/root-small.img"
sfdisk -l "$W/omarchy-small.img"
zstd -q -T0 --ultra -22 --long=31 -f "$W/omarchy-small.img" -o "$W/omarchy-small.img.zst"
ls -l "$W/omarchy-small.img.zst"
echo REPACK_DONE
