#!/system/bin/sh
# share-test.sh: check route I's home share with the VM running (root, host):
#   sh share-test.sh
# virtiofsd's uid and capabilities, the guest mount, ownership both ways (a
# file from yao, one from a root container), and the symlink test (a link to
# ../../etc made in the guest: what the guest and D see through it). Removes
# its test files afterwards.
V=/data/local/kaidashi/bin/ohmarchy-vm
S=/data/local/kaidashi/ownvm/svc
H=/proc/$(cat /data/local/archtest/session.pid)/root/home/builder
g() { sh $V ssh "$@" < /dev/null; }
hr() { printf '\n== %s\n' "$*"; }

hr virtiofsd
p=$(cat $S/virtiofsd.pid 2>/dev/null)
if [ -n "$p" ] && grep -q /data/local/kaidashi /proc/$p/cmdline 2>/dev/null; then
  grep -E '^(Uid|Gid|Groups|CapEff|CapPrm|NoNewPrivs)' /proc/$p/status | tr -s '\t' ' '
else
  echo "no virtiofsd of ours"; tail -5 $S/virtiofsd.out
fi

hr "guest mount"
g 'findmnt -n /home/builder; ls -ln /home/builder | head -5'

hr "write from the guest"
g 'cd /home/builder && touch .ovm-yao && docker run --rm -v /home/builder:/w alpine sh -c "touch /w/.ovm-root; ln -s ../../etc /w/.ovm-escape" && ls -ln .ovm-yao .ovm-root .ovm-escape'
echo "-- the same files in D (host view):"
ls -ln $H/.ovm-yao $H/.ovm-root $H/.ovm-escape 2>&1

hr "symlink ../../etc through the share"
echo "-- in the guest, as yao:"
g 'readlink /home/builder/.ovm-escape; head -1 /home/builder/.ovm-escape/hostname 2>&1; head -1 /home/builder/.ovm-escape/os-release 2>&1'
echo "-- in a root container with the share at /w:"
g 'docker run --rm -v /home/builder:/w alpine sh -c "head -1 /w/.ovm-escape/os-release; ls /w/.. | head -3"' 2>&1
echo "-- the host's own files, for comparison (must not appear above):"
head -1 /etc/os-release 2>/dev/null || getprop ro.build.display.id

hr "parent of the share root, from the guest"
g 'ls -a /home/builder/.. | head; stat -c "%n %i %d" /home/builder /home/builder/..'

hr cleanup
g 'rm -f /home/builder/.ovm-yao /home/builder/.ovm-escape; docker run --rm -v /home/builder:/w alpine rm -f /w/.ovm-root'
ls -a $H | grep -c '^\.ovm-'
