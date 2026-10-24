#!/bin/sh
# Frames that reach the HarmonyOS screen, counted by the host's own compositor,
# the same way as docs/native-desktop.md: run on the workstation while the
# guest animates (es2gears, workspace switching) with its window in front.
#   oseasy/measure-fps.sh [SECONDS] [WINDOW]
# Prints the panel mode; frames per second from `composer fps` (RenderService
# keeps the timestamps of the last frames composed for the screen; counted over
# the last SECONDS, default 8, capped by how many it keeps); the same for
# WINDOW's `fps` if given; and per-second counts of DoComposition /
# HwcPresentDisplay / NativeWindowFlushBuffer from a hitrace capture of SECONDS,
# and the flushes per thread (task-pid as hitrace names it): other windows that
# present (ohmarchy-120, the Oseasy app's own animations) must not be counted
# as the guest's frames.
set -eu
secs=${1:-8}; win=${2:-}
perl -e 'alarm shift; exec @ARGV' $((secs * 2 + 90)) ssh -o BatchMode=yes ohdev sh -s <<EOF
T=/data/local/tmp/oseasy-fps
hidumper -s RenderService -a screen | grep -e activeMode -e 'supportedMode\[0\]'
hitrace -t $secs -o \$T.trace graphic > \$T.hitrace.log 2>&1
rate() { # stdin: one ns timestamp per line; prints frames/s over the last window
  sort -n | awk -v w=$secs 'NF==1 && \$1 ~ /^[0-9]+\$/ && \$1 > 0 { t[n++] = \$1 }
    END { if (n < 2) { print "n/a"; exit }
          last = t[n-1]; span = w * 1e9; c = 0; first = last
          for (i = n-1; i >= 0 && last - t[i] <= span; i--) { c++; first = t[i] }
          printf "%.1f frames/s (%d frames over %.2f s)\n", (c-1) / ((last-first)/1e9), c, (last-first)/1e9 }'
}
echo "== composer fps: \$(hidumper -s RenderService -a 'composer fps' | rate)"
[ -n "$win" ] && echo "== $win fps: \$(hidumper -s RenderService -a '$win fps' | rate)"
echo "== hitrace $secs s"
for k in RSMainThread::DoComposition HwcPresentDisplay NativeWindowFlushBuffer; do
  c=\$(grep -c "H:\$k" \$T.trace 2>/dev/null || true)
  echo "\$k: \${c:-0} total, \$(( \${c:-0} / $secs ))/s"
done
echo "== NativeWindowFlushBuffer per thread (/s)"
grep "H:NativeWindowFlushBuffer" \$T.trace 2>/dev/null | awk '{print \$1}' | sort | uniq -c | sort -rn | head -6 |
  awk -v w=$secs '{ printf "  %-40s %d\\n", \$2, \$1 / w }'
EOF
