#!/system/bin/sh
# ownvm.sh: route I's test slot on the HarmonyOS host, as root (docs/vm-own.md).
# Installed as /data/local/kaidashi/bin/ownvm.sh next to a copy of
# hongrong/pure/testvm.sh; every ssh from the Mac wraps it in perl alarm.
#   ownvm.sh start        testvm.sh start with TESTVM_GPU=1 on omarchy-own.img
#   ownvm.sh wait [SECS]  wait for the guest's sshd (default 240 s)
#   ownvm.sh g CMD...     run CMD in the guest as yao (stdin passed through)
#   ownvm.sh sudo-setup   once per disk: passwordless sudo for yao; the password
#                         comes only from the environment (OWNVM_PW), never a file
#   ownvm.sh stop         power the guest off, stop vhost-device-gpu, tap down
# The guest is reached from the host only: ohdev's sshd does not forward.
D=/data/local/kaidashi/ownvm
DISK=$D/omarchy-own.img
TV="/data/local/kaidashi/bin/testvm.sh"
export TESTVM_DIR=$D/run TESTVM_GPU=1
R=/proc/$(cat /data/local/archtest/session.pid)/root
LD="$R/usr/lib/ld-linux-aarch64.so.1 --library-path $R/usr/lib"
G() {
  $LD $R/usr/bin/ssh -i $D/hostkey -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
    -o LogLevel=ERROR -o ConnectTimeout=5 -o BatchMode=yes yao@172.16.100.2 "$@"
}
case "$1" in
start)
  pidof stratovirt >/dev/null && { echo "a StratoVirt VM is running; not starting"; exit 1; }
  sh $TV start $DISK
  ;;
wait)
  t=${2:-240}; i=0
  while [ $i -lt $t ]; do
    G true 2>/dev/null && { echo "guest sshd up after ${i}s"; exit 0; }
    sleep 5; i=$((i+5))
  done
  echo "no guest ssh in ${t}s"; sh $TV status; exit 1
  ;;
g) shift; G "$@" ;;
sudo-setup)
  [ -n "$OWNVM_PW" ] || { echo "set OWNVM_PW"; exit 1; }
  printf '%s\n' "$OWNVM_PW" | G 'sudo -S -p "" sh -c "echo \"yao ALL=(ALL) NOPASSWD: ALL\" > /etc/sudoers.d/zz-ownvm-test && chmod 440 /etc/sudoers.d/zz-ownvm-test" && sudo -n true && echo sudo ok'
  ;;
stop)
  sh $TV stop; sh $TV net-down
  ;;
*) sed -n '2,12p' "$0"; exit 1 ;;
esac
