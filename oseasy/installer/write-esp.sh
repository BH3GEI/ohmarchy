#!/bin/sh
# Refresh only the EFI system partition (keeps Omarchy's root and your data):
#   sh /cdrom/write-esp.sh
set -e
gunzip -c /cdrom/esp.img.gz | dd of=${1:-/dev/vda1} bs=4M 2>&1 | tail -2
sync; echo "ESP rewritten"
