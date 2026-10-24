#!/bin/bash
# Network loss and recovery (C), without touching the host's Wi-Fi (the ssh link to
# the host must survive): the session shares the host's network, so the outage is
# made narrow instead.
#   site  blackhole routes to one test site's addresses for OUTAGE seconds (default
#         30), then removed (also by a timer, should this script die); curl from the
#         session must fail during it and work again right after
#   dns   the session's /etc/resolv.conf (its own file; the host does not use it)
#         points to an unreachable server for OUTAGE seconds, then is restored
#   SITE  test site (default www.baidu.com). Switching Wi-Fi networks for real needs
#         someone at the machine.
here=$(cd "$(dirname "$0")" && pwd)
{
    echo "SITE=${SITE:-www.baidu.com}; OUTAGE=${OUTAGE:-30}; HOST=${OHOS_HOST:-ohdev}"
    cat <<'SH'
probe() {  # seconds until curl gets the page, or "down"
    curl -s -o /dev/null -m 5 -w "%{http_code} %{time_total}" "https://$SITE/" 2>/dev/null || echo "down"
}
ips=$(getent ahostsv4 "$SITE" | awk '{print $1}' | sort -u)
[ -n "$ips" ] || { echo "FAIL site: cannot resolve $SITE"; exit 1; }
# never cut the addresses the ssh link uses
for ip in $ips; do
    ss -tn | awk '{print $5}' | grep -q "^$ip:" && { echo "FAIL site: $SITE ($ip) carries a live connection; pick another SITE"; exit 1; }
done
echo "INFO site: $SITE = $(echo $ips | tr '\n' ' ')"
echo "INFO before: $(probe)"
for ip in $ips; do ip route add blackhole "$ip/32"; done
( sleep $((OUTAGE + 15)); for ip in $ips; do ip route del blackhole "$ip/32" 2>/dev/null; done ) &
sleep 2
during=$(probe)
sleep $((OUTAGE - 2))
for ip in $ips; do ip route del blackhole "$ip/32"; done
t0=$(date +%s.%N); after=down
for i in $(seq 20); do after=$(probe); [ "$after" != down ] && break; sleep 1; done
t1=$(date +%s.%N)
echo "INFO site during: $during; after: $after"
[ "$during" = down ] && [ "$after" != down ] && echo "PASS site: unreachable during the outage, back $(awk -v a=$t0 -v b=$t1 'BEGIN {printf "%.1f", b - a}') s after it ended" \
    || echo "FAIL site: during '$during', after '$after'"
ip route show | grep -q blackhole && echo "FAIL site: a blackhole route is left" || true

cp /etc/resolv.conf /tmp/resolv.conf.ohm
( sleep $((OUTAGE + 15)); [ -f /tmp/resolv.conf.ohm ] && cp /tmp/resolv.conf.ohm /etc/resolv.conf ) &
echo "nameserver 192.0.2.1" > /etc/resolv.conf   # TEST-NET-1: nothing answers
sleep 2
during=$(curl -s -o /dev/null -m 8 -w "%{http_code}" "https://$SITE/" 2>/dev/null || echo down)
sleep $((OUTAGE - 2))
cp /tmp/resolv.conf.ohm /etc/resolv.conf && rm -f /tmp/resolv.conf.ohm
t0=$(date +%s.%N); after=down
for i in $(seq 20); do after=$(probe); [ "$after" != down ] && break; sleep 1; done
t1=$(date +%s.%N)
echo "INFO dns during: $during; after: $after"
[ "$during" = down ] && [ "$after" != down ] && echo "PASS dns: names fail during the outage, back $(awk -v a=$t0 -v b=$t1 'BEGIN {printf "%.1f", b - a}') s after it ended" \
    || echo "FAIL dns: during '$during', after '$after'"
SH
} | "$here/../lib/remote.sh" network chroot 300
