#!/bin/bash
# Install the sandboxed native route on a HarmonyOS PC from this computer, then check it:
#   native/sandbox/install.sh HOST [--write-system]
# HOST: ssh host with a root shell on the PC (oh-ssh, device/oh-ssh). Puts in place
# the app com.ohmarchy.sandbox (built and signed for the device), the helper and
# launcher in /data/local/ohm-sandbox, the Linux image (made on the device from the
# demo session's root; refuses without one), and starts the helper.
# The one file outside /data is /system/etc/init/ohm-sandboxd.cfg (the helper at
# boot). Without --write-system it is only checked and shown (dry run). With it, it
# is written only if absent, and read back.
# The sandbox's network goes through pasta (passt.top, PASST_COMMIT below), patched
# with passt-hongmeng.patch and built inside the sandbox; rebuilt when either changes.
# Needs DevEco Studio (app build, static clang) and Pillow (build-app.sh).
set -e
HOST=${1:?usage: install.sh HOST [--write-system]}
WRITE_SYSTEM=0; [ "$2" = --write-system ] && WRITE_SYSTEM=1
here=$(cd "$(dirname "$0")" && pwd)
tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT
SDK=${DEVECO_HOME:-/Applications/DevEco-Studio.app/Contents}/sdk/default/openharmony/native
CFG=/system/etc/init/ohm-sandboxd.cfg
PASST_COMMIT=6aa4f88bd9846411edff3ed70460475b538addca
R() { ssh -o ConnectTimeout=60 -o ServerAliveInterval=10 -o ServerAliveCountMax=6 "$HOST" "$@"; }
step() { echo "== $*"; }

# What the demo version and the system look like; compared after the install.
health() {
    R sh -s <<'EOF'
B=/data/local/archtest
P=$(cat $B/session.pid 2>/dev/null)
echo "demo session: $([ -n "$P" ] && kill -0 "$P" 2>/dev/null && echo "$P" || echo none)"
for c in Hyprland vtest-broker; do
    for d in /proc/[0-9]*; do
        [ "$({ cat $d/comm; } 2>/dev/null)" = $c ] && [ "$(readlink $d/exe 2>/dev/null)" != /data/local/ohm-sandbox/bin/vtest-broker ] &&
            echo "demo $c ${d#/proc/}"
    done
done
md5sum /system/etc/init/ohmarchy-desktop.cfg /system/etc/init/ohssh.cfg 2>&1
echo "ld-musl $(wc -c < /system/lib/ld-musl-aarch64.so.1) libc.so $(wc -c < /system/lib64/libc.so)"
# ours may be added by this install; every other cfg counts
echo "init cfgs (besides ohm-sandboxd.cfg): $(ls /system/etc/init | grep -cvx ohm-sandboxd.cfg)"
EOF
}

step "device"
R id < /dev/null | grep -q 'uid=0' || { echo "need a root shell on $HOST"; exit 1; }
UDID=$(R bm get --udid < /dev/null | tr -d '\r' | grep -E '^[0-9A-F]{64}$')
[ -n "$UDID" ] || { echo "no UDID from $HOST"; exit 1; }
health > "$tmp/before"; cat "$tmp/before"
grep -q '^demo session: [0-9]' "$tmp/before" || [ "$(R sh -s <<'EOF'
[ -f /data/local/ohm-sandbox/root.img ] && echo have
EOF
)" = have ] || { echo "no Linux image yet and no demo session to make one from"; exit 1; }

step "build (helper binaries, app; pasta source)"
for t in 1 2 3; do
    curl -sfL -m 120 -o "$tmp/passt.tar.gz" "https://passt.top/passt/snapshot/passt-$PASST_COMMIT.tar.gz" && break
    [ $t = 3 ] && { echo "could not download pasta's source"; exit 1; }
    sleep 5
