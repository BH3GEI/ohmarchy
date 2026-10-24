#!/usr/bin/env bash
# Resumable push of a large file to the device over the frps ssh tunnel, which drops
# long streams. Appends from the remote file's current size, one bounded chunk per ssh,
# and loops until sizes match; then verifies sha256. Safe to re-run.
# usage: push-resumable.sh LOCAL REMOTE [CHUNK_MB]
set -euo pipefail
. "$(dirname "$0")/config.sh"
L=$1 R=$2 CH=${3:-128}
[ -f "$L" ] || { echo "no local file: $L" >&2; exit 1; }
total=$(stat -f%z "$L" 2>/dev/null || stat -c%s "$L")
rsize() { to 60 ssh -o ConnectTimeout=20 -o ServerAliveInterval=10 "$OHDEV" \
    "s=\$(stat -c%s '$R' 2>/dev/null); echo \${s:-0}" 2>/dev/null | tr -cd '0-9'; }
to 60 ssh -o ConnectTimeout=20 "$OHDEV" "mkdir -p $(dirname "$R")"
off=$(rsize); off=${off:-0}
echo "resuming at $off / $total"
while [ "$off" -lt "$total" ]; do
    # send CH MiB starting at byte $off, appended on the device
    if to 900 bash -c "tail -c +$((off+1)) '$L' | head -c $((CH*1024*1024)) | \
        ssh -o ConnectTimeout=20 -o ServerAliveInterval=10 -o ServerAliveCountMax=3 '$OHDEV' \
        \"cat >> '$R'\""; then :; else echo "chunk at $off failed, retrying"; sleep 3; fi
    new=$(rsize); new=${new:-0}
    if [ "$new" -le "$off" ]; then echo "no progress at $off (got $new), retrying"; sleep 3; fi
    off=$new
    printf '\r%d / %d (%d%%)   ' "$off" "$total" "$((off*100/total))"
done
echo
want=$(shasum -a 256 "$L" | cut -d' ' -f1)
have=$(to 300 ssh -tt -o ConnectTimeout=20 "$OHDEV" "sha256sum '$R'" 2>/dev/null | tr -d '\r' | grep -oE '^[0-9a-f]{64}')
if [ "$want" = "$have" ]; then echo "ok $R sha256 $want"; else
    echo "SHA MISMATCH want=$want have=$have" >&2; exit 1; fi
