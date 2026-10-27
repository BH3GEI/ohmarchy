#!/system/bin/sh
# Run at boot by init (/system/etc/init/ohm-sandboxd.cfg, the sandbox's only file
# outside /data): once boot has completed (bm needs the system's services), start
# the helper the app talks to. Linux itself starts only when the app opens.
S=/data/local/ohm-sandbox
exec > "$S/boot-serve.log" 2>&1
echo "boot-serve $(date) uptime $(cut -d' ' -f1 /proc/uptime)"
i=0
until [ "$(param get bootevent.boot.completed 2>/dev/null | tr -d ' \r\n')" = true ] || [ $i -ge 600 ]; do
    sleep 1; i=$((i + 1))
done
sleep 10
# serve looks up the app's uid with bm; early in boot the bundle service may not answer
# yet: try every 5 s for up to 3 minutes
i=0
until sh "$S/bin/ohm-sandbox" serve; do
    [ $i -ge 36 ] && { echo "gave up after $((i * 5)) s"; exit 1; }
    sleep 5; i=$((i + 1))
done
echo "serving at uptime $(cut -d' ' -f1 /proc/uptime)"
