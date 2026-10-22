#!/usr/bin/env bash
# Copy the installer ISO into the Fold's Download folder over hdc.
set -euo pipefail
. "$(dirname "$0")/config.sh"
need "$HDC"
T=${HDC_TARGET:-$("$HDC" list targets | head -1)}
[ -n "$T" ] && [ "$T" != "[Empty]" ] || die "no hdc target (connect the Fold, enable USB debugging)"
DST=/storage/media/100/local/files/Docs/Download/omarchy-install.iso
SZ=$(stat -c %s "$WORK/omarchy-install.iso")
"$HDC" -t "$T" file send "$WORK/omarchy-install.iso" "$DST"
[ "$("$HDC" -t "$T" shell "stat -c %s $DST" | tr -d '\r\n ')" = "$SZ" ] && echo "pushed ($SZ bytes) to $DST"
