#!/bin/bash
# pkglist.sh: the packages of an Arch/ALARM root filesystem (a mounted disk
# image), one per line: NAME|VERSION|PKGBASE|LICENSES (licenses space-separated),
# from pacman's local database. Input for gpl-sources.sh.
#   tools/release/pkglist.sh ROOT > pkglist.txt
set -euo pipefail
db=${1:?root of the image}/var/lib/pacman/local
for d in "$db"/*/; do
    [ -f "$d/desc" ] || continue
    awk -v RS= -F'\n' '
        $1 == "%NAME%" { n = $2 } $1 == "%VERSION%" { v = $2 } $1 == "%BASE%" { b = $2 }
        $1 == "%LICENSE%" { l = $2; for (i = 3; i <= NF; i++) l = l " " $i }
        END { print n "|" v "|" (b == "" ? n : b) "|" l }' "$d/desc"
done | sort
