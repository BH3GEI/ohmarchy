#!/system/bin/sh
# Used on 2026-10-24 for omarchy-pure.img (cold boot + 3 warm reboots). QMP stop
# did not trigger a guest shutdown yet: power off from inside the guest.
# testvm.sh: run a disk image in a headless StratoVirt VM on the HarmonyOS host,
# outside the 鸿融 app, the way 鸿融 starts its VM (HMV acceleration, the same
# UEFI firmware, virtio-blk/net, vsock), with the serial console in a file.
# The serial console is a unix socket ($D/serial.sock) to log in through.
# Run as root on the host, only while no other VM runs (HMV runs one at a time).
#   testvm.sh start DISK   start (DISK: raw image)
#   testvm.sh status       pid, vCPUs started (host VM log), serial tail
#   testvm.sh stop         ACPI power button via QMP, then wait; kill after 60 s
#   testvm.sh net-down     remove the tap device and its NAT rule
# Environment: TESTVM_DIR (run files), TESTVM_BRIDGE, and for route I
# (docs/vm-own.md) TESTVM_GPU=1: 鸿融's virgl GPU, i.e. vhost-device-gpu
# (virglrenderer) on $D/gpu.sock and vhost-user-gpu-pci with virgl=true;
# TESTVM_GPU_LIBPATH: LD_LIBRARY_PATH for vhost-device-gpu (to substitute the
# libhwf_kits.z.so it dlopens for its window); TESTVM_DISPLAY=ohui adds
# `-display ohui` with its sockets in $D/ohui.
# The NIC carries rx/tx iothreads as 鸿融's and Oseasy's do: without them the
# guest sends but never receives (seen in this script and in 铠大师's install
# session; route I, docs/vm-own.md).
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
  mkdir -p $D; rm -f $D/qmp.sock $D/serial.sock
  ip tuntap add dev $TAP mode tap 2>/dev/null
  [ -n "$BR" ] && ip link set $TAP master $BR
  ip link set $TAP up
  # 鸿融 removes its bridge when its VM stops: then the host side of the
  # guest's 172.16.100.0/24 is the tap itself
  if [ -z "$BR" ]; then
    ip addr add 172.16.100.1/24 dev $TAP 2>/dev/null
    # outbound NAT for the guest (鸿融's own rules go away with its VM)
    iptables -t nat -C POSTROUTING -s 172.16.100.0/24 ! -o $TAP -j MASQUERADE 2>/dev/null ||
      iptables -t nat -A POSTROUTING -s 172.16.100.0/24 ! -o $TAP -j MASQUERADE
    # the host's policy routing sends 172.16.100.0/24 out wlan0 (rule 16000:
    # fwmark 0 -> table 2009) and forwarded guest packets find no default
    # route in main: route the subnet to the tap, and the guest's traffic
    # through table 2009 (the Wi-Fi default route)
    ip rule show pref 10500 | grep -q . || ip rule add to 172.16.100.0/24 lookup main pref 10500
    ip rule show pref 10501 | grep -q . || ip rule add iif $TAP lookup 2009 pref 10501
  fi
  gpu=
  if [ "${TESTVM_GPU:-0}" = 1 ]; then
    rm -f $D/gpu.sock
    LD_LIBRARY_PATH=${TESTVM_GPU_LIBPATH:-} VHOST_LOG_PATH=$D/vhost-device-gpu.log \
      nohup /system/bin/virt_service/vm_engine/stratovirt/vhost-device-gpu \
      --socket-path $D/gpu.sock --gpu-mode virglrenderer --use-gles false \
      > $D/vhost-device-gpu.out 2>&1 &
    echo $! > $D/vhost-device-gpu.pid
    i=0; while [ ! -S $D/gpu.sock ] && [ $i -lt 10 ]; do sleep 1; i=$((i+1)); done
    [ -S $D/gpu.sock ] || { echo "vhost-device-gpu did not create its socket:"; tail -5 $D/vhost-device-gpu.out; exit 1; }
    gpu="-chardev socket,id=vhost-user-gpu,path=$D/gpu.sock
      -device vhost-user-gpu-pci,id=vhost-user-gpu-id,bus=pcie.0,addr=0x4.0x0,xres=2160,yres=1440,chardev=vhost-user-gpu,virgl=true"
    if [ "${TESTVM_DISPLAY:-}" = ohui ]; then
      mkdir -p $D/ohui
      gpu="$gpu -object iothread,id=ohui-iothread -display ohui,iothread=ohui-iothread,socks-path=$D/ohui"
    fi
  fi
  nohup $SV \
    -machine virt,gic-version=3,mem-share=on,accel=hmv \
    -cpu host,pmu=on,kvm-steal-time=on,bti=off -smp 6 -m 8192 \
    -drive file=$FW,if=pflash,unit=0,readonly=true \
    -drive id=disk0,file=$disk,format=raw,readonly=off,direct=on,aio=io_uring \
    -device virtio-blk-pci,drive=disk0,id=blk0,bus=pcie.0,addr=0x2.0x0 \
    -netdev tap,id=net0,ifname=$TAP \
    -object iothread,id=rx-iothread0 -object iothread,id=tx-iothread0 \
    -device virtio-net-pci,netdev=net0,id=nic0,bus=pcie.0,mac=52:54:00:4d:76:01,addr=0x6.0x0,rx-iothread=rx-iothread0,tx-iothread=tx-iothread0 \
    $gpu \
    -device ohos-vhost-vsock-pci,guest-cid=2001,id=vsock0,bus=pcie.0,addr=0xf \
    -qmp unix:$D/qmp.sock,server,nowait \
    -serial socket,path=$D/serial.sock,server,nowait \
    -D $D/stratovirt.log -disable-seccomp > $D/stdout.log 2>&1 &
  echo $! > $pidf; sleep 2
  running && echo "started pid $(cat $pidf)" || { echo "exited:"; tail -20 $D/stdout.log $D/stratovirt.log; exit 1; }
  ;;
status)
  running && echo "pid $(cat $pidf), up $(ps -o etime= -p $(cat $pidf))" || echo "not running"
  running && echo "vCPUs started: $(grep "\[$(cat $pidf)\]" $D/stratovirt.log 2>/dev/null | grep -c 'psci.rs.*is running')"
  # serial console: toybox nc -U $D/serial.sock (one client at a time)
  ;;
stop)
  running || { echo "not running"; exit 0; }
  # one command per write: StratoVirt's QMP parser rejects two JSON objects at once
  { sleep 1; echo '{"execute":"qmp_capabilities"}'; sleep 1; echo '{"execute":"system_powerdown"}'; sleep 2; } |
    timeout 10 toybox nc -U $D/qmp.sock >/dev/null 2>&1
  i=0; while running && [ $i -lt 60 ]; do sleep 2; i=$((i+2)); done
  running && { echo "no clean shutdown in 60 s; killing"; kill $(cat $pidf); sleep 2; }
  running || echo stopped
  [ -f $D/vhost-device-gpu.pid ] && kill $(cat $D/vhost-device-gpu.pid) 2>/dev/null && rm -f $D/vhost-device-gpu.pid
  ;;
net-down)
  iptables -t nat -D POSTROUTING -s 172.16.100.0/24 ! -o $TAP -j MASQUERADE 2>/dev/null
  ip rule del pref 10500 2>/dev/null; ip rule del pref 10501 2>/dev/null
  ip link del $TAP 2>/dev/null; echo "tap and NAT rule removed"
  ;;
*) sed -n '2,13p' "$0"; exit 1 ;;
esac
