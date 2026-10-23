#!/usr/bin/env bash
# kbisect.sh: drive a git bisect already started in the kbuild container:
# build the commit, copy it into the 鸿融 VM, `hrvm ktest`, mark it, repeat
# until git names the first bad commit. Progress goes to $LOG.
set -uo pipefail
export DOCKER_CONTEXT=${DOCKER_CONTEXT:-colima}
HRVM=${HRVM:-$(cd "$(dirname "$0")" && pwd)/../hongrong/hrvm}
GUEST=${HRVM_GUEST:-ohvm-arch}
LOG=${LOG:-/tmp/kbisect.log}
dx() { docker exec kbuild bash -c "$1"; }

ensure_default() {
  local i
  for i in 1 2 3; do
    ssh -o BatchMode=yes -o ConnectTimeout=8 $GUEST true 2>/dev/null && return 0
    "$HRVM" stop >/dev/null 2>&1; "$HRVM" start >/dev/null && "$HRVM" wait-ssh 300 >/dev/null && return 0
    sleep 30   # the link to the host drops now and then
  done
  return 1
}

while :; do
  c=$(dx 'git -C /work/linux rev-parse --short=12 HEAD')
  subj=$(dx 'git -C /work/linux log -1 --format=%s')
  echo "=== $(date +%H:%M) testing $c $subj" | tee -a "$LOG"
  if ! dx "/work/kernel-build.sh HEAD bs > /work/bs.log 2>&1 && test -s /work/out/bs.Image && gzip -kf /work/out/bs.Image"; then
    echo "build failed -> skip" | tee -a "$LOG"
    r=$(dx 'cd /work/linux && git bisect skip 2>&1'); echo "$r" | tail -3 | tee -a "$LOG"
    continue
  fi
  ensure_default || { echo "cannot reach default system" | tee -a "$LOG"; exit 1; }
  dx 'cat /work/out/bs.Image.gz' | ssh -o BatchMode=yes $GUEST "gunzip -c > /tmp/k.Image && echo $HRVM_SUDO_PW | sudo -S -p '' mv /tmp/k.Image /boot/ktest/bs.Image" || { echo "upload failed" | tee -a "$LOG"; exit 1; }
  res=$("$HRVM" ktest bs 2>&1 | grep -E "PASS|FAIL" | tail -1)
  echo "result: $res" | tee -a "$LOG"
  case $res in
    *PASS*) verdict=good ;; *FAIL*) verdict=bad ;;
    *) echo "no verdict, stopping" | tee -a "$LOG"; exit 1 ;;
  esac
  r=$(dx "cd /work/linux && git bisect $verdict 2>&1")
  echo "$r" | head -6 | tee -a "$LOG"
  if echo "$r" | grep -q "is the first bad commit"; then echo "DONE" | tee -a "$LOG"; exit 0; fi
done
