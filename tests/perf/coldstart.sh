#!/bin/bash
# Desktop cold start (B): from `omarchy desktop start` with the desktop stopped
# (the Arch session itself stays up) until Hyprland answers, and until the Omarchy
# shell shows its bar and background. ROUNDS (default 3). Polled every ~0.1 s on the
# host's /proc/uptime, so the numbers are good to about 0.2 s. Does not involve the
# display app (desktop on the host GPU path), so the screen is not touched.
here=$(cd "$(dirname "$0")" && pwd)
B=${ARCH_BASE:-/data/local/archtest}
user=${ARCH_USER:-builder}
{
    echo "B=$B; U=$user; ROUNDS=${ROUNDS:-3}"
    cat <<'SH'
P=$(cat $B/session.pid)
up() { cut -d' ' -f1 /proc/uptime; }
layers() {
    nsenter -t $P -m -p -- chroot $B/arch /usr/bin/env -i PATH=/usr/bin /usr/bin/su - $U -c \
        'export XDG_RUNTIME_DIR=/run/user/$(id -u); i=$(ls -t $XDG_RUNTIME_DIR/hypr 2>/dev/null | head -1)
         [ -n "$i" ] && HYPRLAND_INSTANCE_SIGNATURE=$i hyprctl layers 2>/dev/null' < /dev/null
}
for r in $(seq $ROUNDS); do
    OHMARCHY_GPU=host sh $B/bin/omarchy desktop stop > /dev/null 2>&1
    sleep 3
    t0=$(up)
    OHMARCHY_GPU=host sh $B/bin/omarchy desktop start > /dev/null 2>&1 &
    th= tb= tg=
    while :; do
        l=$(layers); t=$(up)
        [ -z "$th" ] && echo "$l" | grep -q "Layer level" && th=$t
        [ -z "$tb" ] && echo "$l" | grep -q "namespace: omarchy-bar" && tb=$t
        [ -z "$tg" ] && echo "$l" | grep -q "namespace: omarchy-background" && tg=$t
        [ -n "$tb" ] && [ -n "$tg" ] && break
        awk -v a=$t0 -v b=$t 'BEGIN {exit !(b - a > 60)}' && break
        sleep 0.05
    done
    wait
    echo "round $r: $(awk -v a=$t0 -v h=${th:-0} -v b=${tb:-0} -v g=${tg:-0} 'BEGIN {printf "hyprland %.2f s, bar %.2f s, background %.2f s", h - a, b - a, g - a}')"
done
SH
} | "$here/../lib/remote.sh" perf-coldstart host 600
