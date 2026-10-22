#!/usr/bin/env bash
# guest-put.sh LOCAL GUESTPATH: copy a file into the guest (initramfs or real root).
. "$(dirname "$0")/env.sh"
D=$(dirname "$0")
"$D/guest.sh" "B=busybox; [ -x /usr/local/lib/omarchy/busybox ] && B=/usr/local/lib/omarchy/busybox; (\$B tcpsvd -E -c 1 0 5002 sh -c 'cat > $2.part && mv $2.part $2' >/dev/null 2>&1 &); sleep 0.5" 20 >/dev/null
"$HDC" -t "$HDC_TARGET" file send "$1" /data/local/tmp/ohm.put >/dev/null
hs "netcat -w 5 -q 3 172.16.100.2 5002 < /data/local/tmp/ohm.put" >/dev/null
sleep 1
"$D/guest.sh" "sha256sum $2; kill \$(ps | grep 'tcpsvd -E -c 1 0 5002' | grep -v grep | awk '{print \$1}') 2>/dev/null" 20
sha256sum "$1"
