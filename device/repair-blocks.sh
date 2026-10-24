#!/usr/bin/env bash
# Repair specific 64 MiB blocks of a large file on the device in place (dd seek, conv=notrunc),
# per-block verified and retried — for fixing scattered corruption without resending the
# whole file. toybox dd's "bs=64M" is NOT 64 MiB, so sizes are in 1 MiB units (bs=1048576).
# usage: repair-blocks.sh LOCAL REMOTE START_BLOCK END_BLOCK   (blocks are 64 MiB, inclusive)
set -uo pipefail
. "$(dirname "$0")/config.sh"
L=$1 R=$2 A=$3 B=$4 BLK=64   # 64 MiB blocks
locblk() { tail -c +$(( $1*BLK*1048576 + 1 )) "$L" | head -c $((BLK*1048576)) | shasum -a 256 | cut -c1-16; }
remblk() { to 120 ssh -o ConnectTimeout=15 -o ServerAliveInterval=8 "$OHDEV" \
    "dd if='$R' bs=1048576 skip=$(( $1*BLK )) count=$BLK 2>/dev/null | sha256sum | cut -c1-16" 2>/dev/null | tr -cd '0-9a-f'; }
for i in $(seq "$A" "$B"); do
    want=$(locblk "$i")
    tries=0
    while [ "$(remblk "$i")" != "$want" ]; do
        tries=$((tries+1)); [ $tries -gt 15 ] && { echo "block $i: giving up after $tries" >&2; exit 1; }
        printf '\rblock %d: send (try %d)        ' "$i" "$tries"
        tail -c +$(( i*BLK*1048576 + 1 )) "$L" | head -c $((BLK*1048576)) | \
            to 300 ssh -o ConnectTimeout=15 -o ServerAliveInterval=8 -o ServerAliveCountMax=3 "$OHDEV" \
            "dd of='$R' bs=1048576 seek=$(( i*BLK )) count=$BLK conv=notrunc 2>/dev/null" 2>/dev/null
        sleep 1
    done
    printf '\rblock %d: ok%s\n' "$i" '            '
done
echo "repaired blocks $A..$B"
