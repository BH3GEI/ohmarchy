#!/usr/bin/env bash
# guest-get.sh GUESTPATH LOCAL: copy a file out of the guest.
. "$(dirname "$0")/env.sh"
D=$(dirname "$0")
"$D/guest.sh" "B=busybox; [ -x /usr/local/lib/omarchy/busybox ] && B=/usr/local/lib/omarchy/busybox; (\$B tcpsvd -E -c 1 0 5003 sh -c 'cat $1' >/dev/null 2>&1 &); sleep 0.5; sha256sum $1" 20
hs "netcat -w 5 -q 2 172.16.100.2 5003 > /data/local/tmp/ohm.get < /dev/null" >/dev/null
"$HDC" -t "$HDC_TARGET" file recv /data/local/tmp/ohm.get "$2" >/dev/null
sha256sum "$2"
"$D/guest.sh" "kill \$(ps | grep 'tcpsvd -E -c 1 0 5003' | grep -v grep | awk '{print \$1}') 2>/dev/null" 10 >/dev/null
