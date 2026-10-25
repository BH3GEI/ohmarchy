#!/usr/bin/env bash
# hilog) AND kernel-side (new dmesg avc/xpm for the probe's pid) evidence. Read-only wrt
set -uo pipefail
. "$(dirname "$0")/../config.sh"
HAP=${1:?path to signed xpmprobe.hap}
to 120 ssh -o ConnectTimeout=20 "$OHDEV" 'cat > /data/local/tmp/xpmprobe.hap' < "$HAP"
"$(dirname "$0")/../ohsh" -t 140 - <<'SH'
set -u