#!/bin/bash
# HarmonyOS screen off and on, ROUNDS times (C; default 20), remotely. The screen
# goes off through the screen-off timeout (power-shell timeout -o 3000: AWAKE, DIM,
# INACTIVE), not `power-shell suspend` (which suspends the whole machine and could
# leave it out of reach), and comes back with `power-shell wakeup`. HarmonyOS then
# shows its lock screen, which hides every app, so the test unlocks it like a user
# would (tools/ohdev/ohui types UNLOCK_PW into the password field; never stored).
# A round passes when the screen reached INACTIVE, the host answered meanwhile, and
# after unlocking the display app and Hyprland are the same processes and new
# frames reach the app's surface. Needs the display app open and the screen.
#   UNLOCK_PW=... [ROUNDS=20] tests/stability/screenoff.sh
here=$(cd "$(dirname "$0")" && pwd)
: "${UNLOCK_PW:?set UNLOCK_PW to the HarmonyOS lock screen password}"
OHUI="$here/../../tools/ohdev/ohui"
export OHUI_DIR=${OHUI_DIR:-/tmp/ohui}
h() { perl -e 'alarm 90; exec @ARGV' ssh -o ConnectTimeout=15 "${OHOS_HOST:-ohdev}" sh -s; }
start=$(h < "$here/screenoff/check.sh" | awk '{print $3, $4}')
[ -n "${start% *}" ] || { echo "display app not running"; exit 1; }
echo "start: app/hyprland $start"
ok=0
for i in $(seq "${ROUNDS:-20}"); do
    off=$(h < "$here/screenoff/off.sh"); sleep 2
    "$OHUI" text 720 801 "$UNLOCK_PW" > /dev/null 2>&1; sleep 0.5; "$OHUI" key 2054 > /dev/null 2>&1; sleep 3
    set -- $(h < "$here/screenoff/check.sh")
    if echo "$off" | grep -q INACTIVE && [ "$1" = AWAKE ] && [ "${2:-0}" -gt 0 ] && [ "$3 $4" = "$start" ]; then
        ok=$((ok + 1)); echo "round $i: ok: $off, back $1, new frames $2"
    else
        echo "round $i: FAIL: $off, back $1, new frames $2, app/hyprland $3 $4"
    fi
done
echo "summary $ok of ${ROUNDS:-20} rounds: off, back on, unlocked, desktop running and drawing"
