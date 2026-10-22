#!/usr/bin/env bash
# shot.sh NAME: full-screen screenshot of the Fold -> $OUT/NAME.jpeg
. "$(dirname "$0")/env.sh"
hs "snapshot_display -f /data/local/tmp/ohm.jpeg" | grep -qi success &&
    "$HDC" -t "$HDC_TARGET" file recv /data/local/tmp/ohm.jpeg "$OUT/$1.jpeg" >/dev/null && echo "$OUT/$1.jpeg"
