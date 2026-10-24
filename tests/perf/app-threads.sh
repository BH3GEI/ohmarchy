#!/bin/bash
# CPU of the display app per thread over SECONDS_IDLE (default 15), in % of one
# core: where its time goes when the desktop is idle (B). The app must be open.
here=$(cd "$(dirname "$0")" && pwd)
S=${SECONDS_IDLE:-15}
{
    echo "S=$S"
    cat <<'SH'
p=$(ps -ef | grep "com.ohmarchy.display$" | grep -v grep | awk '{print $2}' | head -1)
[ -n "$p" ] || { echo "display app not running"; exit 1; }
snap() { for t in /proc/$p/task/*; do echo "$(basename $t) $(cut -d' ' -f14,15 $t/stat | awk '{print $1 + $2}') $(cat $t/comm)"; done; }
snap > /data/local/tmp/thr.a; sleep $S; snap > /data/local/tmp/thr.b
awk -v s=$S 'NR == FNR {a[$1] = $2; next} {d = ($2 - a[$1]) / s; if (d > 0) printf "%6.1f %% %s %s\n", d, $1, $3; t += d} END {printf "%6.1f %% total\n", t}' /data/local/tmp/thr.a /data/local/tmp/thr.b | sort -rn | head -15
rm -f /data/local/tmp/thr.a /data/local/tmp/thr.b
SH
} | "$here/../lib/remote.sh" app-threads host $((S + 60))
