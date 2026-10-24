#!/bin/bash
# remote.sh NAME [chroot|host] [timeout-s] < script
# Run a script on the HarmonyOS host and print its output. It is uploaded, run
# detached (inside the Arch session as root with "chroot", plain sh with "host"),
# and polled, with a hard deadline on every ssh: the link to the host sometimes
# stalls where ssh's own timeouts do not apply.
#   OHOS_HOST  ssh host with a root shell on the HarmonyOS PC (default: ohdev)
#   ARCH_BASE  route D's base directory on the host (default: /data/local/archtest)
name=$1; mode=${2:-chroot}; tmo=${3:-600}
HOST=${OHOS_HOST:-ohdev}
B=${ARCH_BASE:-/data/local/archtest}
P=$B/probe
r() { perl -e 'alarm shift; exec @ARGV' "$1" ssh -o ConnectTimeout=15 -o ServerAliveInterval=10 \
        -o ServerAliveCountMax=3 "$HOST" "${@:2}"; }
body=$(cat)
for i in 1 2 3; do printf '%s\n' "$body" | r 60 "mkdir -p $P && cat > $P/$name.sh" && break; sleep 3; done
if [ "$mode" = chroot ]; then run="cd $B && sh arch.sh run probe/$name.sh root"; else run="sh $P/$name.sh"; fi
r 30 sh -s <<END_OF_START
rm -f $P/$name.out $P/$name.done
( ( $run ) < /dev/null > $P/$name.out 2>&1; echo \$? > $P/$name.done ) > /dev/null 2>&1 &
END_OF_START
start=$(date +%s); rc=
while :; do
    rc=$(r 20 "cat $P/$name.done 2>/dev/null" 2>/dev/null)
    [ -n "$rc" ] && break
    [ $(( $(date +%s) - start )) -gt "$tmo" ] && { echo "[remote: $name still running after ${tmo}s]"; break; }
    sleep 5
done
r 120 "cat $P/$name.out" 2>/dev/null
[ -n "$rc" ] && exit "$rc"
exit 124
