#!/bin/bash
# Build the route L app (com.ohmarchy.webemu, "Arch in ArkWeb") with DevEco Studio's
# command-line tools, sign it with the SDK's OpenHarmony test keys (native/app's
# sign.sh, linked into sign/) and install it on the device over ssh.
#   --with-image   also put webemu/image/out/arch32.img into the HAP (rawfile); without
#                  it the app reads files/arch32.img from its sandbox (push-disk.sh)
#   --no-install   build and sign only
#   OHOS_HOST      ssh host with a root shell on the HarmonyOS PC (default: ohdev)
#   UDID           device id for the debug profile (default: read from the device)
set -e
cd "$(dirname "$0")"
HOST=${OHOS_HOST:-ohdev}
C=${DEVECO_HOME:-/Applications/DevEco-Studio.app/Contents}
WITH_IMAGE=0 INSTALL=1
for a in "$@"; do case $a in --with-image) WITH_IMAGE=1 ;; --no-install) INSTALL=0 ;; esac; done
ssh_() { perl -e 'alarm shift; exec @ARGV' "$1" ssh -o ConnectTimeout=10 "$HOST" "${@:2}"; }

[ -f ../vendor/libv86.js ] || ../fetch.sh
R=entry/src/main/resources/rawfile
rm -rf $R && mkdir -p $R/web
cp ../web/* ../vendor/{libv86.js,v86.wasm,v86-fallback.wasm,seabios.bin,vgabios.bin,xterm.js,xterm.css} $R/web/
cp ../image/out/vmlinuz ../image/out/initramfs.img $R/web/
[ $WITH_IMAGE = 1 ] && cp ../image/out/arch32.img $R/

DEVECO_SDK_HOME=$C/sdk PATH=$C/tools/node/bin:$C/tools/ohpm/bin:/usr/bin:/bin \
  "$C/tools/node/bin/node" "$C/tools/hvigor/bin/hvigorw.js" --mode module -p module=entry@default \
  -p product=default -p buildMode=debug assembleHap --no-daemon 2>&1 | grep -E 'ERROR|error:|BUILD' || true
U=entry/build/default/outputs/default/entry-default-unsigned.hap
[ -f "$U" ] || exit 1
export UDID=${UDID:-$(ssh_ 30 -tt 'bm get --udid' 2>/dev/null | tr -d '\r' | grep -E '^[0-9A-F]{64}$')}
BUNDLE=com.ohmarchy.webemu sign/sign.sh "$U" webemu.hap > /dev/null
ls -la webemu.hap
[ $INSTALL = 1 ] || exit 0
ssh_ 60 'mkdir -p /data/local/tmp/routel'
perl -e 'alarm 1800; exec @ARGV' ssh "$HOST" 'cat > /data/local/tmp/routel/webemu.hap' < webemu.hap
ssh_ 120 -tt 'bm install -r -p /data/local/tmp/routel/webemu.hap 2>&1 | tail -1' 2>&1
