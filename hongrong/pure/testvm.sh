#!/system/bin/sh
# NOT YET TESTED (2026-10-24): first run pending.
# testvm.sh: run a disk image in a headless StratoVirt VM on the HarmonyOS host,
# outside the 鸿融 app, the way 鸿融 starts its VM (HMV acceleration, the same
# UEFI firmware, virtio-blk/net, vsock), with the serial console in a file.
# Run as root on the host. Only while the 鸿融 VM is shut down and the shared
# lock /data/local/vm.lock is held (see docs/hongrong-whole-os.md).
#   testvm.sh start DISK   start (DISK: raw image)
#   testvm.sh status       pid, vCPUs started (host VM log), serial tail
#   testvm.sh stop         ACPI power button via QMP, then wait; kill after 60 s
#   testvm.sh net-down     remove the tap device
D=${TESTVM_DIR:-/data/local/vmtest/run}
BR=${TESTVM_BRIDGE:-$(ls /sys/class/net | grep '^WVMBr' | head -1)}
TAP=hmvtest0
FW=/system/opt/virt_service/virtualized_hwf/stratovirt-uefi-linux
SV=/system/bin/virt_service/vm_engine/stratovirt/stratovirt
pidf=$D/stratovirt.pid
running() { [ -f $pidf ] && [ -d /proc/$(cat $pidf) ]; }
case "$1" in
start)
  disk=${2:?disk}
  pidof stratovirt >/dev/null && { echo "a StratoVirt VM is running (鸿融?); not starting"; exit 1; }
  [ -d /data/local/vm.lock ] || { echo "take /data/local/vm.lock first"; exit 1; }
  mkdir -p $D; rm -f $D/qmp.sock; : > $D/serial.log
  ip tuntap add dev $TAP mode tap 2>/dev/null
  [ -n "$BR" ] && ip link set $TAP master $BR
  ip link set $TAP up
  nohup $SV \
    -machine virt,gic-version=3,mem-share=on,accel=hmv \
    -cpu host,pmu=on,kvm-steal-time=on,bti=off -smp 6 -m 8192 \
    -drive file=$FW,if=pflash,unit=0,readonly=true \
    -drive id=disk0,file=$disk,format=raw,readonly=off,direct=on,aio=io_uring \
    -device virtio-blk-pci,drive=disk0,id=blk0,bus=pcie.0,addr=0x2.0x0 \
    -netdev tap,id=net0,ifname=$TAP \
    -device virtio-net-pci,netdev=net0,id=nic0,bus=pcie.0,mac=52:54:00:4d:76:01,addr=0x6.0x0 \
    -device ohos-vhost-vsock-pci,guest-cid=2001,id=vsock0,bus=pcie.0,addr=0xf \
    -qmp unix:$D/qmp.sock,server,nowait \
    -serial file,path=$D/serial.log \
    -D $D/stratovirt.log -disable-seccomp > $D/stdout.log 2>&1 &
  echo $! > $pidf; sleep 2
  running && echo "started pid $(cat $pidf)" || { echo "exited:"; tail -20 $D/stdout.log $D/stratovirt.log; exit 1; }
  ;;
status)
  running && echo "pid $(cat $pidf), up $(ps -o etime= -p $(cat $pidf))" || echo "not running"
  running && echo "vCPUs started: $(grep "\[$(cat $pidf)\]" $D/stratovirt.log 2>/dev/null | grep -c 'psci.rs.*is running')"
  tail -5 $D/serial.log 2>/dev/null
  ;;
stop)
  running || { echo "not running"; exit 0; }
  printf '{"execute":"qmp_capabilities"}\n{"execute":"system_powerdown"}\n' | toybox nc -U $D/qmp.sock >/dev/null 2>&1
  i=0; while running && [ $i -lt 60 ]; do sleep 2; i=$((i+2)); done
  running && { echo "no clean shutdown in 60 s; killing"; kill $(cat $pidf); sleep 2; }
  running || echo stopped
  ;;
net-down)
  ip link del $TAP 2>/dev/null; echo "tap removed"
  ;;
*) sed -n '2,13p' "$0"; exit 1 ;;
esac
