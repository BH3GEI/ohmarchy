#!/bin/bash
# Autostart without a reboot (docs/native-desktop.md, "Starting by itself"):
# stop the desktop, the docker gate and route I's VM, run the boot hook the way
# init runs it, then use it like a user: open the display app (what a click on
# "Omarchy (native)" does), docker run in a terminal of the desktop (route I's VM
# starts on demand), and wait for the VM's idle stop. A screenshot after each
# step into OUT (default tests/results/autostart-<time>).
# Leaves route D's Arch session and the GPU broker running: other work shares
# the session, and boot-start.sh only starts what is not running.
# Needs no other VM running (鸿融, OSEasy): the Docker step starts route I's.
here=$(cd "$(dirname "$0")" && pwd)
B=${ARCH_BASE:-/data/local/archtest}
U=${ARCH_USER:-builder}
OHUI="$here/../../tools/ohdev/ohui"
OUT=${OUT:-$here/../results/autostart-$(date +%Y%m%d-%H%M%S)}
VM=/data/local/kaidashi/bin/ohmarchy-vm
S=/data/local/kaidashi/ownvm/svc
h() { perl -e 'alarm shift; exec @ARGV' "${DL:-90}" ssh -o ConnectTimeout=15 "${OHOS_HOST:-ohdev}" sh -s; }
ses() {
    printf '%s\n' "P=\$(cat $B/session.pid)" \
        "nsenter -t \$P -m -p -- chroot $B/arch /usr/bin/env -i PATH=/usr/bin /usr/bin/su - $U -c 'export XDG_RUNTIME_DIR=/run/user/\$(id -u) WAYLAND_DISPLAY=wayland-1
export HYPRLAND_INSTANCE_SIGNATURE=\$(hyprctl instances -j | python3 -c \"import json,sys; print(json.load(sys.stdin)[0][\\\"instance\\\"])\")
$1' < /dev/null" | h
}
launch() { ses "hyprctl eval \"hl.exec_cmd([[$1]])\" > /dev/null"; }
t0=$(date +%s)
step() {  # name, seconds to let it settle
    sleep "$2"
    mkdir -p "$OUT"
    OHUI_DIR=$OUT "$OHUI" shot "$1" > /dev/null 2>&1
    printf '%5s s  %s  (%s.jpeg)\n' "$(( $(date +%s) - t0 ))" "$1" "$OUT/$1"
}
procs() {
    echo 'for p in /proc/[0-9]*; do c=$(tr "\0" " " < $p/cmdline 2>/dev/null); case "$c" in *docker-gate*|*vtest-broker*|*bin/Hyprland*|*audio-relay*|*stratovirt\ -machine*) echo "      ${p#/proc/} ${c%% -*}";; esac; done 2>/dev/null | sort -u -k2' | h
}

echo "== 0. stop: route I's VM, the docker gate, the desktop, the display app"
# the app too: after a boot it is not running, and a click starts it fresh; an
# app left open is only brought to the front and keeps showing its last frame
DL=150 h <<SH
aa force-stop com.ohmarchy.display > /dev/null 2>&1
pidof stratovirt > /dev/null && sh $VM running && sh $VM stop < /dev/null
g=\$(cat $S/gate.pid 2>/dev/null); [ -n "\$g" ] && tr '\0' ' ' < /proc/\$g/cmdline 2>/dev/null | grep -q ohmarchy-docker-gate && kill \$g
sh $B/bin/omarchy desktop stop > /dev/null 2>&1
sleep 2; true
SH
procs
step 00-stopped 1

echo "== 1. the boot hook, as init runs it (clean environment, cwd /, detached)"
DL=150 h <<SH
cd / && env -i PATH=/system/bin:/bin setsid sh $B/boot-start.sh < /dev/null > /dev/null 2>&1 &
i=0; until [ -S /proc/\$(cat $B/session.pid)/root/tmp/.ohmarchy-docker.sock ] && pidof Hyprland > /dev/null; do i=\$((i+1)); [ \$i -ge 120 ] && break; sleep 1; done
echo "      up \${i} s after the hook started (it waits 20 s first); boot-start.log: \$(cat $B/boot-start.log)"
SH
procs
step 01-after-boot-hook 0

echo "== 2. a user opens \"Omarchy (native)\""
echo "aa start -a EntryAbility -b com.ohmarchy.display > /dev/null" | h
step 02-app-open 12

echo "== 3. docker run in a terminal of the desktop (route I's VM starts on demand)"
launch "foot -T autostart-docker --hold docker run --rm hello-world"   # no quotes here (launch)
step 03-docker-cold 30
echo "tail -4 $S/gate.log" | h | sed 's/^/      /'

echo "== 4. idle: the gate stops the VM after 3 minutes without use"
DL=400 h <<SH | sed 's/^/      /'
i=0; while sh $VM running && [ \$i -lt 360 ]; do sleep 5; i=\$((i+5)); done
sh $VM running && echo "FAIL still running after \$i s" || echo "VM stopped \$i s after the docker step"
tail -2 $S/gate.log
SH
step 04-after-idle-stop 0
echo "screenshots in $OUT"
