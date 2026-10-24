#!/system/bin/sh
# Build route D from nothing into $ARCH_BASE (as root on the HarmonyOS host, from
# this directory, with desktop/src fetched by desktop/fetch-sources.sh):
#   sh install.sh USER [GPU_BIN_DIR]
# image (10), Arch setup (20), Omarchy (30), the patched desktop (40), then a clean
# snapshot for reset.sh. GPU_BIN_DIR holds vtest-broker and virgl_test_server
# (native/vtest/build-vtest.sh output). Everything runs at nice NICE (default 19)
# so it can share the machine. Log: $ARCH_BASE/install.log
set -e
here=$(cd "$(dirname "$0")" && pwd)
. "$here/config.sh"
B=$ARCH_BASE
export ARCH_BASE
user=${1:?usage: install.sh USER [GPU_BIN_DIR]}
gpu=${2:-}
n=${NICE:-19}
mkdir -p "$B"
exec >> "$B/install.log" 2>&1
step() { echo "== $(date '+%F %T') $*"; }

step "10 image"
[ -e "$B/arch.img" ] || nice -n "$n" sh "$here/10-make-image.sh"
cp "$here/reset.sh" "$here/collect-logs.sh" "$B/"
step "20 setup"
sh "$B/arch.sh" start
nice -n "$n" sh "$B/arch.sh" run "$here/20-setup-arch.sh" "$user"
sh "$B/arch.sh" stop; sh "$B/arch.sh" start   # catatonit as pid 1 from now on
step "30 omarchy"
nice -n "$n" sh "$B/arch.sh" run "$here/30-install-omarchy.sh" "$user"
step "sparsecp"   # for reset.sh: the host's cp and dd cannot copy sparsely
P=$(cat "$B/session.pid")
cp "$here/sparsecp.c" "/proc/$P/root/tmp/"
echo 'gcc -static -O2 -o /tmp/sparsecp /tmp/sparsecp.c' > "$B/build-sparsecp.sh"
sh "$B/arch.sh" run "$B/build-sparsecp.sh" && rm -f "$B/build-sparsecp.sh"
cp "/proc/$P/root/tmp/sparsecp" "$B/bin/" && chmod 755 "$B/bin/sparsecp"
step "40 desktop"
# 40 needs desktop/ (sources, patches) next to it: copy native/ into the session
P=$(cat "$B/session.pid")
rm -rf "/proc/$P/root/root/native" && cp -r "$here" "/proc/$P/root/root/native"
nice -n "$n" sh "$B/arch.sh" run /root/native/40-install-desktop.sh "$user"
rm -rf "/proc/$P/root/root/native"
if [ -n "$gpu" ]; then
    step "gpu"
    cp "$gpu/vtest-broker" "$gpu/virgl_test_server" "$B/bin/" && chmod 755 "$B/bin/"*
fi
step "snapshot"
sh "$here/reset.sh" snapshot
step "done"
