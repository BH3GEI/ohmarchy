#!/bin/bash
# upload-on-host.sh: upload big release assets to an existing GitHub draft
# straight from the machine that has them (route D's Arch on the HarmonyOS
# host: GitHub at several MB/s there, while the Mac's link to the host is a
# slow tunnel). release.sh makes the draft and the small files on the Mac,
# then runs this over ssh; GitHub's own sha256 of each asset (the API's
# "digest") then goes into SHA256SUMS, so nothing is hashed here.
#   upload-on-host.sh REPO RELEASE_ID LOG FILE=NAME...   (token on stdin)
# The first line of stdin is a GitHub token. It stays in this shell's memory:
# never in a file, an argument or the environment; curl gets it on its stdin
# (-H @-). The uploads run detached (ssh to the host often hangs after a
# command), each line of LOG one result: "ok NAME SIZE" or "fail NAME why".
# Files over SPLIT_MIB (default 2000; GitHub takes under 2 GiB per asset) go up
# as NAME.part00, NAME.part01, ... cut from the file with dd into WORK.
set -u
repo=$1 id=$2 log=$3; shift 3
IFS= read -r tok
[ -n "$tok" ] || { echo "no token on stdin" >&2; exit 2; }
split_b=$(( ${SPLIT_MIB:-2000} * 1048576 ))
work=${WORK:-/var/tmp/ohm-upload}
up() {  # FILE NAME
    local f=$1 n=$2 size r
    size=$(stat -c %s "$f")
    for try in 1 2 3; do
        r=$(printf 'Authorization: Bearer %s\nContent-Type: application/octet-stream\nAccept: application/vnd.github+json\n' "$tok" |
            curl -sS -m 7200 -X POST -T "$f" -H @- \
                "https://uploads.github.com/repos/$repo/releases/$id/assets?name=$n" 2>&1)
        grep -q '"state": *"uploaded"' <<< "$r" && grep -q "\"size\": *$size[,}]" <<< "$r" &&
            { echo "ok $n $size" >> "$log"; return 0; }
        echo "retry $n ($try): $(tr -d '\n' <<< "$r" | cut -c1-200)" >> "$log"
        sleep 20
    done
    echo "fail $n" >> "$log"
    return 1
}
(
    trap '' HUP
    : > "$log"
    for a in "$@"; do
        f=${a%%=*} n=${a#*=}
        [ -f "$f" ] || { echo "fail $n no such file $f" >> "$log"; continue; }
        size=$(stat -c %s "$f")
        if [ "$size" -le "$split_b" ]; then
            up "$f" "$n"
            continue
        fi
        mkdir -p "$work"
        parts=$(( (size + split_b - 1) / split_b ))
        for k in $(seq 0 $((parts - 1))); do
            p=$work/$n.part$(printf %02d "$k")
            dd if="$f" of="$p" bs=1048576 skip=$((k * split_b / 1048576)) count=$((split_b / 1048576)) 2> /dev/null
            up "$p" "$(basename "$p")"
            rm -f "$p"
        done
        echo "whole $n $size" >> "$log"
    done
    echo "done" >> "$log"
) < /dev/null > /dev/null 2>&1 &
