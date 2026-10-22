#!/usr/bin/env bash
# guest.sh 'COMMANDS' [MAXSECS]: run shell commands inside the Oseasy guest.
# The guest serves a shell on 172.16.100.2:5000 (see oseasy/initramfs); the
# Fold's hdc shell connects out to it (it is not allowed to listen).
. "$(dirname "$0")/env.sh"
f=$(mktemp "$OUT/cmd.XXXX"); printf '%s\nexit\n' "$1" > "$f"
"$HDC" -t "$HDC_TARGET" file send "$f" /data/local/tmp/ohm.cmd >/dev/null; rm -f "$f"
"$HDC" -t "$HDC_TARGET" shell "netcat -w 5 -q ${2:-120} 172.16.100.2 5000 < /data/local/tmp/ohm.cmd"
