#!/bin/bash
# 24 h soak (C): starts a detached loop on the HarmonyOS host that runs smoke.py in
# the desktop session every hour (HOURS, default 24) and appends its JSON line to
# $ARCH_BASE/soak.jsonl. Doesn't need the display app or the screen.
#   tests/stability/soak.sh start|status|stop
here=$(cd "$(dirname "$0")" && pwd)
B=${ARCH_BASE:-/data/local/archtest}
user=${ARCH_USER:-builder}
case "${1:-status}" in
start)
    {
        echo "B=$B; U=$user; HOURS=${HOURS:-24}"
        echo "cat > \$B/soak-smoke.py <<'END_OF_PY'"; cat "$here/smoke.py"; echo "END_OF_PY"
        cat <<'END_OF_HOST'
printf 'B=%s; U=%s; HOURS=%s\n' "$B" "$U" "$HOURS" > $B/soak-loop.sh
cat >> $B/soak-loop.sh <<'END_OF_LOOP'
echo $$ > $B/soak.pid
for h in $(seq 0 $HOURS); do
    P=$(cat $B/session.pid)
    mkdir -p /proc/$P/root/tmp/ohm-tests && cp $B/soak-smoke.py /proc/$P/root/tmp/ohm-tests/smoke.py
    nsenter -t $P -m -p -- chroot $B/arch /usr/bin/env -i PATH=/usr/bin /usr/bin/su - $U -c \
        'export XDG_RUNTIME_DIR=/run/user/$(id -u) WAYLAND_DISPLAY=wayland-1 DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/$(id -u)/bus
         export HYPRLAND_INSTANCE_SIGNATURE=$(hyprctl instances -j | python3 -c "import json,sys; print(json.load(sys.stdin)[0][\"instance\"])")
         python3 /tmp/ohm-tests/smoke.py' < /dev/null >> $B/soak.jsonl 2>> $B/soak.err \
        || echo "{\"time\": \"$(date "+%F %T")\", \"ok\": false, \"error\": \"smoke did not run\"}" >> $B/soak.jsonl
    [ $h -lt $HOURS ] && sleep 3600
done
rm -f $B/soak.pid
END_OF_LOOP
: > $B/soak.jsonl
nohup sh $B/soak-loop.sh < /dev/null > /dev/null 2>&1 &
sleep 60; cat $B/soak.jsonl
END_OF_HOST
    } | "$here/../lib/remote.sh" soak-start host 200 ;;
status)
    echo "p=\$(cat $B/soak.pid 2>/dev/null); [ -n \"\$p\" ] && kill -0 \$p 2>/dev/null && echo running || echo stopped; cat $B/soak.jsonl" \
        | "$here/../lib/remote.sh" soak-status host 60 ;;
stop)
    echo "kill \$(cat $B/soak.pid) 2>/dev/null; rm -f $B/soak.pid; echo stopped" | "$here/../lib/remote.sh" soak-stop host 60 ;;
esac
