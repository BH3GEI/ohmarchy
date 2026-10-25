#!/bin/bash
# Build + sign + install the VM-API runtime probe HAP.
set -e
cd "$(dirname "$0")"
HOST=${OHOS_HOST:-ohdev}
C=${DEVECO_HOME:-/Applications/DevEco-Studio.app/Contents}
DEVECO_SDK_HOME=$C/sdk PATH=$C/tools/node/bin:$C/tools/ohpm/bin:/usr/bin:/bin \
  "$C/tools/node/bin/node" "$C/tools/hvigor/bin/hvigorw.js" --mode module -p module=entry@default \
  -p product=default -p buildMode=debug assembleHap --no-daemon 2>&1 | grep -iE 'ERROR|error:|fail|BUILD|hms|virt' || true
U=entry/build/default/outputs/default/entry-default-unsigned.hap
[ -f "$U" ] || { echo "BUILD FAILED: no unsigned hap"; exit 1; }
echo "unsigned hap OK: $(ls -l "$U" | awk '{print $5}') bytes"
export UDID=${UDID:-$(ssh "$HOST" 'bm get --udid' 2>/dev/null | tr -d '\r' | grep -oE '[0-9A-F]{64}')}
echo "UDID=$UDID"
BUNDLE=com.ohmarchy.jloader sign/sign.sh "$U" jloader.hap
echo "signed: $(ls -l jloader.hap | awk '{print $5}') bytes"
[ "$1" = "--no-install" ] && exit 0
ssh "$HOST" 'cat > /data/local/tmp/jloader.hap' < jloader.hap
ssh "$HOST" 'bm install -r -p /data/local/tmp/jloader.hap 2>&1 | tail -3'
