#!/bin/sh
# Put a disk image where 铠大师's VM can read it, for the installer's
# "Write Omarchy disk from the Documents share (virtiofs)" entry, or take it away.
# 铠大师 exports the HarmonyOS 文档 folder to every VM as virtiofs tag shared_dir.
# Run as root on the device:
#   perl -e 'alarm 3600; exec @ARGV' ssh ohdev sh -s put IMAGE < tools/kaidashi/stage-disk.sh
#   perl -e 'alarm 1800; exec @ARGV' ssh ohdev sh -s putraw IMAGE < tools/kaidashi/stage-disk.sh
#   perl -e 'alarm 60; exec @ARGV' ssh ohdev sh -s remove < tools/kaidashi/stage-disk.sh
# putraw keeps a sparse raw image sparse (wininspect/slice.py with route D's
# python, read-only use of its root) instead of compressing all of it.
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
  ls -l "$D/$N"; end=$(toybox date +%s); echo "staged in $((end - start)) s"
  ;;
putraw)
  img=${2:?image}
  [ -r "$img" ] || { echo "no $img"; exit 1; }
  R=/proc/$(cat /data/local/archtest/session.pid)/root
  start=$(toybox date +%s)
  PYTHONHOME=$R/usr $R/usr/lib/ld-linux-aarch64.so.1 --library-path $R/usr/lib \
    $R/usr/bin/python3 /data/local/kaidashi/bin/slice.py "$img" 0 $(stat -c %s "$img") "$D/ohmarchy-kds-disk.img.part" || exit 1
  mv "$D/ohmarchy-kds-disk.img.part" "$D/ohmarchy-kds-disk.img"
  chgrp file_manager "$D/ohmarchy-kds-disk.img" 2>/dev/null; chmod 644 "$D/ohmarchy-kds-disk.img"
  ls -ls "$D/ohmarchy-kds-disk.img"; end=$(toybox date +%s); echo "staged in $((end - start)) s"
  ;;
remove)
  rm -f "$D/$N" "$D/$N.part" "$D/ohmarchy-kds-disk.img" "$D/ohmarchy-kds-disk.img.part" && echo removed
  ls "$D" | grep -c ohmarchy-kds
  ;;
*) echo "usage: put IMAGE | putraw IMAGE | remove"; exit 1 ;;
esac
