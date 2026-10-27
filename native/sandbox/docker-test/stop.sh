# stop.sh: stop the sandbox dockerd (our recorded PID only), wait for it
S=/data/local/ohm-docker-test
p=$(cat $S/dockerd.pid 2>/dev/null)
if [ -n "$p" ] && kill -0 $p 2>/dev/null && grep -q dockerd /proc/$p/cmdline; then
  kill -TERM $p; i=0; while kill -0 $p 2>/dev/null && [ $i -lt 30 ]; do sleep 1; i=$((i+1)); done
  kill -0 $p 2>/dev/null && echo "still running after 30 s: $p" || echo "stopped $p"
else echo "not running"; fi
ps -A -o pid,args | grep -E 'ohm-sandbox|containerd-shim|/usr/bin/containerd' | grep -v grep
echo "host mounts mentioning sandbox: $(grep -c ohm-sandbox /proc/self/mountinfo)"
echo __END__
