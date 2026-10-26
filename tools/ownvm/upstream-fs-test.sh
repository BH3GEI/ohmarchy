#!/system/bin/sh
# upstream-fs-test.sh: the home share served by upstream virtiofsd
# (OVM_VIRTIOFSD=upstream, docs/vm-own.md). Root on the host:
#   sh upstream-fs-test.sh
V=/data/local/kaidashi/bin/ohmarchy-vm
S=/data/local/kaidashi/ownvm/svc
H=/proc/$(cat /data/local/archtest/session.pid)/root/home/builder
export OVM_VIRTIOFSD=upstream
g() { sh $V ssh "$@" < /dev/null; }
hr() { printf '\n== %s\n' "$*"; }

ls -ln /data/local/kaidashi/bin/virtiofsd-upstream   # no sha256 on ohdev (Yao, 2026-10-26): size
sh $V start < /dev/null || { echo "start failed"; tail -20 $S/virtiofsd.out; sh $V stop < /dev/null; exit 1; }
i=0; until g true 2>/dev/null; do i=$((i+5)); [ $i -ge 150 ] && break; sleep 5; done
echo "guest ssh after ${i}s"
hr "virtiofsd log"; tail -5 $S/virtiofsd.out

hr "modes: create, mkdir, chmod (guest view, then D)"
g 'cd /home/builder && umask && touch .up-yao && mkdir .up-yaod && touch .up-ch && chmod 600 .up-ch &&
   docker run --rm -v /home/builder:/w alpine sh -c "touch /w/.up-root; mkdir /w/.up-rootd" && ls -ldn .up-*'
echo "-- in D:"; ls -ldn $H/.up-* 2>&1
g 'cd /home/builder && rm -rf .up-yao .up-yaod .up-ch; docker run --rm -v /home/builder:/w alpine rm -rf /w/.up-root /w/.up-rootd'

hr share-test; sh /data/local/kaidashi/bin/share-test.sh < /dev/null 2>&1

hr stop; sh $V stop < /dev/null
for p in /proc/[0-9]*; do c=$(tr '\0' ' ' < $p/cmdline 2>/dev/null); case "$c" in *kaidashi/ownvm*) echo "LEFT: ${p#/proc/} $c";; esac; done
echo UPSTREAM_TEST_DONE
