(sleep 1; echo 'echo uptime $(cut -d" " -f1 /proc/uptime); echo 1 > /proc/sys/kernel/sysrq; echo b > /proc/sysrq-trigger'; sleep 3) | toybox nc -w 4 172.16.100.2 5000 2>&1 | tr -d '\r' | tail -3
