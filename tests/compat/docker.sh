#!/bin/bash
# Docker from route D's desktop session: the HongMeng kernel cannot run containers,
# so the docker CLI uses dockerd in route I's VM over ssh (context "ohmarchy",
# docs/vm-own.md). Needs the VM up (ohmarchy-vm start). Prints PASS/FAIL lines.
here=$(cd "$(dirname "$0")" && pwd)
user=${ARCH_USER:-builder}
cat <<SH | "$here/../lib/remote.sh" docker chroot 600
su - $user -c '
docker context show
t=\$(date +%s.%N)
out=\$(timeout 300 docker run --rm hello-world 2>&1)
e=\$(date +%s.%N)
echo "\$out" | grep -q "Hello from Docker!" && echo "PASS hello-world: \$(awk -v a=\$t -v b=\$e "BEGIN {printf \"%.1f\", b - a}") s" \
    || { echo "FAIL hello-world:"; echo "\$out" | tail -5; }
d=\$(mktemp -d); cd \$d
printf "services:\n  hi:\n    image: alpine\n    command: echo compose-ok-from-route-d\n" > compose.yaml
out=\$(timeout 300 docker compose up --abort-on-container-exit 2>&1)
echo "\$out" | grep -q compose-ok-from-route-d && echo "PASS compose: service ran" \
    || { echo "FAIL compose:"; echo "\$out" | tail -5; }
docker compose down > /dev/null 2>&1; cd /; rm -rf \$d' < /dev/null
SH
