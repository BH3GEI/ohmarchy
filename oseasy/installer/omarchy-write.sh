#!/bin/sh
# Run from the Debian installer's rescue shell: sh /cdrom/omarchy-write.sh
set -e
DISK=${1:-/dev/vda}
SRC=/cdrom/omarchy.raw.gz
[ -f "$SRC" ] || { echo "image not found at $SRC (is the install media mounted at /cdrom?)"; exit 1; }
echo "=== writing Omarchy image to $DISK (this takes a few minutes) ==="
gunzip -c "$SRC" | dd of="$DISK" bs=4M 2>&1 | tail -2
sync
echo "=== done. partitions: ==="; grep -E 'vda' /proc/partitions
echo "Then: sync; reboot -f   (the VM boots the disk before the installer media)"
