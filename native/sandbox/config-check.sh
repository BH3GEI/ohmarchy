#!/system/bin/sh
# Print the running sandbox's configuration (read only; changes nothing), as root on
# the host:  sh config-check.sh > check.txt
S=${OHM_SANDBOX:-/data/local/ohm-sandbox}
O="$S/bin/ohm-sandbox"
P=$(cat "$S/sandbox.pid" 2>/dev/null)
[ -n "$P" ] && [ -d "/proc/$P" ] || { echo "sandbox not running"; exit 1; }
echo "# ohm-sandbox configuration, $(date '+%F %T %Z'), sandbox pid $P (host)"
echo
echo "## namespaces: host (this shell) / sandbox"
for n in mnt pid ipc uts net time; do
    echo "$n  $(readlink /proc/self/ns/$n)  $(readlink /proc/$P/ns/$n)"
done
echo
echo "## SELinux context of the sandbox's init"
cat "/proc/$P/attr/current"; echo
echo
echo "## inside: Cap* and NoNewPrivs of a process started by ohm-sandbox run"
sh "$O" run /usr/bin/grep -E '^(Cap|NoNewPrivs)' /proc/self/status
echo
echo "## inside: mountinfo"
sh "$O" run /usr/bin/cat /proc/self/mountinfo
echo
echo "## inside: /dev"
sh "$O" run /usr/bin/ls -la /dev /dev/pts /dev/dma_heap
echo
echo "## inside: processes"
sh "$O" run /usr/bin/ps -eo pid,user,comm
