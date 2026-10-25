#!/bin/bash
# Route L helpers on the device (root over ssh). Only touches com.ohmarchy.webemu
# and /data/local/tmp/routel. Installing, launching and stopping the app need
# /data/local/screen.lock (see README); this script does not take it.
#   device.sh disk     copy /data/local/tmp/routel/arch32.img into the app sandbox (files/)
#   device.sh install  bm install /data/local/tmp/routel/webemu.hap
#   device.sh start    aa start the app
#   device.sh stop     aa force-stop the app
#   device.sh log      ROUTEL lines from hilog (the page's console)
#   device.sh mem      processes of the app and their memory (hidumper --mem)
set -e
HOST=${OHOS_HOST:-ohdev}
B=com.ohmarchy.webemu
T=/data/local/tmp/routel
dsh() { perl -e 'alarm shift; exec @ARGV' "${2:-120}" ssh -o ConnectTimeout=10 "$HOST" sh -s <<<"$1"; }
case $1 in
disk) dsh "
F=/data/app/el2/100/base/$B/files
[ -d \$F ] || { echo 'no sandbox: install the app first'; exit 1; }
cp $T/arch32.img \$F/arch32.img.tmp && mv \$F/arch32.img.tmp \$F/arch32.img
chown \$(stat -c %u:%g \$F) \$F/arch32.img; chmod 640 \$F/arch32.img
chcon \$(ls -dZ \$F | awk '{print \$1}') \$F/arch32.img 2>/dev/null || true
ls -laZ \$F" 600 ;;
install) dsh "bm install -r -p $T/webemu.hap 2>&1 | tail -1" ;;
start) dsh "aa start -a EntryAbility -b $B" ;;
stop) dsh "aa force-stop $B" ;;
log) dsh "hilog -x 2>/dev/null | grep ROUTEL | tail -${2:-40}" ;;
mem) dsh "
for p in \$(ps -A -o PID,NAME | grep -E '$B|render' | awk '{print \$1}'); do
  n=\$(timeout 2 cat /proc/\$p/cmdline 2>/dev/null | tr '\0' ' ' | cut -c1-80)
  case \$n in *webemu*|*render*) ;; *) continue ;; esac
  echo \"== \$p \$n\"
  hidumper --mem \$p 2>/dev/null | grep -E 'Total|PSS|RSS' | head -4
  grep -E 'VmRSS|VmHWM' /proc/\$p/status
done" ;;
*) sed -n 2,12p "$0"; exit 1 ;;
esac
