#!/bin/bash
# Put the proxy's env file (PROXY_VLESS_URL) into an internal disk image (never
# a public one): it goes to /etc/ohmarchy/proxy.env (root, 600), with
# guest/vless2singbox.py and the system unit
# firstboot/ohmarchy-proxy-setup.service, enabled here. At the next boot with
# sing-box installed, the unit writes /etc/sing-box/config.json, deletes the
# env file and enables sing-box. DIRECT_FILE (optional): domains that bypass the
# proxy, one per line, e.g. the AI relay's host; copied to
# /etc/ohmarchy/proxy-direct.txt. The image is changed in place with debugfs,
# nothing is mounted: work on a copy. Nothing secret is printed.
# Runs where debugfs and sfdisk exist (e.g. the native Arch environment).
# Usage: inject-proxy-env.sh RAW.img ENV_FILE [DIRECT_FILE]
set -euo pipefail
img=${1:?raw image}; env_file=${2:?env file}; direct=${3:-}
here=$(cd "$(dirname "$0")" && pwd)
grep -q '^PROXY_VLESS_URL=.' "$env_file" || { echo "no PROXY_VLESS_URL in $env_file"; exit 1; }
start=$(sfdisk -J "$img" | python3 -c 'import json,sys; print(json.load(sys.stdin)["partitiontable"]["partitions"][1]["start"])')
fs="$img?offset=$((start * 512))"
dfs() { debugfs "$@" "$fs" 2>/dev/null; }
cmds=$(mktemp); trap 'rm -f "$cmds"' EXIT
dfs -R "stat /etc/ohmarchy" | grep -q 'Type: directory' ||
  printf 'mkdir /etc/ohmarchy\nsif /etc/ohmarchy mode 040755\n' >> "$cmds"
put() { # put SRC DST MODE
  printf 'rm %s\nwrite %s %s\nsif %s uid 0\nsif %s gid 0\nsif %s mode %s\n' "$2" "$1" "$2" "$2" "$2" "$2" "$3" >> "$cmds"
}
put "$env_file" /etc/ohmarchy/proxy.env 0100600
[ -z "$direct" ] || put "$direct" /etc/ohmarchy/proxy-direct.txt 0100644
put "$here/guest/vless2singbox.py" /usr/local/lib/ohmarchy/vless2singbox.py 0100755
put "$here/firstboot/ohmarchy-proxy-setup.service" /etc/systemd/system/ohmarchy-proxy-setup.service 0100644
w=/etc/systemd/system/multi-user.target.wants/ohmarchy-proxy-setup.service
printf 'rm %s\nsymlink %s /etc/systemd/system/ohmarchy-proxy-setup.service\n' "$w" "$w" >> "$cmds"
debugfs -w -f "$cmds" "$fs" > /dev/null 2>&1
dfs -R "stat /etc/ohmarchy/proxy.env" | sed -n '1p;3p'
dfs -R "stat $w" | sed -n 1p
e2fsck -fn "$fs" > /dev/null 2>&1 && echo FSCK_OK || { echo "e2fsck found problems"; exit 1; }
