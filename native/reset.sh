#!/system/bin/sh
# One-command reset of route D to a clean, just-installed environment (as root on
# the HarmonyOS host):
#   sh reset.sh snapshot   keep the current image as the clean one (install.sh does
#                          this after a fresh install); stops the session first
#   sh reset.sh            stop the desktop and session, replace arch.img with the
#                          clean copy, start the session again
#   sh reset.sh status     sizes and dates of both
# The user's files live in the image, so a reset loses them: copy what you need out
# of $ARCH_BASE/arch/home first (with the session running, under /proc/PID/root).
B=${ARCH_BASE:-$(cd "$(dirname "$0")" && pwd)}
IMG=$B/arch.img
CLEAN=$B/arch-clean.img

copy() {  # sparse copy (bin/sparsecp, from sparsecp.c): toybox cp and dd fill the holes
    "$B/bin/sparsecp" "$1" "$2.tmp" && mv "$2.tmp" "$2"
}

case "${1:-reset}" in
snapshot)
    sh "$B/arch.sh" stop > /dev/null 2>&1
    copy "$IMG" "$CLEAN" && echo "clean image: $CLEAN ($(du -h "$CLEAN" | cut -f1) used)"
    sh "$B/arch.sh" start ;;
reset)
    [ -f "$CLEAN" ] || { echo "no clean image ($CLEAN): run 'reset.sh snapshot' after installing"; exit 1; }
    [ -x "$B/bin/omarchy" ] && sh "$B/bin/omarchy" desktop stop > /dev/null 2>&1
    sh "$B/arch.sh" stop
    copy "$CLEAN" "$IMG" && echo "arch.img reset from $CLEAN"
    sh "$B/arch.sh" start ;;
status)
    ls -la "$IMG" "$CLEAN" 2>&1
    du -h "$IMG" "$CLEAN" 2>/dev/null ;;
*)
    echo "usage: reset.sh [snapshot|reset|status]" >&2; exit 2 ;;
esac
