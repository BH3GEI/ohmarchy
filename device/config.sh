# Route H settings (sourced). Override in the environment.
: "${OHDEV:=ohdev}"                 # ssh host alias for the HarmonyOS device (root)
: "${BUNDLE:=com.caidingding233.qemuhmos}"
: "${DEV_DIR:=/data/local/tmp/routeh}"            # scratch on the device
: "${DEV_DOWNLOAD:=/storage/media/100/local/files/Docs/Download}"
ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
WORK=${WORK:-$ROOT/work/device}
mkdir -p "$WORK"
to() { perl -e 'alarm shift; exec @ARGV' "$@"; }   # hard timeout on every ssh
