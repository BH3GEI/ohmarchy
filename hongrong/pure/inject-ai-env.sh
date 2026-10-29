#!/bin/bash
# Put the AI relay's env file into an internal disk image (never a public one):
# ENV_FILE goes to ~USER/.config/ohmarchy/ai.env (600), and the user unit
# firstboot/ohmarchy-ai-import.service, enabled here, runs guest/setup-ai.sh
# with it at the next login and deletes it. The image is changed in place with
# debugfs, nothing is mounted: work on a copy. The key is read from ENV_FILE
# and written only into the image; nothing is printed.
# Runs where debugfs and sfdisk exist (e.g. the native Arch environment).
# Usage: inject-ai-env.sh RAW.img ENV_FILE [USER, default omarchy]
#   RAW.img  a raw disk with the root filesystem in partition 2
set -euo pipefail
img=${1:?raw image}; env_file=${2:?env file}; user=${3:-omarchy}
here=$(cd "$(dirname "$0")" && pwd)
for v in OHM_AI_KEY OHM_AI_BASE OHM_AI_BASE_V1; do
  grep -q "^$v=." "$env_file" || { echo "no $v in $env_file"; exit 1; }
done
start=$(sfdisk -J "$img" | python3 -c 'import json,sys; print(json.load(sys.stdin)["partitiontable"]["partitions"][1]["start"])')
fs="$img?offset=$((start * 512))"
dfs() { debugfs "$@" "$fs" 2>/dev/null; }
pw=$(dfs -R "cat /etc/passwd" | grep "^$user:") || { echo "no user $user in the image"; exit 1; }
uid=$(echo "$pw" | cut -d: -f3); gid=$(echo "$pw" | cut -d: -f4); home=$(echo "$pw" | cut -d: -f6)
dfs -R "stat /usr/local/lib/ohmarchy/setup-ai.sh" | grep -q 'Type: regular' || { echo "no setup-ai.sh in the image"; exit 1; }
u=$home/.config/systemd/user
cmds=$(mktemp); trap 'rm -f "$cmds"' EXIT
for d in "$home/.config" "$home/.config/ohmarchy" "$home/.config/systemd" "$u" "$u/default.target.wants"; do
  dfs -R "stat $d" | grep -q 'Type: directory' && continue
  printf 'mkdir %s\nsif %s uid %s\nsif %s gid %s\nsif %s mode 040755\n' "$d" "$d" "$uid" "$d" "$gid" "$d" >> "$cmds"
done
cat >> "$cmds" <<CMDS
rm $home/.config/ohmarchy/ai.env
write $env_file $home/.config/ohmarchy/ai.env
sif $home/.config/ohmarchy/ai.env uid $uid
sif $home/.config/ohmarchy/ai.env gid $gid
sif $home/.config/ohmarchy/ai.env mode 0100600
sif $home/.config/ohmarchy mode 040700
rm $u/ohmarchy-ai-import.service
write $here/firstboot/ohmarchy-ai-import.service $u/ohmarchy-ai-import.service
sif $u/ohmarchy-ai-import.service uid $uid
sif $u/ohmarchy-ai-import.service gid $gid
sif $u/ohmarchy-ai-import.service mode 0100644
rm $u/default.target.wants/ohmarchy-ai-import.service
symlink $u/default.target.wants/ohmarchy-ai-import.service ../ohmarchy-ai-import.service
CMDS
debugfs -w -f "$cmds" "$fs" > /dev/null 2>&1
dfs -R "stat $home/.config/ohmarchy/ai.env" | sed -n '1p;3p'
dfs -R "stat $u/default.target.wants/ohmarchy-ai-import.service" | sed -n 1p
e2fsck -fn "$fs" > /dev/null 2>&1 && echo FSCK_OK || { echo "e2fsck found problems"; exit 1; }
