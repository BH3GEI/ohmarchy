#!/bin/bash
# Run with sudo in the guest: make the virtio-gpu display report a 120 Hz mode
# by overriding its EDID (the 鸿融 host advertises only 60 Hz modes).
# Usage: install-edid.sh [EDID.bin] [CONNECTOR]   (default omarchy-120.bin, Virtual-1)
# Undo: rm /etc/mkinitcpio.conf.d/zz-edid.conf, drop drm.edid_firmware from
# /boot/grub/grub.cfg, mkinitcpio -P.
set -euo pipefail
bin=${1:-$(dirname "$0")/omarchy-120.bin}; con=${2:-Virtual-1}
name=$(basename "$bin")
install -D -m 644 "$bin" "/usr/lib/firmware/edid/$name"
echo "FILES+=(/usr/lib/firmware/edid/$name)" > /etc/mkinitcpio.conf.d/zz-edid.conf
mkinitcpio -P >/dev/null
cfg=/boot/grub/grub.cfg
grep -q "drm.edid_firmware=" "$cfg" ||
  sed -i "s#\(linux /boot/Image .*\)#\1 drm.edid_firmware=$con:edid/$name#" "$cfg"
grep -n "drm.edid_firmware" "$cfg"
echo "reboot to use it; then check /sys/class/drm/card*-$con/modes"
