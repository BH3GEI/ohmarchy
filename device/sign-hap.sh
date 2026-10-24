#!/usr/bin/env bash
# Sign the route-F patched Aetherium HAP with the device's debug profile (UDID from the device).
# usage: sign-hap.sh [IN.hap] [OUT.hap]   defaults: work/emulator/aetherium-patched.hap -> work/device/aetherium-signed.hap
set -euo pipefail
. "$(dirname "$0")/config.sh"
IN=${1:-$ROOT/work/emulator/aetherium-patched.hap}
OUT=${2:-$WORK/aetherium-signed.hap}
[ -f "$IN" ] || { echo "patched HAP not found: $IN (run emulator/20-fetch-inputs.sh first)" >&2; exit 1; }
UDID=$(to 40 ssh -tt -o ConnectTimeout=20 "$OHDEV" 'bm get --udid' 2>/dev/null | tr -d '\r' | grep -oE '[0-9A-F]{64}' | head -1)
[ -n "$UDID" ] || { echo "could not read device UDID" >&2; exit 1; }
BUNDLE="$BUNDLE" UDID="$UDID" bash "$ROOT/native/app/sign/sign.sh" "$IN" "$OUT"
echo "signed: $OUT  (UDID ${UDID:0:8}…, bundle $BUNDLE)"
