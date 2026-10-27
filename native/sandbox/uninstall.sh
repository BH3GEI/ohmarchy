#!/bin/bash
# Remove the sandboxed native route from a HarmonyOS PC, from this computer:
#   native/sandbox/uninstall.sh HOST
# Stops the helper and Linux, uninstalls com.ohmarchy.sandbox, removes
# /system/etc/init/ohm-sandboxd.cfg only if it is byte for byte the one the installer
# wrote, and removes /data/local/ohm-sandbox (Linux and everything in it). The demo
# version is not touched; its state is compared before and after.
set -e
HOST=${1:?usage: uninstall.sh HOST}
R() { ssh -o ConnectTimeout=60 -o ServerAliveInterval=10 -o ServerAliveCountMax=6 "$HOST" "$@"; }
state() {
    R sh -s <<'EOF'
P=$(cat /data/local/archtest/session.pid 2>/dev/null)
echo "demo session: $([ -n "$P" ] && kill -0 "$P" 2>/dev/null && echo "$P" || echo none)"
md5sum /system/etc/init/ohmarchy-desktop.cfg /system/etc/init/ohssh.cfg 2>&1
echo "ld-musl $(wc -c < /system/lib/ld-musl-aarch64.so.1) libc.so $(wc -c < /system/lib64/libc.so)"
EOF
}
before=$(state); echo "$before"
R sh -s <<'EOF'
S=/data/local/ohm-sandbox; CFG=/system/etc/init/ohm-sandboxd.cfg
if [ -x $S/bin/ohm-sandbox ]; then
    sh $S/bin/ohm-sandbox unserve
    sh $S/bin/ohm-sandbox desktop stop > /dev/null 2>&1
    sh $S/bin/ohm-sandbox stop
fi
bm uninstall -n com.ohmarchy.sandbox 2>&1 | tail -1
if [ -f $CFG ]; then
    if [ -f $S/ohm-sandboxd.cfg ] && cmp -s $CFG $S/ohm-sandboxd.cfg; then
        rm -f $CFG && echo "removed $CFG"
    else
        echo "STOP: $CFG is not the file the installer wrote; left in place"; exit 1
    fi
fi
for d in /dev/block/loop*; do
    losetup "$d" 2>/dev/null | grep -qF "($S/root.img)" && { echo "STOP: the image is still attached to $d"; exit 1; }
done
rm -rf /data/local/ohm-sandbox && echo "removed /data/local/ohm-sandbox"
rm -f /data/local/tmp/ohm-sandbox.hap
EOF
after=$(state)
[ "$before" = "$after" ] && echo "demo version and system: unchanged" || { echo "CHANGED:"; diff <(echo "$before") <(echo "$after"); exit 1; }
