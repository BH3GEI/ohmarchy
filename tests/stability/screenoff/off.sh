# Host side of screenoff.sh: screen off through the timeout (AWAKE, DIM, INACTIVE),
# report the states and that the host answered, then wake the screen.
trap 'power-shell timeout -r > /dev/null 2>&1' EXIT
state() { hidumper -s PowerManagerService -a "-s" 2>/dev/null | grep -m1 "Current State" | awk '{print $3}'; }
power-shell timeout -o 3000 > /dev/null; seen=""; off=""
for _ in $(seq 40); do sleep 0.5; s=$(state); case " $seen " in *" $s "*) ;; *) seen="$seen $s" ;; esac
  case $s in INACTIVE|SLEEP|STAND_BY|DOZE) off=$s; break ;; esac; done
power-shell timeout -r > /dev/null; sleep 2
echo "states:$seen answered:$(date +%T)"
power-shell wakeup > /dev/null
