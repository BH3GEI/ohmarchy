#!/bin/bash
# Run inside route I's guest (Omarchy on linux-aarch64 7.2.12, started by
# hongrong/pure/testvm.sh with TESTVM_GPU=1), as root:
#   ssh … 'sudo bash -s' < tools/ownvm/guest-setup.sh [check|docker|all]
# check:  kernel, EDID and connector modes, the virgl GPU (renderer string),
#         network (address, route, DNS, an HTTPS fetch)
# docker: install docker + compose, enable it, run hello-world and a small
#         compose project; prints every step's result
set -u
what=${1:-all}
hr() { printf '\n== %s\n' "$*"; }

check() {
  hr kernel; uname -r; cat /proc/cmdline
  hr "DRM connectors"
  for c in /sys/class/drm/card*-*; do
    [ -e "$c/status" ] || continue
    echo "${c##*/}: $(cat $c/status) modes: $(tr '\n' ' ' < $c/modes)"
    [ -s "$c/edid" ] && echo "  edid $(wc -c < $c/edid) bytes, name: $(strings $c/edid | head -1)"
  done
  dmesg | grep -iE 'edid|virtio_gpu|virgl|\[drm\]' | tail -12
  hr "GPU renderer"
  if command -v eglinfo >/dev/null; then
    EGL_PLATFORM=surfaceless eglinfo -B 2>/dev/null | grep -iE 'renderer|version string' | head -4
  else
    echo "eglinfo missing (mesa-utils)"
  fi
  hr network
  ip -4 addr show | grep -E 'inet |^[0-9]'; ip route
  getent hosts archlinux.org | head -1 || echo "DNS failed"
  curl -sS -o /dev/null -w 'https %{http_code} in %{time_total}s\n' https://archlinux.org/ || echo "HTTPS failed"
}

docker_setup() {
  hr "install docker"
  pacman -Sy --needed --noconfirm docker docker-compose docker-buildx mesa-utils 2>&1 | tail -3
  systemctl enable --now docker.service; systemctl is-active docker
  id yao >/dev/null 2>&1 && usermod -aG docker yao
  hr "docker info"
  docker info 2>&1 | grep -E 'Server Version|Storage Driver|Cgroup (Driver|Version)|Kernel Version|Operating System|Architecture'
  hr "hello-world"
  docker run --rm hello-world 2>&1 | grep -E 'Hello from Docker|error|Error' | head -3
  hr "compose"
  d=$(mktemp -d); cat > $d/compose.yaml <<'EOF'
services:
  web:
    image: nginx:alpine
    ports: ["8080:80"]
  probe:
    image: alpine
    depends_on: [web]
    command: sh -c "sleep 3; wget -qO- http://web/ | head -4"
EOF
  (cd $d && docker compose up -d web >/dev/null 2>&1
   curl -s -o /dev/null -w 'host port 8080: %{http_code}\n' --retry 5 --retry-connrefused http://127.0.0.1:8080/ || true
   docker compose run --rm probe > $d/probe.out 2>&1; rc=$?
   grep -E 'Welcome|error|Error' $d/probe.out | head -3; echo "compose probe exit $rc"
   docker compose down -v >/dev/null 2>&1)
  rm -rf $d
}

case $what in
  check) check ;;
  docker) docker_setup ;;
  all) check; docker_setup ;;
esac
