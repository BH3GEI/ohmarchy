#!/bin/bash
# Static survey of the 铠大师 HAP on a Mac/Linux host (no device changes).
#   tools/kaidashi/hap-survey.sh [workdir]
# Copies entry.hap off ohdev, unpacks it without the 441 MB guest-tools ISO and
# prints the manifest, the bundled Secure Boot certificates, the native exports
# and the resource/bytecode strings behind the ISO check and the VM API.
set -euo pipefail
W=${1:-work/kaidashi}
H=/data/app/el1/bundle/public/com.sanway.ecoengine/entry.hap
mkdir -p "$W/x"
[ -f "$W/entry.hap" ] || perl -e 'alarm 900; exec @ARGV' ssh -o BatchMode=yes ohdev "cat $H" > "$W/entry.hap"
md5sum "$W/entry.hap" 2>/dev/null || md5 "$W/entry.hap"
unzip -o -q "$W/entry.hap" -x resources/rawfile/server.iso -d "$W/x"
unzip -l "$W/entry.hap" | sort -k1 -n -r | head -8

echo "== manifest"
python3 - "$W/x/module.json" <<'PY'
import json,sys
m=json.load(open(sys.argv[1]))
a=m['app']; print(a['bundleName'],a['versionName'],a['vendor'],'target',a['targetAPIVersion'])
mo=m['module']; print('main',mo['mainElement'])
print('perms',[p['name'].split('.')[-1] for p in mo['requestPermissions']])
for x in mo.get('abilities',[]): print('ability',x['name'])
PY

echo "== Secure Boot certificates (rawfile/securityBoot)"
for c in "$W"/x/resources/rawfile/securityBoot/*.cer; do
  echo "$(basename $c): $(openssl x509 -in $c -noout -subject)"
done

echo "== native code"
strings -n 5 "$W/x/libs/arm64-v8a/libentry.so" | grep -E 'ExtractWim|sources/install.wim|GenIso|extractwim.cpp' | sort -u

echo "== bytecode strings (ets/modules.abc; ark_disasm refuses it: checksum/offsets corrupted on purpose)"
strings -n 5 "$W/x/ets/modules.abc" > "$W/abc.txt"
grep -E '@hms:virtService|Not support vm multi-instance|accelerationEnabled|biosPath|dbContent|getGraphicDevice|CheckISOVersion|WIMInfoDefined|<ARCH>12|10\.0\.26100|SUPPORT_WINDOWS_24H2|RefreshRate|Windows_install.iso|checkKiddo|NoVip' "$W/abc.txt" | sort -u

echo "== resource strings (resources.index)"
python3 - "$W/x/resources.index" <<'PY'
import re,sys
d=open(sys.argv[1],'rb').read()
keys=['镜像校验','仅支持Windows','已有虚拟机','镜像被修改','路径不可以含有空格','铠大师虚拟机','试用','会员','外接显示器']
for s in sorted(set(re.findall(rb'[^\x00-\x1f]{6,}',d))):
    t=s.decode('utf-8','ignore')
    if any(k in t for k in keys): print(t[:160])
PY
