#!/bin/bash
# Workspace switch frame rate (B): switches between two workspaces (a terminal on
# each) every 0.45 s for 10 s through hyprctl, then reads HarmonyOS's compositor
# frame timestamps (hidumper RenderService "composer fps") and reports the rate
# while frames are flowing (gaps over 50 ms, between animations, left out). The
# display app must be open and in front; target >= 110 fps.
here=$(cd "$(dirname "$0")" && pwd)
B=${ARCH_BASE:-/data/local/archtest}
user=${ARCH_USER:-builder}
{
    echo "B=$B; U=$user"
    cat <<'SH'
P=$(cat $B/session.pid)
hidumper -s RenderService -a "fpsClear" > /dev/null 2>&1
nsenter -t $P -m -p -- chroot $B/arch /usr/bin/env -i PATH=/usr/bin /usr/bin/su - $U -c '
export XDG_RUNTIME_DIR=/run/user/$(id -u) WAYLAND_DISPLAY=wayland-1
export HYPRLAND_INSTANCE_SIGNATURE=$(hyprctl instances -j | python3 -c "import json,sys; print(json.load(sys.stdin)[0][\"instance\"])")
ws() { hyprctl eval "hl.dispatch(hl.dsp.focus({ workspace = \"$1\" }))" > /dev/null; }
pids=""
for w in 2 3; do ws $w; foot -T ohm-ws-test sleep 60 & pids="$pids $!"; sleep 1.5; done
end=$(($(date +%s) + 10))
while [ $(date +%s) -lt $end ]; do ws 2; sleep 0.45; ws 3; sleep 0.45; done
ws 1; kill $pids 2>/dev/null' < /dev/null
hidumper -s RenderService -a "composer fps" 2>/dev/null | cat > /data/local/tmp/ws.fps  # straight into a file it writes nothing
echo "=== FPS"; cat /data/local/tmp/ws.fps; rm -f /data/local/tmp/ws.fps
SH
} | "$here/../lib/remote.sh" perf-workspace host 120 | python3 -c '
import re, sys
t = sys.stdin.read().split("=== FPS")[-1]
ts = sorted(int(x) for x in re.findall(r"^(\d{10,})$", t, re.M)) or sorted(int(b) for a, b in re.findall(r"^(\d+):(\d+)$", t, re.M))
d = [(b - a) / 1e6 for a, b in zip(ts, ts[1:])]
busy = [x for x in d if x < 50]
if not busy:
    print(f"no frames recorded ({len(ts)} timestamps, gaps {sorted(d)[:5]})"); sys.exit(1)
fps = 1000 / (sum(busy) / len(busy))
print(f"workspace switch: {fps:.1f} fps over {len(busy)} frames ({len(ts)} timestamps)")
'
