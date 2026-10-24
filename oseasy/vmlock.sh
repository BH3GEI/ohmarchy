#!/bin/sh
# The host's mutexes: /data/local/vm.lock (HMV: starting VMs, stopping 鸿融's main
# VM; only one VM at a time) and, with LOCK=screen, /data/local/screen.lock (the
# screen and foreground focus). A VM app with a window (Oseasy, 铠大师) takes both.
# Run from the workstation:
#   oseasy/vmlock.sh take OWNER HOURS   mkdir /data/local/vm.lock, write owner + times
#   oseasy/vmlock.sh show               print the owner file, or "free"
#   oseasy/vmlock.sh drop OWNER         rmdir, only if OWNER holds it
# The lock is held for at most 2 hours; when done, stop your VM, start 鸿融's main
# VM again from the 鸿融 app, check it reaches the Omarchy desktop, then drop.
set -eu
HOST=${OHDEV:-ohdev}
L=/data/local/${LOCK:-vm}.lock
rsh() { perl -e 'alarm shift; exec @ARGV' 60 ssh -o BatchMode=yes -o ConnectTimeout=15 "$HOST" sh -s; }

case "${1:-show}" in
take)
    owner=${2:?owner}; hours=${3:-2}
    now=$(date '+%Y-%m-%d %H:%M %Z'); until=$(date -v+"${hours}"H '+%Y-%m-%d %H:%M %Z' 2>/dev/null ||
        date -d "+$hours hours" '+%Y-%m-%d %H:%M %Z')
    rsh <<EOF
if mkdir $L 2>/dev/null; then
  printf '%s\nstart: %s\nexpected end: %s\n' '$owner' '$now' '$until' > $L/owner
  echo TAKEN; cat $L/owner
else
  echo BUSY; cat $L/owner 2>/dev/null
  exit 1
fi
EOF
    ;;
show)
    rsh <<EOF
[ -d $L ] && cat $L/owner 2>/dev/null || echo free
EOF
    ;;
drop)
    owner=${2:?owner}
    rsh <<EOF
[ -d $L ] || { echo "not held"; exit 0; }
head -1 $L/owner | grep -qxF '$owner' || { echo "held by someone else:"; cat $L/owner; exit 1; }
rm -f $L/owner && rmdir $L && echo DROPPED
EOF
    ;;
*) echo "usage: $0 take OWNER [HOURS] | show | drop OWNER" >&2; exit 2 ;;
esac
