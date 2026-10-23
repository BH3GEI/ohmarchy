#!/usr/bin/env bash
# Install the patched Aetherium (and RemoteDesk) and copy the Omarchy disk to the Download folder.
# The emulator accepts unsigned HAPs; a real device needs them signed with your own profile.
set -euo pipefail
. "$(dirname "$0")/config.sh"
cd "$WORK"
T=$(emu_target)

"$HDC" -t "$T" install -r aetherium-patched.hap
[ -f "$RD_HAP" ] && "$HDC" -t "$T" install -r "$RD_HAP"
"$HDC" -t "$T" file send omarchy-aarch64-virt.qcow2 "$DEV_DOWNLOAD/omarchy-aarch64-virt.qcow2"
# small file the throw-away VM in 40-create-vm.sh picks as its ISO (creates Aetherium's dirs)
printf 'ohmarchy\n' > aetherium-init.txt
"$HDC" -t "$T" file send aetherium-init.txt "$DEV_DOWNLOAD/aetherium-init.txt"
# VM console ports on the Mac: VNC 5901 -> 15901, first serial port 4321 -> 14321
"$HDC" -t "$T" fport tcp:15901 tcp:5901
"$HDC" -t "$T" fport tcp:14321 tcp:4321
echo "next: emulator/40-create-vm.sh"
