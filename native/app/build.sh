#!/bin/bash
# Build the display app with DevEco Studio's command-line tools, sign it with the
# SDK's OpenHarmony test keys (sign/sign.sh) and install it on the device over ssh.
# It is installed, not started; open "Omarchy (native)" on the device yourself.
#   OHOS_HOST   ssh host with a root shell on the HarmonyOS PC (default: ohdev)
#   UDID        device id for the debug profile (default: read from the device)
#   --no-install  build and sign only
set -e
cd "$(dirname "$0")"
HOST=${OHOS_HOST:-ohdev}
C=${DEVECO_HOME:-/Applications/DevEco-Studio.app/Contents}
DEVECO_SDK_HOME=$C/sdk PATH=$C/tools/node/bin:$C/tools/ohpm/bin:/usr/bin:/bin \
  "$C/tools/node/bin/node" "$C/tools/hvigor/bin/hvigorw.js" --mode module -p module=entry@default \
  -p product=default -p buildMode=debug assembleHap --no-daemon 2>&1 | grep -E 'ERROR|error:|BUILD' || true
U=entry/build/default/outputs/default/entry-default-unsigned.hap
[ -f "$U" ] || exit 1
export UDID=${UDID:-$(ssh -tt "$HOST" 'bm get --udid' 2>/dev/null | tr -d '\r' | grep -E '^[0-9A-F]{64}$')}
sign/sign.sh "$U" ohdisp.hap > /dev/null
[ "$1" = "--no-install" ] && exit 0
ssh "$HOST" 'cat > /data/local/tmp/ohdisp.hap' < ohdisp.hap
ssh -tt "$HOST" 'bm install -r -p /data/local/tmp/ohdisp.hap 2>&1 | tail -1' 2>&1
