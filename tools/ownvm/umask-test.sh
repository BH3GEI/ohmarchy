#!/system/bin/sh
# umask-test.sh: one short slot (root, host): start ohmarchy-vm, check
# virtiofsd's umask and the mode of files made in the share by yao and by a
# root container (expected 0644 in D), remove them, stop. Needs no other StratoVirt VM running.
V=/data/local/kaidashi/bin/ohmarchy-vm
S=/data/local/kaidashi/ownvm/svc
H=/proc/$(cat /data/local/archtest/session.pid)/root/home/builder
sh $V start < /dev/null || exit 1
p=$(cat $S/virtiofsd.pid)
echo "virtiofsd $p: $(grep -E '^(Umask|Uid)' /proc/$p/status | tr -s '\t' ' ' | tr '\n' ' ')"
sh $V ssh 'umask; touch /home/builder/.ovm-um-yao; docker run --rm -v /home/builder:/w alpine sh -c "umask; touch /w/.ovm-um-root; mkdir /w/.ovm-um-dir"' < /dev/null
ls -ldn $H/.ovm-um-yao $H/.ovm-um-root $H/.ovm-um-dir
sh $V ssh 'rm -rf /home/builder/.ovm-um-yao /home/builder/.ovm-um-dir; docker run --rm -v /home/builder:/w alpine rm -f /w/.ovm-um-root' < /dev/null
ls -a $H | grep -c '^\.ovm-um'
sh $V stop < /dev/null
