#!/usr/bin/env bash
# After the first-boot setup: make the guest boot straight into Hyprland, reboot, wait for it.
# usage: 60-desktop.sh USER PASSWORD
set -euo pipefail
. "$(dirname "$0")/config.sh"
U=$1 P=$2
RUN="python3 -I $ROOT/tools/serial/run.py"

until python3 -I "$ROOT/tools/serial/login.py" "$U" "$P"; do
    echo "no login yet (setup still creating the account?), retrying in 60 s"; sleep 60
done

echo "waiting for Omarchy's first-boot setup to finish..."
until [ "$($RUN 'pgrep -c -f omarchy-provision-owner || true' 300 | tr -dc 0-9)" = 0 ]; do sleep 120; done

# copy the guest script in short base64 lines and check it: the serial console drops input when busy
G="$ROOT/emulator/guest/desktop-autostart.sh"
sum=$(shasum -a 256 "$G" | cut -d' ' -f1)
$RUN 'rm -f /tmp/da.b64' 120
base64 < "$G" | fold -w 200 | while read -r chunk; do $RUN "printf '%s\\n' $chunk >> /tmp/da.b64" 120 >/dev/null; done
[ "$($RUN 'base64 -d /tmp/da.b64 > /tmp/da.sh; sha256sum /tmp/da.sh' 120 | cut -d' ' -f1 | tr -d '\r\n')" = "$sum" ] ||
    { echo "guest script arrived damaged" >&2; exit 1; }
$RUN "echo '$P' | sudo -S bash /tmp/da.sh $U" 600
$RUN "echo '$P' | sudo -S systemctl reboot" 60 || true

echo "rebooting; waiting for Hyprland on tty1..."
sleep 300
until python3 -I "$ROOT/tools/serial/login.py" "$U" "$P" &&
      [ "$($RUN 'pgrep -c -x Hyprland || true' 300 | tr -dc 0-9)" != 0 ]; do sleep 60; done
python3 -I "$ROOT/tools/vnc/vncshot.py" 127.0.0.1 15901 "$WORK/desktop.png"
echo "desktop up: $WORK/desktop.png"
