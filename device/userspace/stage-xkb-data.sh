#!/usr/bin/env bash
# Stage xkeyboard-config data for the in-app Hyprland. xkbcommon compiles a keymap at startup
# from this data; without it Hyprland fails to init the keyboard. Bundle the tarball into the
# HAP (rawfile/resfile), extract to /data/storage/el2/base/files/xkb at app start; bbload.cpp
# sets XKB_CONFIG_ROOT there. Slimmed to evdev rules + the core dirs (no geometry).
set -euo pipefail
SP="${SP:?}"; X="$SP/stage3/csrc/xkb-ex"; OUT="$SP/stage3/hap-data"; rm -rf "$OUT"; mkdir -p "$OUT/xkb"
for d in rules keycodes types compat symbols; do cp -R "$X/$d" "$OUT/xkb/"; done
find "$OUT/xkb/rules" -type f ! -name 'evdev*' -delete
( cd "$OUT" && tar czf "$SP/stage3/xkb-data.tar.gz" xkb )
echo "xkb-data.tar.gz: $(ls -lh "$SP/stage3/xkb-data.tar.gz" | awk '{print $5}') (extracts to files/xkb)"
