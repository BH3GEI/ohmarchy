#!/system/bin/sh
# Boot supervisor for ohsshd + frpc.
# Launched by init (/system/etc/init/ohssh.cfg) on bootevent.boot.completed,
# and kept alive by init. Idempotent: matches by full cmdline substring so it
# never double-launches. Also re-launches either daemon if it dies.
#
# ohsshd runs under hdcd's access token (via ohtoken), so SSH sessions get the
# same rights as `hdc shell` (snapshot_display, uitest). Under init's own
# "ohssh" token those IPC calls fail with "operation not permitted".
B=/data/oh-ssh
LOG="$B/boot-start.log"

log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" >> "$LOG"; }

# HongMeng: reading /proc/<pid>/cmdline of a process that exits meanwhile can
# never return (a tr spun at 100% CPU for 9 hours, 2026-10-27). Read it only for
# live processes, in the background, with a 3 s limit.
cmdline_of() {
  kill -0 "$1" 2>/dev/null || return 1
  f="$B/.cmdline.$$"
  tr '\0' ' ' < "/proc/$1/cmdline" > "$f" 2>/dev/null &
  t=$!; i=0
  while kill -0 $t 2>/dev/null; do
    [ $i -ge 30 ] && { kill -9 $t 2>/dev/null; rm -f "$f"; return 1; }
    sleep 0.1; i=$((i + 1))
  done
  cat "$f"; rm -f "$f"
}

running() {
  # $1 = process name (/proc/<pid>/comm), $2 = unique substring of its cmdline
  for d in /proc/[0-9]*; do
    n=$({ cat "$d/comm"; } 2>/dev/null)
    [ "$n" = "$1" ] || continue
    case "$(cmdline_of "${d#/proc/}")" in
      *"$2"*) return 0 ;;
    esac
  done
  return 1
}

hdcd_token() {
  grep -oE '"processName":"hdcd","APL":[0-9]+,"version":[0-9]+,"tokenId":[0-9]+' \
    /data/service/el0/access_token/nativetoken.json 2>/dev/null | grep -oE '[0-9]+$'
}

log "supervisor start (pid $$), uid=$(id -u) secon=$(cat /proc/self/attr/current 2>/dev/null)"

# let network / filesystems settle after boot.completed
sleep 5

while true; do
  if ! running ohsshd "oh-ssh/ohsshd"; then
    T=$(hdcd_token)
    if [ -n "$T" ] && [ -x "$B/ohtoken" ]; then
      log "starting ohsshd (hdcd token $T)"
      nohup "$B/ohtoken" run "$T" "$B/ohsshd" -addr 0.0.0.0:2222 -authkeys "$B/keys/authorized_keys" -hostkey "$B/ohsshd_hostkey" -shell "$B/shell.sh" >> "$B/ohsshd.log" 2>&1 &
    else
      log "starting ohsshd (no hdcd token found, screenshots/uitest will fail)"
      nohup "$B/ohsshd" -addr 0.0.0.0:2222 -authkeys "$B/keys/authorized_keys" -hostkey "$B/ohsshd_hostkey" -shell "$B/shell.sh" >> "$B/ohsshd.log" 2>&1 &
    fi
    sleep 1
  fi
  if ! running frpc "frpc-office.toml"; then
    log "starting frpc"
    nohup "$B/frp/frpc" -c "$B/frp/frpc-office.toml" >> "$B/frp/frpc.out" 2>&1 &
  fi
  sleep 30
done
