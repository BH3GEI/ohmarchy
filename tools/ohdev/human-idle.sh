#!/bin/bash
# Is someone at the HarmonyOS machine? Seconds since the last input from a physical
# device (keyboard, touchpad, mouse, touch screen): MultimodalInput's libinput event
# dump (hidumper -s 3101 -a -e). Input injected with uitest (tools/ohdev/ohui) does
# not go through libinput, so our own test input does not count.
#   human-idle.sh              print "<seconds> idle (last physical input <time>)"
#   human-idle.sh wait [MIN]   check every minute until nobody has touched the
#                              machine for MIN minutes (default 10), then return
#   human-idle.sh check [SEC]  exit 0 if no physical input in the last SEC seconds
#                              (default 60), 1 if there was (stop and give way)
#   OHOS_HOST  ssh host (default ohdev)
idle() {
    perl -e 'alarm 60; exec @ARGV' ssh -o ConnectTimeout=15 "${OHOS_HOST:-ohdev}" \
        'date +%F_%T; hidumper -s 3101 -a -e 2>/dev/null | cat | grep "^{20" | tail -1 | cut -c2-24' |
        python3 -c '
import sys, datetime
lines = [l.strip() for l in sys.stdin if l.strip()]
now = datetime.datetime.strptime(lines[0], "%Y-%m-%d_%H:%M:%S")
if len(lines) < 2:
    print("999999 no physical input recorded"); sys.exit()
last = lines[1].rstrip(" ,")
t = datetime.datetime.strptime(last.split(".")[0], "%Y-%m-%d %H:%M:%S")
print(f"{max(0, int((now - t).total_seconds()))} idle (last physical input {last})")'
}

case "${1:-}" in
"") idle ;;
check)
    s=$(idle | cut -d' ' -f1)
    [ -n "$s" ] && [ "$s" -ge "${2:-60}" ] ;;
wait)
    need=$(( ${2:-10} * 60 ))
    while :; do
        r=$(idle); s=${r%% *}
        echo "$(date +%H:%M:%S) $r"
        [ -n "$s" ] && [ "$s" -ge "$need" ] && break
        sleep 60
    done ;;
*) sed -n '2,13p' "$0"; exit 2 ;;
esac
