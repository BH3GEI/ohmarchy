#!/bin/bash
# Power proxy for B (the battery reports no current while on mains): over SECONDS_P
# (default 60) seconds, sampled every 0.5 s on the host, the whole machine's CPU
# busy time (% of all cores), the average frequency of each CPU cluster, and the
# average GPU and DDR frequency. Run it in each state to compare, with nothing else
# going on (other lines' VMs, builds):
#   LABEL="native idle" tests/perf/power.sh       desktop in the display app, idle
#   LABEL="native gears" ...                      es2gears in the native desktop
#   LABEL="vm idle" / "vm gears"                  the same in the 鸿融 VM
# For energy, HarmonyOS's own per-app accounting (XpowerManager, dubai.db
# hourly_app_energy) only flushes every half hour or so; see docs/acceptance.md B.
here=$(cd "$(dirname "$0")" && pwd)
S=${SECONDS_P:-60}
{
    echo "S=$S; LABEL='${LABEL:-}'"
    cat <<'SH'
busy() { awk '/^cpu / {print $2 + $3 + $4 + $7 + $8, $2 + $3 + $4 + $5 + $6 + $7 + $8}' /proc/stat; }
set -- $(busy); b0=$1; t0=$2
: > /data/local/tmp/power.samples
n=$((S * 2)); i=0
while [ $i -lt $n ]; do
    f=""; for p in /sys/devices/system/cpu/cpufreq/policy*; do f="$f $(cat $p/scaling_cur_freq)"; done
    echo "$f $(cat /sys/class/devfreq/gpufreq/cur_freq) $(cat /sys/class/devfreq/ddrfreq/cur_freq)" >> /data/local/tmp/power.samples
    sleep 0.5; i=$((i + 1))
done
set -- $(busy); b1=$1; t1=$2
echo "label: $LABEL"
awk -v b=$((b1 - b0)) -v t=$((t1 - t0)) 'BEGIN {printf "cpu busy: %.1f %% of all cores\n", b / t * 100}'
awk '{for (i = 1; i <= NF; i++) s[i] += $i; n++} END {
    printf "cpu MHz by cluster:"; for (i = 1; i <= NF - 2; i++) printf " %.0f", s[i] / n / 1000; printf "\n"
    printf "gpu MHz: %.0f\nddr MHz: %.0f\n", s[NF - 1] / n / 1e6, s[NF] / n / 1e6}' /data/local/tmp/power.samples
rm -f /data/local/tmp/power.samples
SH
} | "$here/../lib/remote.sh" power host $((S + 60))
