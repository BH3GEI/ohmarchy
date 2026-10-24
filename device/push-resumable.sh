#!/usr/bin/env bash
# Resumable push of a large file to the device over the frps ssh tunnel, which drops
# long streams (seen dropping every ~256 MB). Appends from the remote file's current
# size, one small bounded chunk per ssh, retries with backoff across drops, and
# verifies sha256 at the end. Safe to re-run and to interrupt.
# usage: push-resumable.sh LOCAL REMOTE [CHUNK_MB]
set -uo pipefail
. "$(dirname "$0")/config.sh"
L=$1 R=$2 CH=${3:-32}
[ -f "$L" ] || { echo "no local file: $L" >&2; exit 1; }
total=$(stat -f%z "$L" 2>/dev/null || stat -c%s "$L")
# single-writer lock: two concurrent appends to the same remote file corrupt it
LOCK="${TMPDIR:-/tmp}/ohmarchy-push-$(echo "$R" | tr -c 'A-Za-z0-9' _).lock"
if [ -f "$LOCK" ] && kill -0 "$(cat "$LOCK" 2>/dev/null)" 2>/dev/null; then
    echo "another push is already running for $R (pid $(cat "$LOCK")); refusing" >&2; exit 1
fi
echo $$ > "$LOCK"
trap 'rm -f "$LOCK"' EXIT

rsize() {  # echo remote size, or nothing on failure
    to 40 ssh -o ConnectTimeout=15 -o ServerAliveInterval=8 -o ServerAliveCountMax=3 "$OHDEV" \
        "stat -c%s '$R' 2>/dev/null" 2>/dev/null | tr -cd '0-9'
}
to 40 ssh -o ConnectTimeout=15 "$OHDEV" "mkdir -p $(dirname "$R")" >/dev/null 2>&1

stall=0
while :; do
    off=$(rsize)
    [ -n "$off" ] || { echo "rsize failed, retry in 5s"; sleep 5; stall=$((stall+1)); [ $stall -gt 40 ] && { echo "giving up (rsize)"; exit 1; }; continue; }
    [ "$off" -ge "$total" ] && break
    printf '\r%d / %d (%d%%) stall=%d   ' "$off" "$total" "$((off*100/total))" "$stall"
    tail -c +$((off+1)) "$L" | head -c $((CH*1024*1024)) | \
        to 300 ssh -o ConnectTimeout=15 -o ServerAliveInterval=8 -o ServerAliveCountMax=3 "$OHDEV" "cat >> '$R'" 2>/dev/null
    new=$(rsize)
    if [ -n "$new" ] && [ "$new" -gt "$off" ]; then stall=0; else
        stall=$((stall+1)); [ $stall -gt 40 ] && { echo "giving up (no progress at $off)"; exit 1; }
        sleep $((stall<5 ? 2 : 6))
    fi
done
echo
want=$(shasum -a 256 "$L" | cut -d' ' -f1)
have=$(to 300 ssh -tt -o ConnectTimeout=20 "$OHDEV" "sha256sum '$R'" 2>/dev/null | tr -d '\r' | grep -oE '^[0-9a-f]{64}')
[ "$want" = "$have" ] && echo "ok $R sha256 $want" || { echo "SHA MISMATCH want=$want have=$have" >&2; exit 1; }
