#!/usr/bin/env bash
# Install the signed Aetherium HAP on the device as root (does not launch it).
set -euo pipefail
. "$(dirname "$0")/config.sh"
"$(dirname "$0")/ohsh" - <<SH
bm install -p $DEV_DIR/aetherium-signed.hap && echo installed || bm install -r -p $DEV_DIR/aetherium-signed.hap
bm dump -n $BUNDLE | grep -m1 versionName || true
SH
