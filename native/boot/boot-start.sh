#!/system/bin/sh
# Run once at boot by init (native/boot/ohmarchy-desktop.cfg): bring up route D's
# session, the GPU broker and the desktop, so opening "Omarchy (native)" is all a
# user does. Opening the app restarts the desktop for it (vtest-broker --on-app).
B=${ARCH_BASE:-/data/local/archtest}
exec > "$B/boot-start.log" 2>&1
sleep 20   # let the system settle after boot completed
"$B/bin/omarchy" desktop start
