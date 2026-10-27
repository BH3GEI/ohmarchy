#!/bin/sh
echo "== procs =="; for d in /proc/[0-9]*; do n=$({ cat "$d/comm"; } 2>/dev/null); case "$n" in ohsshd|frpc|ohtoken) echo "${d#/proc/} $n";; esac; done
echo "== ohsshd.log =="; tail -3 /data/oh-ssh/ohsshd.log 2>/dev/null
echo "== frpc log =="; tail -3 /data/oh-ssh/frp/frpc.log 2>/dev/null; tail -3 /data/oh-ssh/frp/frpc.out 2>/dev/null
