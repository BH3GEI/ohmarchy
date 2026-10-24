#!/bin/sh
# Stream a raw disk image to the Oseasy VM booted in the probe's install mode
# (it listens on 172.16.100.2:5003 and writes /dev/vda, then adds vmwgfx-oseasy).
# Run on the HarmonyOS host; the image is only read.
#   sh push-disk.sh /data/local/vmtest/omarchy-pure.img
img=${1:?disk image}
ls -la "$img"
start=$(date +%s)
toybox nc -q 5 172.16.100.2 5003 < "$img"
echo "pushed in $(( $(date +%s) - start )) s"
