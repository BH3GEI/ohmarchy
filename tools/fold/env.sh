# Common settings for the Fold helpers (sourced).
# HDC: hdc binary from the OpenHarmony SDK (toolchains/hdc)
# HDC_TARGET: device id from `hdc list targets` (default: first connected device)
# OUT: where screenshots and temp files go
: "${HDC:=hdc}"
: "${OUT:=/tmp/ohmarchy}"
mkdir -p "$OUT"
if [ -z "${HDC_TARGET:-}" ]; then
    HDC_TARGET=$("$HDC" list targets 2>/dev/null | head -1)
    [ -n "$HDC_TARGET" ] && [ "$HDC_TARGET" != "[Empty]" ] || { echo "no hdc target" >&2; exit 1; }
fi
hs() {  # run a shell command on the Fold, retrying while USB re-negotiates
    local out i
    for i in $(seq 1 40); do
        out=$("$HDC" -t "$HDC_TARGET" shell "$1" 2>&1)
        echo "$out" | grep -q 'E001005\|not found or connected' || { echo "$out"; return 0; }
        sleep 1
    done
    echo "hdc unreachable: $out" >&2; return 1
}
