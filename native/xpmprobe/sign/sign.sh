#!/bin/bash
# Sign a HAP with the OpenHarmony test keys from the SDK (debug profile bound to the device UDID).
set -e
C=/Applications/DevEco-Studio.app/Contents
L=$C/sdk/default/openharmony/toolchains/lib
J=$C/jbr/Contents/Home/bin
D=$(cd "$(dirname "$0")" && pwd)
IN=$1 OUT=$2 BUNDLE=${BUNDLE:-com.ohmarchy.display}
UDID=${UDID:?set UDID to the device id from `bm get --udid`}
python3 - "$L/UnsgnedDebugProfileTemplate.json" "$D/profile.json" "$BUNDLE" "$UDID" "$D/app-chain.pem" <<'P'
import json,sys
t=json.load(open(sys.argv[1]))
t["bundle-info"]["bundle-name"]=sys.argv[3]
t["debug-info"]["device-ids"]=[sys.argv[4]]
t["validity"]={"not-before":1700000000,"not-after":1893456000}
t["uuid"]="5f1f2c6e-6b0e-4f0a-9a52-0b3d8c1e7a11"
json.dump(t,open(sys.argv[2],"w"),indent=2)
open(sys.argv[5],"w").write(t["bundle-info"]["development-certificate"])
P
for a in "openharmony application ca" "openharmony application root ca"; do
  $J/keytool -exportcert -rfc -alias "$a" -keystore $L/OpenHarmony.p12 -storepass 123456 >> "$D/app-chain.pem"
done
$J/java -jar $L/hap-sign-tool.jar sign-profile -keyAlias "openharmony application profile debug" \
  -signAlg SHA256withECDSA -mode localSign -profileCertFile $L/OpenHarmonyProfileDebug.pem \
  -inFile "$D/profile.json" -keystoreFile $L/OpenHarmony.p12 -outFile "$D/app.p7b" -keyPwd 123456 -keystorePwd 123456
$J/java -jar $L/hap-sign-tool.jar sign-app -keyAlias "openharmony application release" \
  -signAlg SHA256withECDSA -mode localSign -appCertFile "$D/app-chain.pem" -profileFile "$D/app.p7b" \
  -inFile "$IN" -keystoreFile $L/OpenHarmony.p12 -outFile "$OUT" -keyPwd 123456 -keystorePwd 123456
