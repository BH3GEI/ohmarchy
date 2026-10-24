#!/system/bin/sh
# Collect route D's logs and state into one archive for a bug report (run as root
# on the HarmonyOS host): sh collect-logs.sh [OUT_DIR]   (default /data/local/tmp)
# Contains no passwords; the desktop user's files are not included beyond its logs.
B=${ARCH_BASE:-$(cd "$(dirname "$0")" && pwd)}
R=$B/arch
user=${ARCH_USER:-builder}
out=${1:-/data/local/tmp}
d=$out/ohmarchy-logs-$(date +%Y%m%d-%H%M%S)
mkdir -p "$d/host" "$d/session"

# host side
for f in session.log vtest.log boot-start.log soak.jsonl soak.err; do
    [ -f "$B/$f" ] && tail -c 2000000 "$B/$f" > "$d/host/$f"
done
{ uname -a; getprop const.product.software.version 2>/dev/null; date; uptime; } > "$d/host/system.txt" 2>&1
ps -ef > "$d/host/ps.txt" 2>&1
sh "$B/arch.sh" status > "$d/host/arch-status.txt" 2>&1
hilog -x 2>/dev/null | grep -E "com.ohmarchy.display|ohdisp" | tail -5000 > "$d/host/hilog-display-app.txt"
bm dump -n com.ohmarchy.display 2>/dev/null | grep -E '"versionName"|"versionCode"' > "$d/host/app-version.txt"
cat /proc/meminfo > "$d/host/meminfo.txt"
ls /data/log/faultlog/faultlogger 2>/dev/null | grep -iE "ohmarchy|display" > "$d/host/faultlog-list.txt"

# session side (only if it is running)
P=$(cat "$B/session.pid" 2>/dev/null)
if [ -n "$P" ] && kill -0 "$P" 2>/dev/null; then
    S=/proc/$P/root
    uid=$(grep "^$user:" "$S/etc/passwd" | cut -d: -f3)
    for f in "$S/run/user/$uid"/*.log; do
        [ -f "$f" ] && tail -c 2000000 "$f" > "$d/session/$(basename "$f")"
    done
    for f in "$S/run/user/$uid"/hypr/*/hyprland.log; do
        [ -f "$f" ] && tail -c 2000000 "$f" > "$d/session/hyprland-$(basename "$(dirname "$f")").log"
    done
    nsenter -t "$P" -m -p -- chroot "$R" /usr/bin/env -i PATH=/usr/bin /bin/sh -c '
        ps -eo user,pid,ppid,rss,etime,args --sort=-rss | head -80
        echo; pacman -Q | wc -l; pacman -Q hyprland aquamarine mesa pipewire omarchy 2>&1
        echo; df -h / /tmp 2>&1
        echo; cat /etc/sudoers.d/10-wheel 2>&1' > "$d/session/state.txt" 2>&1
    cp "$S/tmp/ohm-tests/"*.jsonl "$d/session/" 2>/dev/null
fi

tar -czf "$d.tar.gz" -C "$out" "$(basename "$d")" && rm -rf "$d"
echo "$d.tar.gz ($(du -h "$d.tar.gz" | cut -f1))"
