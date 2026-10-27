# demo.sh: the Docker test build, shown in three steps (run on ohdev as root:
# ssh ohdev sh -s < demo.sh). Test build, not real isolation: README.md.
# Needs: start.sh's tree, alpine:3.22 and nginx:alpine pulled, tools/lprobe.
S=/data/local/ohm-docker-test; H=$(dirname "$0")
say() { printf '\n\033[1;35m## %s\033[0m\n' "$*"; }
run() { printf '\033[1;32m$\033[0m %s\n' "$*"; }
if ! { [ -s $S/dockerd.pid ] && kill -0 $(cat $S/dockerd.pid) 2>/dev/null; }; then
  NET=pasta sh $S/start.sh > $S/log/demo-start.txt 2>&1 || { echo "start failed: $S/log/demo-start.txt"; exit 1; }
fi
p=$(cat $S/dockerd.pid)
docker() { timeout 120 nsenter -t $p -m -- /usr/bin/docker -H unix:///run/docker.sock "$@" 2>&1; }

say "1. hello-world in the sandbox (Docker test build on the HongMeng kernel, no VM)"
run "docker run --rm --cap-drop MKNOD --network none hello-world"
docker run --rm --cap-drop MKNOD --network none hello-world | sed -n 2,3p

say "2. nginx in the sandbox's own network, reached from another container"
run "docker run -d --name web --cap-drop MKNOD --network host nginx:alpine"
docker rm -f web > /dev/null 2>&1
docker run -d --name web --cap-drop MKNOD --network host nginx:alpine nginx -g 'daemon off; master_process off;' | cut -c1-12
sleep 3
run "docker run --rm --cap-drop MKNOD --network host alpine:3.22 wget -qO- http://127.0.0.1/"
docker run --rm --cap-drop MKNOD --network host alpine:3.22 wget -q -T 5 -O- http://127.0.0.1/ | grep -o '<title>.*</title>'
docker rm -f web > /dev/null

say "3. a service only on the host's 127.0.0.1: the host reaches it, a container does not"
$S/tools/lprobe > $S/log/lprobe.out 2>&1 & L=$!; sleep 1
run "curl telnet://127.0.0.1:18081      # on the host"
curl -s --max-time 3 telnet://127.0.0.1:18081 < /dev/null | head -1
run "docker run --rm --cap-drop MKNOD --network host alpine:3.22 nc -w 3 127.0.0.1 18081"
docker run --rm --cap-drop MKNOD --network host alpine:3.22 sh -c 'nc -w 3 127.0.0.1 18081 < /dev/null || echo "can'"'"'t connect (nc exit $?)"'
kill $L 2>/dev/null; wait $L 2>/dev/null

say "afterwards: dockerd stopped, no sandbox mounts left on the host"
[ "$KEEP" = 1 ] || sh $S/stop.sh | grep -E '^stopped|host mounts'
