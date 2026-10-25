#!/bin/bash
# HarmonyOS screen off and on, ROUNDS times (C; default 20), remotely: the screen
# goes off through the screen-off timeout (power-shell timeout -o 3000), not
# `power-shell suspend` (which suspends the whole machine and could leave it out of
# reach), and comes back with `power-shell wakeup`. Each round checks that the host
# still answers while the screen is off, that the power state went INACTIVE, and
# afterwards that the display app and Hyprland are the same processes and new
# frames reach the app's surface, and that a running VM (StratoVirt, e.g. 鸿融's)
# is still the same process. The timeout is restored at the end, also on failure.
# Needs the display app open and the screen to ourselves.
here=$(cd "$(dirname "$0")" && pwd)
"$here/../lib/screen-free.sh" || exit 1
B=${ARCH_BASE:-/data/local/archtest}
user=${ARCH_USER:-builder}
{
    echo "B=$B; U=$user; ROUNDS=${ROUNDS:-20}"
    cat <<'SH'
P=$(cat $B/session.pid)
trap 'power-shell timeout -r > /dev/null 2>&1; power-shell wakeup > /dev/null 2>&1' EXIT
app() { ps -ef | grep "com.ohmarchy.display$" | grep -v grep | awk '{print $2}' | head -1; }
hyp() { pgrep -x Hyprland | head -1; }
vm() { ps -ef | grep "stratovirt -machine" | grep -v grep | awk '{print $2}' | head -1; }
state() { hidumper -s PowerManagerService -a "-s" 2>/dev/null | grep -m1 "Current State" | awk '{print $3}'; }
latest() { hidumper -s RenderService -a "ohdispSurface fps" 2>/dev/null | grep -oE "^[0-9]{10,}" | sort -n | tail -1; }
ws() {
    nsenter -t $P -m -p -- chroot $B/arch /usr/bin/env -i PATH=/usr/bin /usr/bin/su - $U -c "export XDG_RUNTIME_DIR=/run/user/\$(id -u)
export HYPRLAND_INSTANCE_SIGNATURE=\$(hyprctl instances -j | python3 -c 'import json,sys; print(json.load(sys.stdin)[0][\"instance\"])')
hyprctl eval 'hl.dispatch(hl.dsp.focus({ workspace = \"$1\" }))' > /dev/null" < /dev/null
}
a0=$(app); h0=$(hyp); v0=$(vm); ok=0
[ -n "$a0" ] || { echo "display app not running"; exit 1; }
echo "start: state $(state), app $a0, hyprland $h0, vm ${v0:-none}"
for i in $(seq $ROUNDS); do
    power-shell timeout -o 3000 > /dev/null
    off=""
    for _ in $(seq 20); do sleep 0.5; s=$(state); [ "$s" != AWAKE ] && { off=$s; break; }; done
    power-shell timeout -r > /dev/null
    sleep 2
    alive=$(date +%T)   # this line running means the host still answers with the screen off
    power-shell wakeup > /dev/null; sleep 3
    on=$(state)
    t=$(latest); ws 2; sleep 0.5; ws 1; sleep 1
    new=$(hidumper -s RenderService -a "ohdispSurface fps" 2>/dev/null | grep -oE "^[0-9]{10,}" | awk -v t=${t:-0} '$1 > t' | wc -l)
    a=$(app); h=$(hyp); v=$(vm)
    r="off: ${off:-no (stayed AWAKE)}, host answered at $alive, back: $on, new frames $new, app $([ "$a" = "$a0" ] && echo same || echo "restarted ($a)"), hyprland $([ "$h" = "$h0" ] && echo same || echo "restarted ($h)"), vm $([ "$v" = "$v0" ] && echo same || echo "changed (${v:-gone})")"
    if [ -n "$off" ] && [ "$on" = AWAKE ] && [ "$new" -gt 0 ] && [ "$a" = "$a0" ] && [ "$h" = "$h0" ] && [ "$v" = "$v0" ]; then ok=$((ok + 1)); echo "round $i: ok: $r"; else echo "round $i: FAIL: $r"; fi
done
echo "summary $ok of $ROUNDS rounds: screen went off and came back with the desktop running and drawing"
SH
} | "$here/../lib/remote.sh" screenoff host 1200
