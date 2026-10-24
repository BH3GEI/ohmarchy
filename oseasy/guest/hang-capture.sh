#!/bin/sh
# Catch a guest hang from outside: kernel messages go to the host over netconsole
# (UDP, sent by the kernel itself, so it keeps working while user space starves),
# lockup detectors panic with backtraces of every CPU, and a heartbeat writes the
# guest's state to the kernel log every 10 s (it stops when user space stops).
#   sudo sh hang-capture.sh HOST_IP [PORT]     (on the host: toybox nc -u -l -p PORT)
set -eu
ip=$1; port=${2:-6666}
dev=$(ip route show default | awk '{print $5; exit}')
gw=$(ip route show default | awk '{print $3; exit}')
ping -c1 -W1 "$gw" >/dev/null 2>&1 || true
mac=$(ip neigh show "$gw" dev "$dev" | awk '{print $3; exit}')
modprobe configfs 2>/dev/null || true
mountpoint -q /sys/kernel/config || mount -t configfs none /sys/kernel/config
modprobe netconsole
t=/sys/kernel/config/netconsole/ohmarchy
[ -d $t ] || mkdir $t
echo 0 > $t/enabled 2>/dev/null || true
echo "$dev" > $t/dev_name
echo "$ip" > $t/remote_ip
echo "$port" > $t/remote_port
[ -n "$mac" ] && echo "$mac" > $t/remote_mac
echo 1 > $t/enabled
dmesg -n 8
for kv in kernel.softlockup_panic=1 kernel.hung_task_panic=1 kernel.softlockup_all_cpu_backtrace=1 \
          kernel.hardlockup_all_cpu_backtrace=1 kernel.nmi_watchdog=1 kernel.hung_task_timeout_secs=60 \
          kernel.panic_on_rcu_stall=1 kernel.panic_print=0x7f kernel.panic=0; do
  sysctl -q -w "$kv" 2>/dev/null || echo "hang-capture: $kv not available"
done
echo "hang-capture: netconsole $dev -> $ip:$port via $gw ($mac); watchdog $(cat /proc/sys/kernel/watchdog 2>/dev/null), nmi_watchdog $(cat /proc/sys/kernel/nmi_watchdog 2>/dev/null)" | tee /dev/kmsg
systemd-run --unit=ohmarchy-heartbeat --nice=-10 /bin/sh -c '
while :; do
  echo "hb: load $(cut -d" " -f1-4 /proc/loadavg); mem $(awk "/MemAvailable/ {print int(\$2/1024)}" /proc/meminfo) MB; top: $(ps -eo pcpu=,comm= --sort=-pcpu | head -4 | tr -s " " | tr "\n" ",")" > /dev/kmsg
  sleep 10
done' >/dev/null
echo "hang-capture: heartbeat started" > /dev/kmsg
