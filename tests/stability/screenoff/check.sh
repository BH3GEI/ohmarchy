# Host side of screenoff.sh: after unlocking, make the desktop draw and report the
# power state, new frames on the app's surface, and the app and Hyprland pids.
B=${ARCH_BASE:-/data/local/archtest}; P=$(cat $B/session.pid)
state() { hidumper -s PowerManagerService -a "-s" 2>/dev/null | grep -m1 "Current State" | awk '{print $3}'; }
latest() { hidumper -s RenderService -a "ohdispSurface fps" 2>/dev/null | grep -oE "^[0-9]{10,}" | sort -n | tail -1; }
t=$(latest)
nsenter -t $P -m -p -- chroot $B/arch /usr/bin/env -i PATH=/usr/bin /usr/bin/su - builder -c 'export XDG_RUNTIME_DIR=/run/user/60000; export HYPRLAND_INSTANCE_SIGNATURE=$(hyprctl instances -j | python3 -c "import json,sys; print(json.load(sys.stdin)[0][\"instance\"])"); for w in 2 1; do hyprctl eval "hl.dispatch(hl.dsp.focus({ workspace = \"$w\" }))" > /dev/null; sleep 0.5; done' < /dev/null
new=$(hidumper -s RenderService -a "ohdispSurface fps" 2>/dev/null | grep -oE "^[0-9]{10,}" | awk -v t=${t:-0} '$1 > t' | wc -l)
echo "$(state) $new $(ps -ef | grep 'com.ohmarchy.display$' | grep -v grep | awk '{print $2}') $(pgrep -x Hyprland | head -1)"
