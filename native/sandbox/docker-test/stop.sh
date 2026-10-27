# stop.sh: stop the sandbox dockerd (our recorded PID only), wait for it
S=/data/local/ohm-docker-test
p=$(cat $S/dockerd.pid 2>/dev/null)
if [ -n "$p" ] && kill -0 $p 2>/dev/null && grep -q dockerd /proc/$p/cmdline; then
  kill -TERM $p; i=0; while kill -0 $p 2>/dev/null && [ $i -lt 30 ]; do sleep 1; i=$((i+1)); done
  kill -0 $p 2>/dev/null && echo "still running after 30 s: $p" || echo "stopped $p"
else echo "not running"; fi
q=$(cat $S/pasta.pid 2>/dev/null)
if [ -n "$q" ] && case "$(readlink /proc/$q/exe 2>/dev/null)" in $S/tools/pasta|$S/tools/passt) true;; *) false;; esac; then kill $q && echo "stopped pasta $q"; sleep 1; fi
rm -f $S/pasta.pid
ps -A -o pid,args | grep -E 'ohm-docker-test|containerd-shim|/usr/bin/containerd' | grep -v grep
echo "host mounts mentioning sandbox: $(grep -c ohm-docker-test /proc/self/mountinfo)"
echo __END__
