#!/bin/bash
# Idle CPU and memory of the native desktop (B): the desktop's processes in the Arch
# session (idle_session.py) plus the host side (the display app, the GPU server),
# sampled over SECONDS (default 60) with nothing being used. CPU is in % of one core.
here=$(cd "$(dirname "$0")" && pwd)
S=${SECONDS_IDLE:-60}
B=${ARCH_BASE:-/data/local/archtest}
{
    echo "B=$B; P=\$(cat $B/session.pid); T=/proc/\$P/root/tmp/ohm-tests; S=$S"
    echo "mkdir -p \$T"
    echo "cat > \$T/idle_session.py <<'END_OF_PY'"; cat "$here/idle_session.py"; echo "END_OF_PY"
    cat <<'SH'
ticks() { for p in $1; do [ -r /proc/$p/stat ] && cut -d' ' -f14,15 /proc/$p/stat; done | awk '{t += $1 + $2} END {print t + 0}'; }
host=$(ps -ef | grep -E "com.ohmarchy.display$|virgl_test_server|vtest-broker" | grep -v grep | awk '{print $2}')
a=$(ticks "$host"); t0=$(date +%s)
nsenter -t $P -m -p -- chroot $B/arch /usr/bin/env -i PATH=/usr/bin python3 /tmp/ohm-tests/idle_session.py $S > $T/idle.json
b=$(ticks "$host"); t1=$(date +%s)
kb=0; for p in $host; do r=$(awk '/^Pss:/ {print $2}' /proc/$p/smaps_rollup 2>/dev/null); kb=$((kb + ${r:-0})); done
echo "=== SESSION"; cat $T/idle.json
echo "=== HOST"; echo "{\"cpu_percent\": $(awk -v a=$a -v b=$b -v d=$((t1 - t0)) 'BEGIN {printf "%.2f", (b - a) / 100 / d * 100}'), \"memory_mb\": $((kb / 1024)), \"processes\": $(echo $host | wc -w)}"
SH
} | "$here/../lib/remote.sh" perf-idle host $((S + 120)) | python3 "$here/idle_summary.py"
