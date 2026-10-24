#!/bin/bash
# Boot diagnostics for Hyprland in the Oseasy VM (root, from ohmarchy-boot-diag.service).
# Lock slots are short and Oseasy forgets the VM at power-off, so everything worth
# knowing is collected unattended: for each stage, the session is (re)started with
# that stage's environment, given 60 s, and then the full Hyprland log, the KMS
# state, every Hyprland thread's kernel stack, vmwgfx interrupts and 2 s of
# drm.debug go to /var/log/ohmarchy-boot/<boot>/<stage>/. A one-line summary per
# stage also goes to the kernel log, which is the VM's serial console (the host
# reads it in /data/log/hwf_service/vmlog).
#   stages: default, AQ_NO_ATOMIC=1 (legacy KMS), AQ_NO_MODIFIERS=1 (linear buffers),
#   then modetest's page-flip rate with the session stopped, and the session back.
set -u
U=$(awk -F: '$3 == 1000 {print $1}' /etc/passwd)
H=$(getent passwd "$U" | cut -d: -f6)
B=/var/log/ohmarchy-boot/$(date +%Y%m%d-%H%M%S)
ENVF=$H/.config/uwsm/env-hyprland
mkdir -p "$B" "$(dirname "$ENVF")"
mountpoint -q /sys/kernel/debug || mount -t debugfs debugfs /sys/kernel/debug
say() { echo "ohmarchy-boot-diag: $*" > /dev/kmsg; echo "$*" >> "$B/summary.txt"; }

irqs() { awk '/vmwgfx/ {s=0; for (i = 2; i <= NF && $i ~ /^[0-9]+$/; i++) s += $i; print s}' /proc/interrupts | head -1; }

collect() {
    local d=$B/$1 pid t n0 n1 commits
    mkdir -p "$d"
    pid=$(pgrep -x -u "$U" Hyprland | head -1)
    cp /run/user/1000/hypr/*/hyprland.log "$d/" 2>/dev/null
    cp /tmp/uwsm.log "$d/" 2>/dev/null
    cat /sys/kernel/debug/dri/0/state > "$d/dri-state.txt" 2>&1
    cat /sys/kernel/debug/dri/0/framebuffer > "$d/dri-fb.txt" 2>&1
    cat /sys/kernel/debug/dri/0/clients > "$d/dri-clients.txt" 2>&1
    if [ -n "$pid" ]; then
        for t in /proc/$pid/task/*; do
            echo "== $(basename "$t") $(cat "$t/comm") wchan=$(cat "$t/wchan")"
            cat "$t/stack" 2>/dev/null
        done > "$d/threads.txt"
        ls -l /proc/$pid/fd > "$d/fds.txt" 2>&1
    fi
    n0=$(irqs)
    dmesg -C
    echo 0x17 > /sys/module/drm/parameters/debug     # core (ioctls), driver, kms, atomic
    sleep 2
    echo 0 > /sys/module/drm/parameters/debug
    dmesg > "$d/drm-debug.txt"
    n1=$(irqs)
    commits=$(grep -c 'DRM_IOCTL_MODE_ATOMIC\|DRM_IOCTL_MODE_PAGE_FLIP\|DRM_IOCTL_MODE_SETCRTC' "$d/drm-debug.txt")
    say "$1: Hyprland pid ${pid:-none}, log $(wc -l < "$d/hyprland.log" 2>/dev/null || echo 0) lines," \
        "last: $(grep -v '^$' "$d/hyprland.log" 2>/dev/null | tail -1 | cut -c1-120)"
    say "$1: commits in 2 s $commits, vmwgfx irqs $(( ${n1:-0} - ${n0:-0} )), main thread $(cat /proc/$pid/wchan 2>/dev/null)"
}

stage() {   # stage NAME [VAR=VALUE...]
    local name=$1; shift
    : > "$ENVF"
    for kv in AQ_TRACE=1 HYPRLAND_TRACE=1 "$@"; do echo "export $kv" >> "$ENVF"; done
    chown "$U:" "$ENVF"
    if pgrep -x -u "$U" Hyprland > /dev/null; then
        loginctl terminate-user "$U"       # getty@tty1 autologs in again; .bash_profile starts uwsm
        sleep 5
    fi
    for _ in $(seq 1 90); do pgrep -x -u "$U" Hyprland > /dev/null && break; sleep 1; done
    sleep 60
    collect "$name"
}

say "start, writing $B"
stage default
stage no-atomic AQ_NO_ATOMIC=1
stage no-modifiers AQ_NO_MODIFIERS=1
: > "$ENVF"; chown "$U:" "$ENVF"    # plain session from here on (trace off)

# page flips with dumb buffers and nobody else on KMS
systemctl stop getty@tty1; loginctl terminate-user "$U"; sleep 5
conn=$(modetest -M vmwgfx -c 2>/dev/null | awk '/\tconnected\t/ {print $1; exit}')
mode=$(modetest -M vmwgfx -c 2>/dev/null | awk '/\tconnected\t/ {f=1; next} f && /^  #0 / {print $2; exit}')
timeout 15 modetest -M vmwgfx -s "$conn:$mode" -v > "$B/modetest.txt" 2>&1
say "modetest $conn:$mode: $(grep -i freq "$B/modetest.txt" | tail -3 | tr '\n' ' ')"
systemctl start getty@tty1
chmod -R a+rX /var/log/ohmarchy-boot
say "done"
