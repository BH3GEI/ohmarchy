#!/bin/bash
# Give 鸿融's virtio-gpu output the 120 Hz EDID, at every boot, before the
# display manager. The same images also run on route B's SVGA device, whose
# vmwgfx connector is also named Virtual-1: a drm.edid_firmware=Virtual-1:...
# on the kernel command line reached it too, and vmwgfx then oopsed in its
# HVM poll worker with a black screen. So the EDID is set here, through
# debugfs, only on a DRM device driven by virtio_gpu. Not run yet.
set -u
edid=/usr/lib/firmware/edid/omarchy-120.bin
[ -r "$edid" ] || exit 0
mountpoint -q /sys/kernel/debug || mount -t debugfs debugfs /sys/kernel/debug || exit 0
for d in /sys/kernel/debug/dri/*/; do
  grep -q '^virtio_gpu' "$d/name" 2>/dev/null || continue
  for c in "$d"Virtual-*/; do
    [ -e "$c/edid_override" ] || continue
    cat "$edid" > "$c/edid_override" && echo 1 > "$c/trigger_hotplug"
    echo "EDID $edid on ${c%/}"
  done
done
exit 0
