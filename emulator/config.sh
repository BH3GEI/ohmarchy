# Route E settings (sourced by emulator/*.sh). Override any of them in the environment.

# DevEco Studio's emulator CLI (macOS path; on Windows/Linux point it at tools/emulator/Emulator)
: "${EMULATOR:=/Applications/DevEco-Studio.app/Contents/tools/emulator/Emulator}"
: "${HDC:=hdc}"
# Emulator instance: HarmonyOS 7.0 "2in1" (PC) image
: "${EMU_NAME:=ohm2in1}"
: "${EMU_OS:=HarmonyOS 7.0.0(26.0.0)}"
: "${EMU_MEMORY_GB:=16}"
: "${EMU_STORAGE_GB:=64}"
: "${EMU_CPUS:=8}"
: "${EMU_INSTANCES:=$HOME/.Huawei/Emulator/deployed}"
# Image download is limited to the Chinese mainland: optional proxy for the -install step only
: "${EMU_HTTP_PROXY:=}"

# Aetherium (QEMU-in-a-HAP) test release, patched by lib/patch_aetherium.py
AETH_REPO=AetheriumSimulator/qemu-hmos
AETH_TAG=test-14456eb66216095c52ec3e3d81f59abcab17e5f3
AETH_HAP=aetherium-unsigned.hap
AETH_SHA256=9396c90d39395d4407ef7d27ad1730f6f738bc4c10f85f7a3293293fd6626003
AETH_BUNDLE=com.caidingding233.qemuhmos

# Omarchy AArch64 VM image (UTM bundle with a qcow2)
OMARCHY_REPO=riverscn/omarchy-aarch64-image
OMARCHY_TAG=v4.0.3-virt.1
OMARCHY_ZIP_SHA256=0db7dc92cc77e4868c62125b4219da680740f7ad7a0ededcaa565bb10f595ece

# HarmonyOS-native VNC client used to show the VM inside HarmonyOS (optional)
RD_REPO=Mydstiny/RemoteDesktopHarmonyOS
RD_TAG=v1.2.2-unsigned.1
RD_HAP=RemoteDesk-1.2.2-1001010-debug-unsigned.hap
RD_SHA256=92bb490ec7b5d93d2282690e301b8bc36e375069fad833509c7c6c276e64fa13

# Paths inside the emulator
DEV_DOWNLOAD=/storage/media/100/local/files/Docs/Download

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
WORK=${WORK:-$ROOT/work/emulator}
mkdir -p "$WORK"

emu_target() {  # hdc target of the running emulator (127.0.0.1:PORT), never a USB device
    "$HDC" list targets 2>/dev/null | grep -m1 '^127\.0\.0\.1:' || { echo "emulator not connected to hdc" >&2; return 1; }
}
sha_check() {  # sha_check FILE SHA256
    local got; got=$(shasum -a 256 "$1" | cut -d' ' -f1)
    [ "$got" = "$2" ] || { echo "sha256 mismatch for $1: $got" >&2; return 1; }
}
