# start.sh: dockerd in its own mount namespace, rooted at /data/local/ohm-docker-test/root
S=/data/local/ohm-docker-test R=/data/local/ohm-docker-test/root
if [ -s $S/dockerd.pid ] && kill -0 $(cat $S/dockerd.pid) 2>/dev/null; then echo "already running: $(cat $S/dockerd.pid)"; echo __END__; exit 0; fi
cat > $S/ns.sh <<'NS'
# runs in the new mount namespace (host toybox sh), then pivots into R
R=/data/local/ohm-docker-test/root
mount -o rprivate / 2>&1 || echo "rprivate failed"
mount --bind $R $R || exit 1
mount -t proc proc $R/proc || exit 1
mount -t sysfs -o ro sysfs $R/sys || echo "sysfs failed"
mount -t tmpfs -o mode=755,size=1m tmpfs $R/sys/fs/cgroup || echo "cgroup tmpfs failed"
mount -t tmpfs -o mode=755,size=16m tmpfs $R/dev || exit 1
umask 0
mknod $R/dev/null c 1 3; mknod $R/dev/zero c 1 5; mknod $R/dev/full c 1 7
mknod $R/dev/random c 1 8; mknod $R/dev/urandom c 1 9; mknod $R/dev/tty c 5 0
umask 022
mkdir -p $R/dev/pts $R/dev/shm
mount -t devpts devpts $R/dev/pts || echo "devpts failed"
mount -t tmpfs -o mode=1777,size=64m tmpfs $R/dev/shm
mount -t tmpfs -o mode=755,size=64m tmpfs $R/run
cd $R && pivot_root . oldroot || exit 1
exec /usr/bin/bash /inner.sh
NS
cat > $R/inner.sh <<'IN'
export PATH=/usr/bin OHM_NO_DEVICES_CGROUP=1 OHM_CHROOT_REEXEC=1 OHM_NO_CGROUPS=1 OHM_KEYRING_BEST_EFFORT=1 \
  OHM_SKIP_FS=devpts,mqueue OHM_NO_MOUNT_SOURCE_THREAD=1 OHM_KEEPCAPS_BEST_EFFORT=1 \
  TMPDIR=/tmp  # the host session's TMPDIR (/data/local/tmp) does not exist in here
umount -l /oldroot || echo "umount oldroot failed"
echo "root now: $(ls /)"
exec dockerd --config-file /etc/docker/daemon.json -H unix:///run/docker.sock --pidfile /run/docker.pid
IN
# NET=pasta: dockerd (and --network host containers) in a network namespace of its
# own, connected by pasta (passt.top, the native sandbox's build, tools/passt; it must run as tools/pasta): out
# through host sockets, nothing forwarded inward, the host's 127.0.0.1 not reachable.
# Without it, dockerd shares the host's network.
case "$NET" in pasta) UNS="unshare -m -n" ;; *) UNS="unshare -m" ;; esac
setsid $UNS sh $S/ns.sh > $S/log/dockerd.log 2>&1 < /dev/null &
echo $! > $S/dockerd.pid
if [ "$NET" = pasta ]; then
  P=$(cat $S/dockerd.pid); sleep 1
  set -- $(ip route show table all 2>/dev/null | grep -m1 '^default via ')
  if [ "$1" = default ] && [ "$4" = dev ]; then
    # pasta needs the namespace's loopback up, and drops its capabilities before it
    # opens the namespace: hand it a bind mount, gone again once pasta has it open
    # (--no-netns-quit: it would quit when the path goes; stop.sh ends it)
    nsenter -t $P -n -- ip link set lo up || echo "loopback not up"
    F=$S/netns; : > $F; mount --bind /proc/$P/ns/net $F
    $S/tools/pasta --runas 0 --netns $F --netns-only --no-netns-quit --config-net -4 -i "$5" -g "$3" \
      -t none -u none -T none -U none --no-map-gw -q -P $S/pasta.pid -l $S/log/pasta.log > /dev/null 2>&1
    echo "network: pasta rc=$? through $5 ($3)"; sleep 2; umount -l $F; rm -f $F
  else echo "network: no default route; offline"; fi
fi
sleep 8
echo "pid $(cat $S/dockerd.pid): $(cat /proc/$(cat $S/dockerd.pid)/cmdline 2>/dev/null | tr '\0' ' ')"
tail -40 $S/log/dockerd.log
echo "host mounts mentioning sandbox: $(grep -c ohm-docker-test /proc/self/mountinfo)"
echo __END__
