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
export PATH=/usr/bin OHM_NO_DEVICES_CGROUP=1 OHM_CHROOT_REEXEC=1 OHM_NO_CGROUPS=1 OHM_KEYRING_BEST_EFFORT=1
umount -l /oldroot || echo "umount oldroot failed"
echo "root now: $(ls /)"
exec dockerd --config-file /etc/docker/daemon.json -H unix:///run/docker.sock --pidfile /run/docker.pid
IN
setsid unshare -m sh $S/ns.sh > $S/log/dockerd.log 2>&1 < /dev/null &
echo $! > $S/dockerd.pid
sleep 8
echo "pid $(cat $S/dockerd.pid): $(cat /proc/$(cat $S/dockerd.pid)/cmdline 2>/dev/null | tr '\0' ' ')"
tail -40 $S/log/dockerd.log
echo "host mounts mentioning sandbox: $(grep -c ohm-sandbox /proc/self/mountinfo)"
echo __END__
