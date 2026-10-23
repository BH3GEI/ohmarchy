#!/usr/bin/env bash
# Download the HarmonyOS 7.0 2in1 emulator image, create the instance and boot it.
# Accept the emulator licenses yourself first: "$EMULATOR" -license
set -euo pipefail
. "$(dirname "$0")/config.sh"

# The CLI refuses image downloads unless DevEco's country/region is the Chinese mainland
# ("Currently, this capability is available only in the Chinese mainland."). The check reads
# this file locally, before any network request; the download itself also needs a CN egress.
for f in "$HOME"/Library/Application\ Support/Huawei/DevEcoStudio*/options/country.region.xml \
         "${APPDATA:-/nonexistent}"/Huawei/DevEcoStudio*/options/country.region.xml \
         "$HOME"/.config/Huawei/DevEcoStudio*/options/country.region.xml; do
    [ -f "$f" ] || continue
    grep -q 'countryregion name="CN"' "$f" && continue
    echo "DevEco region is not CN in: $f" >&2
    echo "  set it in DevEco Studio, or: cp \"$f\" \"$f.bak\" && sed -i.tmp 's/countryregion name=\"[A-Z]*\"/countryregion name=\"CN\"/' \"$f\"" >&2
    exit 1
done

if ! "$EMULATOR" -imageList -downloaded true 2>/dev/null | grep -q '"deviceType": "2in1"'; then
    "$EMULATOR" -install -deviceType 2in1 -osVersion "$EMU_OS" -force \
        ${EMU_HTTP_PROXY:+-http_proxy "$EMU_HTTP_PROXY"}
fi

if ! "$EMULATOR" -list 2>/dev/null | grep -qx "$EMU_NAME"; then
    "$EMULATOR" -create "$EMU_NAME" -deviceType 2in1 -osVersion "$EMU_OS" \
        -memory "$EMU_MEMORY_GB" -storage "$EMU_STORAGE_GB"
    # -create has no CPU option
    sed -i.bak "s/^hw.cpu.ncore=.*/hw.cpu.ncore=$EMU_CPUS/" "$EMU_INSTANCES/$EMU_NAME/config.ini"
fi

running=$("$EMULATOR" -list -details 2>/dev/null | python3 -I -c '
import json, sys
print(any(d.get("name") == sys.argv[1] and d.get("isRunning") == "true" for d in json.load(sys.stdin)))' "$EMU_NAME")
if [ "$running" = True ]; then
    echo "$EMU_NAME is already running"
else
    nohup "$EMULATOR" -start "$EMU_NAME" >"$WORK/emulator.log" 2>&1 &
fi
for _ in $(seq 1 120); do
    t=$(emu_target 2>/dev/null) &&
        [ "$("$HDC" -t "$t" shell param get bootevent.boot.completed 2>/dev/null | tr -d '\r ')" = true ] &&
        { echo "booted: $t"; exit 0; }
    sleep 5
done
echo "emulator did not finish booting, see $WORK/emulator.log" >&2; exit 1
