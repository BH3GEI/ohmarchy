#!/bin/sh
# Stream a zstd-compressed raw disk image to the Oseasy VM booted in the probe's install mode
# (it listens on 172.16.100.2:5003 and writes /dev/vda, then adds vmwgfx-oseasy).
# Run on the HarmonyOS host; the image is only read.
# Make the .zst without touching the image (zstd from the Arch environment):
#   cat disk.img | sh /data/local/archtest/arch.sh run zc.sh > disk.img.zst   (zc.sh: zstd -T4 -3 -c)
#   sh push-disk.sh /data/local/oseasy/omarchy-pure.img.zst
img=${1:?disk image}
ls -la "$img"
date
toybox nc -q 5 172.16.100.2 5003 < "$img"
date
