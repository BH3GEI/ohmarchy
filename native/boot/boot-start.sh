#!/system/bin/sh
# Run at boot by init (native/boot/ohmarchy-desktop.cfg, start-mode boot like the
# ssh service): bring up route D's session, the GPU broker and the desktop, so
# opening "Omarchy (native)" is all a user does. Opening the app restarts the
# desktop for it (vtest-broker --on-app).
# The service starts early, so wait here for boot to complete: a cfg job on
# "bootevent.boot.completed=true" never fired for this overlay cfg (reboot test
# 2026-10-26), while the ssh service, started in boot mode, came up every time.
B=${ARCH_BASE:-/data/local/archtest}
exec > "$B/boot-start.log" 2>&1
echo "boot-start $(date) uptime $(cut -d' ' -f1 /proc/uptime)"
i=0
until [ "$(param get bootevent.boot.completed 2>/dev/null | tr -d ' \r\n')" = true ] || [ $i -ge 600 ]; do
    sleep 1; i=$((i + 1))
done
echo "boot completed after ${i}s of waiting"
sleep 20   # let the system settle
"$B/bin/omarchy" desktop start
echo "desktop start exit $? at uptime $(cut -d' ' -f1 /proc/uptime)"
