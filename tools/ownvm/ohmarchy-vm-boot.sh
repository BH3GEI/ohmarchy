#!/system/bin/sh
# Started by init after boot (ohmarchy-vm.cfg, optional): waits for route D's
# session (its ssh client is used to reach the guest), then starts the VM.
# Logs to /data/local/kaidashi/ownvm/svc/boot.log.
L=/data/local/kaidashi/ownvm/svc; mkdir -p $L; exec >> $L/boot.log 2>&1
echo "== $(toybox date '+%F %T %z') boot start"
i=0; while [ $i -lt 300 ]; do
  [ -d /proc/$(cat /data/local/archtest/session.pid 2>/dev/null)/root/usr/bin ] && break
  sleep 5; i=$((i+5))
done
sh /data/local/kaidashi/bin/ohmarchy-vm start
