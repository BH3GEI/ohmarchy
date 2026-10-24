#!/bin/bash
# Docker bind mounts from route D's home directory: route I's VM shares the desktop
# user's home at the same path (virtiofs), so `docker run -v $PWD:/w` works as on
# a normal Linux. Run from the desktop session as the desktop user; needs the VM up
# with the share. Prints PASS/FAIL lines.
here=$(cd "$(dirname "$0")" && pwd)
user=${ARCH_USER:-builder}
cat <<SH | "$here/../lib/remote.sh" docker-mount chroot 600
su - $user -c '
d=\$HOME/ohm-docker-test; rm -rf \$d; mkdir -p \$d; cd \$d
echo hello-from-route-d > in.txt
out=\$(timeout 120 docker run --rm -v \$PWD:/w alpine sh -c "ls /w | head -3; cat /w/in.txt; touch /w/from-container" 2>&1)
echo "\$out" | sed "s/^/  /"
echo "\$out" | grep -q hello-from-route-d && echo "PASS run reads the bind mount" || echo "FAIL run cannot read the bind mount"
if [ -e from-container ]; then
  o=\$(stat -c %u from-container)
  [ "\$o" = "\$(id -u)" ] && echo "PASS file written in the container belongs to uid \$o here" || echo "FAIL file written in the container belongs to uid \$o, not \$(id -u)"
else
  echo "FAIL file written in the container is not here"
fi
printf "services:\n  w:\n    image: alpine\n    volumes: [\".:/w\"]\n    command: sh -c \"echo compose > /w/from-compose\"\n" > compose.yaml
timeout 120 docker compose up --abort-on-container-exit > compose.log 2>&1
[ "\$(cat from-compose 2>/dev/null)" = compose ] && echo "PASS compose writes through the bind mount" || { echo "FAIL compose:"; tail -3 compose.log; }
docker compose down > /dev/null 2>&1
ls -ln | sed "s/^/  /"
cd; rm -rf \$d' < /dev/null
SH
