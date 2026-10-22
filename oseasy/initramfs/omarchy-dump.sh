#!/bin/sh
# omarchy-dump.sh STAGE: display/driver snapshot into /run/omarchy (kept after switch_root)
S="$1"; mkdir -p /run/omarchy
{
    echo "=== stage=$S $(uname -a)"; cat /proc/cmdline
    echo "=== modules"; cat /proc/modules
    echo "=== fb"; cat /proc/fb; ls -la /dev/dri /dev/fb* 2>&1
    echo "=== drm"; for f in /sys/class/drm/*/status; do [ -f "$f" ] && echo "$f $(cat "$f") $(head -1 "${f%status}modes" 2>/dev/null)"; done
    echo "=== net"; ip addr 2>&1
    echo "=== dmesg"; dmesg
} > "/run/omarchy/stage-$S.txt" 2>&1
