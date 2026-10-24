#!/bin/bash
# Battery drain over MINUTES (default 30) on the HarmonyOS host, for the on-site
# power test (B): the machine must be unplugged. Samples the battery's current and
# voltage every 10 s and reports the average power draw in watts, plus the charge
# used. Run it once per state (see docs/acceptance.md, on-site checklist).
#   LABEL="native idle" MINUTES=30 tests/perf/battery.sh
here=$(cd "$(dirname "$0")" && pwd)
M=${MINUTES:-30}
{
    echo "M=$M; LABEL='${LABEL:-}'"
    cat <<'SH'
b=/sys/class/power_supply/Battery
[ "$(cat /sys/class/power_supply/Mains/online 2>/dev/null)" = 1 ] && { echo "still on mains: unplug first"; exit 1; }
c0=$(cat $b/capacity); n=0; sum=0
end=$(( $(cut -d. -f1 /proc/uptime) + M * 60 ))
while [ "$(cut -d. -f1 /proc/uptime)" -lt $end ]; do
    i=$(cat $b/current_now); v=$(cat $b/voltage_now)
    sum=$(awk -v s=$sum -v i=$i -v v=$v 'BEGIN {printf "%.3f", s + (i < 0 ? -i : i) * v / 1e12}')
    n=$((n + 1)); sleep 10
done
echo "label: $LABEL"
echo "minutes: $M, samples: $n"
awk -v s=$sum -v n=$n 'BEGIN {printf "average draw: %.2f W\n", s / n}'
echo "battery: $c0 % -> $(cat $b/capacity) %"
SH
} | "$here/../lib/remote.sh" battery host $((M * 60 + 120))
