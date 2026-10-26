#!/bin/bash
# Grow the root partition and its ext4 to the end of the disk, once. The
# images are packed small (repack-disk.sh) so that compressing them does not
# grind through tens of GiB of zeros; whoever writes one to a bigger disk
# (route B's installer with dd, 鸿融 with a 256 GiB qcow2) gets the space back
# at the first boot. Online: the root stays mounted. Not run yet.
set -euo pipefail
root=$(findmnt -no SOURCE /)
disk=/dev/$(lsblk -no PKNAME "$root")
part=$(cat "/sys/class/block/${root#/dev/}/partition")
# the backup GPT sits at the end of the image, not of the disk
sfdisk --force --no-reread --relocate gpt-bak-std "$disk"
echo ', +' | sfdisk --force --no-reread -N "$part" "$disk"
partx -u "$disk"
resize2fs "$root"
mkdir -p /var/lib/ohmarchy; touch /var/lib/ohmarchy/growroot.done
