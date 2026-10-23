#!/usr/bin/env bash
# Run as root inside the Omarchy guest: boot straight into the Hyprland session.
# usage: desktop-autostart.sh USER
#
# Under TCG, SDDM kills its Wayland greeter about 21 s after each start and loops
# (sddm-helper exited with 2). Instead: no SDDM, tty1 autologin, and the user's
# login shell on tty1 execs the same uwsm command as Omarchy's omarchy.desktop.
# Idle screensaver/lock are switched off: on a remote VNC screen they only get in the way.
set -euo pipefail
U=$1
H=$(getent passwd "$U" | cut -d: -f6)

systemctl disable sddm.service

mkdir -p /etc/systemd/system/getty@tty1.service.d
cat > /etc/systemd/system/getty@tty1.service.d/autologin.conf <<EOF
[Service]
ExecStart=
ExecStart=-/usr/bin/agetty -o '-p -f -- \\\\u' --noclear --autologin $U %I \$TERM
EOF

P="$H/.bash_profile"
touch "$P"
if ! grep -q 'ohmarchy-route-f' "$P"; then
    cat >> "$P" <<'EOF'
# ohmarchy-route-f: start Omarchy's Hyprland session on tty1 (SDDM is too slow under TCG)
if [ -z "${WAYLAND_DISPLAY:-}" ] && [ "$(tty)" = /dev/tty1 ]; then
    exec uwsm start -g -1 -e -D Hyprland hyprland.desktop > /tmp/uwsm.log 2>&1
fi
EOF
fi
chown "$U:" "$P"

# Omarchy 4 idles from its Quickshell shell (screensaver 150 s, lock 300 s), which under TCG
# locks the desktop before it has finished starting. Its own "stay awake" switch
# (omarchy-toggle-idle stay-awake) is this state file.
install -d -o "$U" -g "$(id -gn "$U")" "$H/.local/state/omarchy/indicators"
touch "$H/.local/state/omarchy/indicators/stay-awake"
chown -R "$U:" "$H/.local/state/omarchy"
echo "done: reboot to start the desktop on tty1"
