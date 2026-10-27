# setup.sh: build /data/local/ohm-docker-test/root, a minimal root with the docker
# stack copied (read only) from route D's session; touches nothing outside S.
# DRY=1 prints what it would do.
S=/data/local/ohm-docker-test R=/data/local/ohm-docker-test/root
P=$(cat /data/local/archtest/session.pid); A=/proc/$P/root
run() { if [ "${DRY:-0}" = 1 ]; then echo "DRY: $*"; else "$@" || echo "FAILED: $*"; fi; }
[ -d $A/usr/bin ] || { echo "no session root at $A"; exit 1; }
files="/usr/bin/dockerd /usr/bin/containerd /usr/bin/containerd-shim-runc-v2 /usr/bin/runc /usr/bin/docker
 /usr/bin/docker-init /usr/bin/docker-proxy /usr/lib/docker/cli-plugins/docker-compose
 /usr/lib/ld-linux-aarch64.so.1 /usr/lib/libc.so.6 /usr/lib/libgcc_s.so.1 /usr/lib/libpathrs.so /usr/lib/libresolv.so.2
 /usr/lib/libseccomp.so.2 /usr/lib/libsystemd.so.0 /usr/local/lib/libhongmeng-msgrcv.so /usr/local/lib/libhongmeng-uname.so
 /usr/local/lib/libsplice-eof.so /usr/local/lib/ohmarchy-statx.so /etc/ld.so.preload /etc/ssl/certs/ca-certificates.crt
 /usr/bin/bash /usr/bin/umount /usr/bin/mount /usr/bin/ls /usr/bin/cat /usr/bin/ps
 /usr/lib/libblkid.so.1 /usr/lib/libcap.so.2 /usr/lib/libmount.so.1 /usr/lib/libncursesw.so.6 /usr/lib/libproc2.so.1 /usr/lib/libreadline.so.8"
run mkdir -p $R/usr/bin $R/usr/lib/docker/cli-plugins $R/usr/local/lib $R/etc/ssl/certs $R/etc/docker \
  $R/var/lib/docker $R/var/lib/containerd $R/run $R/tmp $R/proc $R/sys $R/dev $R/oldroot $S/log
for f in $files; do
  if [ -e "$A$f" ]; then run cp -L "$A$f" "$R$f"; else echo "missing in session: $f"; fi
done
[ "${DRY:-0}" = 1 ] || {
  ln -sf usr/bin $R/bin; ln -sf bash $R/usr/bin/sh; ln -sf usr/lib $R/lib; ln -sf usr/lib $R/lib64; chmod 1777 $R/tmp
  echo 'root:x:0:0:root:/root:/bin/sh' > $R/etc/passwd; echo 'root:x:0:' > $R/etc/group
  grep -q '^nameserver' $A/etc/resolv.conf 2>/dev/null && cp -L $A/etc/resolv.conf $R/etc/resolv.conf || echo 'nameserver 223.5.5.5' > $R/etc/resolv.conf
  echo '{"registry-mirrors":["https://docker.m.daocloud.io","https://docker.1ms.run"],"iptables":false,"ip6tables":false,"bridge":"none","data-root":"/var/lib/docker","exec-root":"/run/docker","storage-driver":"vfs","seccomp-profile":"unconfined","log-driver":"json-file","log-opts":{"max-size":"10m"}}' > $R/etc/docker/daemon.json
}
echo "resolv: $(grep -c nameserver $A/etc/resolv.conf 2>/dev/null)"; du -sh $S 2>/dev/null
echo __END__