done
mkdir "$tmp/passt" && tar -xzf "$tmp/passt.tar.gz" -C "$tmp/passt" --strip-components 1
patch -s -d "$tmp/passt" -p1 < "$here/passt-hongmeng.patch"
COPYFILE_DISABLE=1 tar -cf "$tmp/passt.tar" -C "$tmp/passt" .
pasta_stamp="$PASST_COMMIT $(md5 -q "$here/passt-hongmeng.patch")"
for p in ohm-capdrop ohm-sandboxd; do
    "$SDK/llvm/bin/clang" --target=aarch64-linux-ohos --sysroot="$SDK/sysroot" -static -O2 -o "$tmp/$p" "$here/$p.c"
done
UDID=$UDID "$here/build-app.sh" > "$tmp/build.log" 2>&1 || { tail -20 "$tmp/build.log"; exit 1; }

step "copy to $HOST"
tar -cf "$tmp/files.tar" -C "$here" ohm-sandbox config-check.sh boot-serve.sh ohm-sandboxd.cfg ohm-abstract-fence.c ohm-fence-demo policy.sh policy.conf.default \
    -C "$here/../desktop" ohime.c ohmarchy-audio-relay.c ohmarchy-desktop hongmeng-ptypeer.c \
    -C "$here/../desktop/src/Hyprland/protocols" input-method-unstable-v2.xml \
    -C "$tmp" ohm-capdrop ohm-sandboxd
