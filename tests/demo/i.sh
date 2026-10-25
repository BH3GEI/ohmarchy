#!/bin/bash
# Demo of route I (docs/demo.md): route I's VM as the Docker backend of the
# native desktop (route D). Start the VM and time it until dockerd answers,
# then from D's session as the desktop user: hello-world, a compose service
# with a bind mount (busybox httpd serving a page the container writes into
# D's home), the page over the network, the file's mode and owner in D
# (0644, the desktop user); stop. Prints PASS/FAIL lines.
# Needs the hypervisor free: ohmarchy-vm refuses to start while another
# StratoVirt VM (鸿融) runs.
here=$(cd "$(dirname "$0")" && pwd)
user=${ARCH_USER:-builder}
V=/data/local/kaidashi/bin/ohmarchy-vm

echo "== 1. start the VM (host, as root)"
"$here/../lib/remote.sh" demo-i-start host 300 <<SH || { echo "FAIL VM did not start"; exit 1; }
t=\$(date +%s)
sh $V start < /dev/null || exit 1
i=0; until sh $V ssh docker info < /dev/null > /dev/null 2>&1; do i=\$((i+1)); [ \$i -ge 120 ] && break; sleep 1; done
sh $V ssh docker info < /dev/null > /dev/null 2>&1 || { echo "FAIL dockerd does not answer"; exit 1; }
echo "PASS VM up and dockerd answering \$((\$(date +%s) - \$t)) s after start"
SH

echo "== 2. Docker from the desktop session (as $user)"
sed "s/@USER@/$user/" <<'SH' | "$here/../lib/remote.sh" demo-i-docker chroot 600
su - @USER@ -c '
docker context show
out=$(timeout 300 docker run --rm hello-world 2>&1)
echo "$out" | grep -q "Hello from Docker!" && echo "PASS hello-world" || { echo "FAIL hello-world:"; echo "$out" | tail -5; }
d=$HOME/ohm-demo-i; rm -rf $d; mkdir -p $d/www; cd $d
cat > compose.yaml <<EOF
services:
  web:
    image: busybox
    ports: ["8080:8080"]
    volumes: ["./www:/www"]
    command: sh -c "echo hello-from-compose > /www/index.html; exec httpd -f -p 8080 -h /www"
EOF
timeout 300 docker compose up -d > compose.log 2>&1 || { echo "FAIL compose up:"; tail -5 compose.log; }
page=; for i in $(seq 1 30); do page=$(curl -s --max-time 2 http://172.16.100.2:8080/); [ -n "$page" ] && break; sleep 1; done
[ "$page" = hello-from-compose ] && echo "PASS page from the container at http://172.16.100.2:8080/: $page" \
    || echo "FAIL no page on 172.16.100.2:8080 (got: $page)"
m=$(stat -c "%a %U" www/index.html 2>/dev/null)
echo "  www/index.html in D: $m"
[ "$m" = "644 $(id -un)" ] && echo "PASS the file the container wrote is 0644 and belongs to $(id -un)" \
    || echo "FAIL the file the container wrote is: $m"
docker compose down > /dev/null 2>&1
cd; rm -rf $d' < /dev/null
SH

echo "== 3. stop the VM (host, as root)"
"$here/../lib/remote.sh" demo-i-stop host 120 <<SH
sh $V stop < /dev/null && echo "PASS VM stopped"
SH
