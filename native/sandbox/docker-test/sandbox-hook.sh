# sandbox-hook.sh: Docker for the native sandbox (ohm-sandbox start/stop, policy docker = on)
#   sandbox-hook.sh start PID   dockerd (NET=pasta, own mount/net/pid namespaces), its socket
#                               as /run/docker.sock in the sandbox whose init is PID:
#                               root:<the sandbox user's gid>, 0660, through tools/sockrelay
#   sandbox-hook.sh stop        the relay and dockerd (our recorded PIDs only)
# runc refuses what would reach past this directory (README: what a container may get).
S=/data/local/ohm-docker-test
relay_stop() {
  r=$(cat $S/relay.pid 2>/dev/null)
  [ -n "$r" ] && [ "$(readlink /proc/$r/exe 2>/dev/null)" = $S/tools/sockrelay ] && kill $r
  rm -f $S/relay.pid
}
case "$1" in
start)
  P=$2
  [ -d "/proc/$P/root/run" ] || { echo "no sandbox with init $P"; exit 1; }
  gid=$(grep '^builder:' /proc/$P/root/etc/passwd | cut -d: -f4)
  [ -n "$gid" ] || { echo "no user builder in the sandbox"; exit 1; }
  NET=pasta SOCK=1 sh $S/start.sh | grep -E 'network:|API listen|already running|SOCK'
  i=0; while [ ! -S $S/root/sbx/docker.sock ] && [ $i -lt 30 ]; do sleep 1; i=$((i+1)); done
  [ -S $S/root/sbx/docker.sock ] || { echo "dockerd gave no socket ($S/log/dockerd.log)"; exit 1; }
  relay_stop
  setsid $S/tools/sockrelay /proc/$P/root/run/docker.sock "$gid" $S/root/sbx/docker.sock \
    < /dev/null > $S/log/relay.log 2>&1 &
  echo $! > $S/relay.pid
  sleep 1; cat $S/log/relay.log
  ;;
stop)
  relay_stop
  sh $S/stop.sh | grep -E 'stopped|still|not running|host mounts'
  ;;
*) echo "usage: sandbox-hook.sh start PID | stop"; exit 2 ;;
esac