R 'cat > /data/local/tmp/ohm-sandbox-files.tar' < "$tmp/files.tar"
# the app: only the 1 MB pieces that differ from the copy already there
hap=$here/ohm-sandbox.hap
mkdir "$tmp/hap" && split -b 1m "$hap" "$tmp/hap/n."
R sh -s > "$tmp/old.md5" <<'EOF'
D=/data/local/tmp/ohm-sandbox-hap; rm -rf "${D:?}"; mkdir -p "$D"
[ -f /data/local/tmp/ohm-sandbox.hap ] && cd "$D" && split -b 1048576 /data/local/tmp/ohm-sandbox.hap n. && md5sum n.* | awk '{print $1, $2}'
exit 0
EOF
for f in "$tmp/hap"/n.*; do
    n=${f##*/}
    grep -q "^$(md5 -q "$f") $n\$" "$tmp/old.md5" && continue
    for t in 1 2 3 4 5; do
        [ "$(R "cat > /data/local/tmp/ohm-sandbox-hap/$n && md5sum /data/local/tmp/ohm-sandbox-hap/$n" < "$f" | cut -d' ' -f1)" = "$(md5 -q "$f")" ] && break
        [ $t = 5 ] && { echo "could not copy $n"; exit 1; }
    done
done
want=$(md5 -q "$hap")

step "install on $HOST"
R "WANT=$want sh -s" <<'EOF'
set -e
S=/data/local/ohm-sandbox; T=/data/local/tmp/ohm-sandbox-unpack
mkdir -p $S/bin $S/src $S/evidence
rm -rf "${T:?}"; mkdir -p $T; tar -xf /data/local/tmp/ohm-sandbox-files.tar -C $T
sh -n $T/ohm-sandbox
# the helper may be running (an update): stop it; files go in under a new name, then renamed
[ -x $S/bin/ohm-sandbox ] && sh $S/bin/ohm-sandbox unserve > /dev/null
for f in ohm-sandbox policy.sh config-check.sh boot-serve.sh ohm-capdrop ohm-sandboxd; do
    cp $T/$f $S/bin/$f.new && mv $S/bin/$f.new $S/bin/$f
done
cp $T/ohm-abstract-fence.c $T/ohm-fence-demo $T/ohime.c $T/ohmarchy-audio-relay.c $T/ohmarchy-desktop $T/hongmeng-ptypeer.c $T/input-method-unstable-v2.xml $S/src/
cp $T/ohm-sandboxd.cfg $S/ohm-sandboxd.cfg
# the policy: the commented default always; policy.conf only when there is none (the
# user's own is kept, across updates and Reset Linux)
cp $T/policy.conf.default $S/policy.conf.default
[ -f $S/policy.conf ] || cp $T/policy.conf.default $S/policy.conf
[ -x $S/bin/vtest-broker ] || cp /data/local/archtest/bin/vtest-broker $S/bin/vtest-broker
chmod 755 $S/bin/*
H=/data/local/tmp/ohm-sandbox-hap
cat $H/n.* > /data/local/tmp/ohm-sandbox.hap.new
[ "$(md5sum /data/local/tmp/ohm-sandbox.hap.new | cut -d' ' -f1)" = "$WANT" ] || { echo "app copy damaged"; exit 1; }
mv /data/local/tmp/ohm-sandbox.hap.new /data/local/tmp/ohm-sandbox.hap
rm -rf "${H:?}" "${T:?}" /data/local/tmp/ohm-sandbox-files.tar
bm install -r -p /data/local/tmp/ohm-sandbox.hap 2>&1 | tail -1
EOF

step "Linux image"
R sh -s <<'EOF'
S=/data/local/ohm-sandbox; O="sh $S/bin/ohm-sandbox"
if [ ! -f $S/root.img ]; then
    $O create || exit 1
    $O start && $O build-helpers && $O stop && $O snapshot || exit 1
else
    echo "image present: kept (helpers rebuilt in it)"
    $O unserve > /dev/null; $O stop > /dev/null 2>&1
    $O start && $O build-helpers && $O stop || exit 1
fi
EOF

step "pasta (the sandbox's network)"
if [ "$(R cat /data/local/ohm-sandbox/bin/pasta.stamp 2>/dev/null < /dev/null)" = "$pasta_stamp" ]; then
    echo "built already ($pasta_stamp)"
else
    R sh -s <<'EOF'
S=/data/local/ohm-sandbox; O="sh $S/bin/ohm-sandbox"
$O unserve > /dev/null; $O stop > /dev/null 2>&1; $O start > /dev/null || exit 1
EOF
    R sh /data/local/ohm-sandbox/bin/ohm-sandbox build-pasta < "$tmp/passt.tar"
    R sh /data/local/ohm-sandbox/bin/ohm-sandbox stop < /dev/null
    echo "$pasta_stamp" | R 'cat > /data/local/ohm-sandbox/bin/pasta.stamp'
fi

step "boot: $CFG"
R "WRITE=$WRITE_SYSTEM sh -s" <<'EOF'
S=/data/local/ohm-sandbox; CFG=/system/etc/init/ohm-sandboxd.cfg
if [ -f $CFG ] && cmp -s $CFG $S/ohm-sandboxd.cfg; then
    echo "already in place (same content)"
elif [ -e $CFG ]; then
    echo "STOP: $CFG exists and is not ours; not touched"; exit 1
elif [ "$WRITE" != 1 ]; then
    echo "dry run: would add $CFG (absent now; nothing else under /system changes):"
    cat $S/ohm-sandboxd.cfg
else
    cp $S/ohm-sandboxd.cfg $CFG && chmod 644 $CFG
    cmp $CFG $S/ohm-sandboxd.cfg && echo "written and read back: $CFG"
fi
EOF

step "helper"
R sh /data/local/ohm-sandbox/bin/ohm-sandbox serve < /dev/null

step "self-check"
R sh -s <<'EOF'
S=/data/local/ohm-sandbox; O="sh $S/bin/ohm-sandbox"
$O desktop start > /dev/null 2>&1
$O status; $O desktop status
sh $S/bin/config-check.sh > $S/evidence/config-check-install.txt 2>&1
grep -E '^(mnt|pid|ipc|uts|net) |CapBnd|NoNewPrivs' $S/evidence/config-check-install.txt
$O desktop stop > /dev/null 2>&1; $O stop
EOF
health > "$tmp/after"
if diff "$tmp/before" "$tmp/after" > "$tmp/diff"; then
    echo "demo version and system: unchanged (session, processes, init cfgs, ld-musl, libc.so)"
else
    echo "CHANGED:"; cat "$tmp/diff"; exit 1
fi
echo "installed. Open \"Omarchy (sandbox)\"; Reset Linux is in its icon's menu."
