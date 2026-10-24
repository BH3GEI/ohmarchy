#!/usr/bin/env bash
# Host-side numbers for the Route H baseline, read-only on the device:
# overall CPU busy %, per-core, the top CPU consumers, and SoC temperatures,
# sampled over a window while the Aetherium TCG VM runs.
# usage: baseline.sh [SECONDS]   (default 10)
# Frame rate / refresh use oseasy/measure-fps.sh (composer fps, panel activeMode,
# hitrace) pointed at the Aetherium VM window; boot time is timed around the launch.
set -euo pipefail
. "$(dirname "$0")/config.sh"
SECS=${1:-10}
"$(dirname "$0")/ohsh" -t $((SECS + 60)) - <<SH
secs=$SECS
read_stat() { awk '/^cpu /{for(i=2;i<=NF;i++)s+=\$i; print s, \$5}' /proc/stat; }  # total, idle
set -- \$(read_stat); t0=\$1; i0=\$2
# temperatures before
echo "== SoC temperatures (start):"
for z in /sys/class/thermal/thermal_zone*; do
  [ -r "\$z/temp" ] || continue
  printf '  %s %s = %s\n' "\$(basename \$z)" "\$(cat \$z/type 2>/dev/null)" "\$(cat \$z/temp 2>/dev/null)"
done
sleep \$secs
set -- \$(read_stat); t1=\$1; i1=\$2
busy=\$(awk -v t0=\$t0 -v i0=\$i0 -v t1=\$t1 -v i1=\$i1 'BEGIN{dt=t1-t0; di=i1-i0; if(dt>0) printf "%.1f", (dt-di)*100.0/dt; else print "n/a"}')
echo "== host CPU busy over \${secs}s: \${busy}%"
echo "== top CPU consumers:"
top -b -n 1 2>/dev/null | head -14 | tail -9
echo "== SoC temperatures (end):"
for z in /sys/class/thermal/thermal_zone*; do
  [ -r "\$z/temp" ] || continue
  printf '  %s %s = %s\n' "\$(basename \$z)" "\$(cat \$z/type 2>/dev/null)" "\$(cat \$z/temp 2>/dev/null)"
done
echo "== load average:"; uptime
SH
