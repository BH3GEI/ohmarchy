#!/usr/bin/env bash
# gzip the signed HAP and the Omarchy qcow2 to the device, one transfer at a time, sha256-verified.
# Only one big transfer may run on ohdev at a time; the 3.4 GB disk is announced to the supervisor.
set -euo pipefail
. "$(dirname "$0")/config.sh"
HAP=${1:-$WORK/aetherium-signed.hap}
QCOW=${2:-$ROOT/work/emulator/omarchy-aarch64-virt.qcow2}
send() {  # send LOCAL REMOTE
    local l=$1 r=$2
    echo "sending $(basename "$l") ($(du -h "$l" | cut -f1)) -> $r"
    gzip -1 -c "$l" | to 3600 ssh -o ConnectTimeout=20 "$OHDEV" "mkdir -p $(dirname "$r"); gunzip > $r"
    local want have
    want=$(shasum -a 256 "$l" | cut -d' ' -f1)
    have=$(to 120 ssh -tt -o ConnectTimeout=20 "$OHDEV" "sha256sum $r" 2>/dev/null | tr -d '\r' | grep -oE '^[0-9a-f]{64}')
    [ "$want" = "$have" ] || { echo "sha256 mismatch for $r" >&2; return 1; }
    echo "ok $r"
}
send "$HAP" "$DEV_DIR/aetherium-signed.hap"
send "$QCOW" "$DEV_DOWNLOAD/omarchy-aarch64-virt.qcow2"
