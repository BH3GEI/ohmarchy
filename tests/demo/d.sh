#!/bin/bash
# Route D demo, automated (docs/demo.md): each step is one command on the
# HarmonyOS host, then a screenshot into OUT (default tests/results/demo-<time>).
#   tests/demo/d.sh prep    start route I's VM for the Docker step (not part of the
#                           demo; takes vm.lock; needs the 鸿融 VM off)
#   tests/demo/d.sh         the demo, timed
#   tests/demo/d.sh clean   close the demo's windows
here=$(cd "$(dirname "$0")" && pwd)
B=${ARCH_BASE:-/data/local/archtest}
U=${ARCH_USER:-builder}
OHUI="$here/../../tools/ohdev/ohui"
OUT=${OUT:-$here/../results/demo-$(date +%Y%m%d-%H%M%S)}
VM=${OHMARCHY_VM:-/data/local/kaidashi/bin/ohmarchy-vm}
h() { perl -e 'alarm shift; exec @ARGV' "${DL:-90}" ssh -o ConnectTimeout=15 "${OHOS_HOST:-ohdev}" sh -s; }
# run CMD in the desktop session as the desktop user, with Hyprland's environment
ses() {
    printf '%s\n' "P=\$(cat $B/session.pid)" \
        "nsenter -t \$P -m -p -- chroot $B/arch /usr/bin/env -i PATH=/usr/bin /usr/bin/su - $U -c 'export XDG_RUNTIME_DIR=/run/user/\$(id -u) WAYLAND_DISPLAY=wayland-1
export HYPRLAND_INSTANCE_SIGNATURE=\$(hyprctl instances -j | python3 -c \"import json,sys; print(json.load(sys.stdin)[0][\\\"instance\\\"])\")
$1' < /dev/null" | h
}
# start CMD from Hyprland, as from a keybinding (SUPER+RETURN etc.); no quotes in CMD
launch() { ses "hyprctl eval \"hl.exec_cmd([[$1]])\" > /dev/null"; }
t0=$(date +%s)
step() {  # name, seconds to let it settle
    sleep "$2"
    mkdir -p "$OUT"
    OHUI_DIR=$OUT "$OHUI" shot "$1" > /dev/null 2>&1
    printf '%5s s  %s  (%s.jpeg)\n' "$(( $(date +%s) - t0 ))" "$1" "$OUT/$1"
}

case "${1:-run}" in
prep)
    echo "sh $VM start; sh $VM status" | DL=300 h ;;
clean)
    ses 'hyprctl clients -j | python3 -c "import json,sys
for c in json.load(sys.stdin):
    if c[\"title\"].startswith(\"demo-\") or c[\"class\"] in (\"firefox\", \"org.gnome.Nautilus\"):
        print(c[\"address\"])" | while read a; do hyprctl eval "hl.dispatch(hl.dsp.window.close({ window = \"address:$a\" }))" > /dev/null; done
omarchy-menu close > /dev/null 2>&1'
    ;;
run)
    # 1. the desktop (idempotent; at boot ohmarchy-desktop.cfg already does it)
    echo "sh $B/bin/omarchy desktop start > /dev/null" | h
    step 01-desktop-started 0
    # 2. open the display app (a click on "Omarchy (native)" in the dock does the same)
    echo "aa start -a EntryAbility -b com.ohmarchy.display > /dev/null" | h
    step 02-app-open 12
    # 3. terminal with fastfetch (SUPER+RETURN, then fastfetch)
    launch "foot -T demo-terminal --hold fastfetch"
    step 03-terminal-fastfetch 3
    # 4. workspaces at 120 Hz (SUPER+2 / SUPER+1), measured by HarmonyOS's compositor
    echo 'hidumper -s RenderService -a "fpsClear" > /dev/null 2>&1' | h
    ses 'for i in 1 2 3 4 5; do hyprctl eval "hl.dispatch(hl.dsp.focus({ workspace = \"2\" }))" > /dev/null; sleep 0.45; hyprctl eval "hl.dispatch(hl.dsp.focus({ workspace = \"1\" }))" > /dev/null; sleep 0.45; done'
    fps=$(echo 'hidumper -s RenderService -a "composer fps" 2>/dev/null | cat' | h | python3 -c '
import re, sys
t = sys.stdin.read()
ts = sorted(int(x) for x in re.findall(r"^(\d{10,})$", t, re.M)) or sorted(int(b) for a, b in re.findall(r"^(\d+):(\d+)$", t, re.M))
d = [(b - a) / 1e6 for a, b in zip(ts, ts[1:]) if (b - a) / 1e6 < 50]
print(f"{1000 / (sum(d) / len(d)):.0f}" if d else "?")')
    step 04-workspaces-${fps}fps 0
    # 5. the browser (SUPER+SHIFT+B): Firefox, sandboxed
    launch "omarchy-launch-browser https://omarchy.org"
    step 05-browser 5
    # 6. the Omarchy menu (SUPER+SPACE), then an app from it: Files (SUPER+SHIFT+F)
    ses 'omarchy-menu summon > /dev/null 2>&1'
    step 06-omarchy-menu 1
    ses 'omarchy-menu close > /dev/null 2>&1'
    launch "nautilus --new-window"
    step 07-files 2
    # 8. Docker through route I's VM (d.sh prep first)
    if echo "sh $VM status 2>/dev/null | grep -q 'dockerd: [0-9]' && echo up" | h | grep -q up; then
        launch "foot -T demo-docker --hold docker run --rm hello-world"
        step 08-docker-hello-world 6
    else
        echo "      route I's VM is not up: Docker step skipped (tests/demo/d.sh prep)"
    fi
    echo "total $(( $(date +%s) - t0 )) s; screenshots in $OUT"
    ;;
esac
