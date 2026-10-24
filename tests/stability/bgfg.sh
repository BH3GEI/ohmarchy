#!/bin/bash
# Display app to the background and back, ROUNDS times (C; default 20): the closest
# remote stand-in for HarmonyOS's screen off, which destroys and recreates the app's
# surface. Each round brings Settings to the front, then the display app again,
# makes the desktop draw (workspace switch) and checks that new frames reached the
# app's surface (RenderService "ohdispSurface fps" timestamps after the switch).
# Also records whether the app process and Hyprland survived. Needs the screen.
here=$(cd "$(dirname "$0")" && pwd)
"$here/../lib/screen-free.sh" || exit 1
B=${ARCH_BASE:-/data/local/archtest}
user=${ARCH_USER:-builder}
{
    echo "B=$B; U=$user; ROUNDS=${ROUNDS:-20}"
    cat <<'SH'
P=$(cat $B/session.pid)
app() { ps -ef | grep "com.ohmarchy.display$" | grep -v grep | awk '{print $2}' | head -1; }
hyp() { pgrep -x Hyprland | head -1; }
ws() {
    nsenter -t $P -m -p -- chroot $B/arch /usr/bin/env -i PATH=/usr/bin /usr/bin/su - $U -c "export XDG_RUNTIME_DIR=/run/user/\$(id -u)
export HYPRLAND_INSTANCE_SIGNATURE=\$(hyprctl instances -j | python3 -c 'import json,sys; print(json.load(sys.stdin)[0][\"instance\"])')
hyprctl eval 'hl.dispatch(hl.dsp.focus({ workspace = \"$1\" }))' > /dev/null" < /dev/null
}
latest() { hidumper -s RenderService -a "ohdispSurface fps" 2>/dev/null | grep -oE "^[0-9]{10,}" | sort -n | tail -1; }
aa start -a EntryAbility -b com.ohmarchy.display > /dev/null; sleep 4
a0=$(app); h0=$(hyp); ok=0
for i in $(seq $ROUNDS); do
    aa start -a com.huawei.hmos.settings.MainAbility -b com.huawei.hmos.settings > /dev/null; sleep 3
    aa start -a EntryAbility -b com.ohmarchy.display > /dev/null; sleep 3
    t=$(latest)
    ws 2; sleep 0.5; ws 1; sleep 1
    new=$(hidumper -s RenderService -a "ohdispSurface fps" 2>/dev/null | grep -oE "^[0-9]{10,}" | awk -v t=${t:-0} '$1 > t' | wc -l)
    a=$(app); h=$(hyp)
    r="frames $new, app $([ "$a" = "$a0" ] && echo same || echo "restarted ($a)"), hyprland $([ "$h" = "$h0" ] && echo same || echo "restarted ($h)")"
    [ "$new" -gt 0 ] && ok=$((ok + 1)) && echo "round $i: ok: $r" || echo "round $i: FAIL: $r"
    a0=$a; h0=$h
done
echo "summary $ok of $ROUNDS rounds showed new frames after coming back"
SH
} | "$here/../lib/remote.sh" bgfg host 600
