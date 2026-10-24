#!/bin/sh
# Put a disk image where 铠大师's VM can read it, for the installer's
# "Write Omarchy disk from the Documents share (virtiofs)" entry, or take it away.
# 铠大师 exports the HarmonyOS 文档 folder to every VM as virtiofs tag shared_dir.
# Run as root on the device:
#   perl -e 'alarm 3600; exec @ARGV' ssh ohdev sh -s put IMAGE < tools/kaidashi/stage-disk.sh
#   perl -e 'alarm 60; exec @ARGV' ssh ohdev sh -s remove < tools/kaidashi/stage-disk.sh
# IMAGE is raw (gzip-compressed on the way, so sparse zeros cost nothing) or
# already .gz. 文档 is the owner's personal folder: remove the file right after
# the write.
D=/storage/media/100/local/files/Docs/Documents
N=ohmarchy-kds-disk.img.gz
case ${1:-} in
put)
  img=${2:?image}
  [ -r "$img" ] || { echo "no $img"; exit 1; }
  start=$(toybox date +%s)
  case $img in
    *.gz) cp "$img" "$D/$N.part" ;;
    *) toybox gzip -1 -c "$img" > "$D/$N.part" ;;
  esac || exit 1
  mv "$D/$N.part" "$D/$N"
  chgrp file_manager "$D/$N" 2>/dev/null; chmod 644 "$D/$N"
  ls -l "$D/$N"; echo "staged in $(( $(toybox date +%s) - start )) s"
  ;;
remove)
  rm -f "$D/$N" "$D/$N.part" "$D/ohmarchy-kds-disk.img" && echo removed
  ls "$D" | grep -c ohmarchy-kds
  ;;
*) echo "usage: put IMAGE | remove"; exit 1 ;;
esac
