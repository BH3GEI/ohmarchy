# netcheck.sh: is the network isolation real? netns of host, dockerd, pasta and containers;
# a real listener on the host's 127.0.0.1:18557 (tools/lprobe18557: lprobe.go on that port,
# 90 s), tried from containers on 127.0.0.1, the gateway and the host's LAN address
S=/data/local/ohm-docker-test
NET=pasta sh $S/start.sh > $S/log/netcheck-start.txt 2>&1; grep -E 'network:' $S/log/netcheck-start.txt
p=$(cat $S/dockerd.pid)
d() { timeout 120 nsenter -t $p -m -- /usr/bin/docker -H unix:///run/docker.sock "$@" 2>&1; }
echo "== 1. netns"
echo "host pid 1:          $(readlink /proc/1/ns/net)"
echo "host (this shell):   $(readlink /proc/self/ns/net)"
echo "dockerd ($p):     $(readlink /proc/$p/ns/net)"
echo "pasta:               $(readlink /proc/$(cat $S/pasta.pid)/ns/net)"
for n in host none; do
  echo "container --network $n: $(d run --rm --cap-drop MKNOD --network $n alpine:3.22 readlink /proc/self/ns/net)"
done
d run -d --name nchk --cap-drop MKNOD --network host alpine:3.22 sleep 60 > /dev/null
cp=$(d inspect -f '{{.State.Pid}}' nchk); echo "container pid $cp as seen from the host: $(readlink /proc/$cp/ns/net)"
d rm -f nchk > /dev/null
echo "== 2. a real listener on the host's 127.0.0.1:18557"
$S/tools/lprobe18557 > $S/log/lprobe18557.out 2>&1 & L=$!; sleep 1
grep -i ':487D ' /proc/net/tcp | awk '{print "host /proc/net/tcp:", $2, "state", $4}'
echo "host curl 127.0.0.1:18557: $(curl -s --max-time 3 telnet://127.0.0.1:18557 < /dev/null | head -1) (rc $?)"
gw=$(ip route show table all | grep -m1 '^default via ' | awk '{print $3}')
lan=$(ip -4 addr show wlan0 | awk '/inet /{print $2}' | cut -d/ -f1)
echo "host gateway $gw, host wlan0 $lan"
for a in 127.0.0.1 $gw $lan; do
  for n in host none; do
    r=$(d run --rm --cap-drop MKNOD --network $n alpine:3.22 sh -c "wget -q -T 4 -O- http://$a:18557/ 2>&1; echo rc=\$?")
    echo "container --network $n -> $a:18557: $(echo $r | tr '\n' ' ')"
  done
done
sleep 1; kill $L 2>/dev/null; wait $L 2>/dev/null
echo "== lprobe accepted (every connection that reached the host listener):"; cat $S/log/lprobe18557.out
echo "== 3. outbound still works: $(d run --rm --cap-drop MKNOD --network host alpine:3.22 sh -c 'wget -q -T 8 -O- https://mirrors.tuna.tsinghua.edu.cn/alpine/latest-stable/releases/aarch64/latest-releases.yaml | sed -n 3p')"
sh $S/stop.sh | grep -E '^stopped|host mounts'
