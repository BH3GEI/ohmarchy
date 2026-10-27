#!/system/bin/sh
# restart ohsshd with the same args as boot-start.sh (hdcd token + login shell wrapper)
B=/data/oh-ssh
T=$(grep -oE "\"processName\":\"hdcd\",\"APL\":[0-9]+,\"version\":[0-9]+,\"tokenId\":[0-9]+" /data/service/el0/access_token/nativetoken.json 2>/dev/null | grep -oE "[0-9]+$")
sleep 2
# by comm, not cmdline: reading the cmdline of an exiting process can hang on HongMeng
for d in /proc/[0-9]*; do [ "$({ cat $d/comm; } 2>/dev/null)" = ohsshd ] && kill ${d#/proc/}; done
sleep 1
nohup "$B/ohtoken" run "$T" "$B/ohsshd" -addr 0.0.0.0:2222 -authkeys "$B/keys/authorized_keys" -hostkey "$B/ohsshd_hostkey" -shell "$B/shell.sh" >> "$B/ohsshd.log" 2>&1 &
