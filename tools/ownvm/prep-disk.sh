#!/system/bin/sh
# Make route I's disk on the HarmonyOS host (root, no VM, no vm.lock): a sparse
# copy of agent-2a's verified omarchy-pure.img with a 120 Hz EDID for the
# virtio-gpu connector and the kernel argument that loads it.
#   perl -e 'alarm 3600; exec @ARGV' ssh ohdev sh -s [SRC [DST]] < tools/ownvm/prep-disk.sh
# Needs next to DST: ohmarchy-120.bin (tools/ownvm/mkedid.py) and edid.cpio
# (a newc cpio holding usr/lib/firmware/edid/ohmarchy-120.bin). Docker is
# installed later inside the running guest (pacman needs the guest).
#
# The host cannot mount this ext4: HongMeng's driver rejects its incompat
# features (0x22c2: "has unsupported incompat features"), so the root is edited
# with debugfs from route D's e2fsprogs (read-only use of its root) on a loop
# device at the partition's offset. The source image is only read.
SRC=${1:-/data/local/vmtest/work/out/omarchy-pure.img}
DST=${2:-/data/local/kaidashi/ownvm/omarchy-own.img}
DIR=$(dirname "$DST")
for f in ohmarchy-120.bin edid.cpio; do [ -r $DIR/$f ] || { echo "no $DIR/$f"; exit 1; }; done
R=/proc/$(cat /data/local/archtest/session.pid)/root
LD="$R/usr/lib/ld-linux-aarch64.so.1 --library-path $R/usr/lib"

if [ ! -f "$DST" ]; then
  echo "== sparse copy"
  PYTHONHOME=$R/usr nice -n 19 $LD $R/usr/bin/python3 /data/local/kaidashi/bin/slice.py \
    "$SRC" 0 $(stat -c %s "$SRC") "$DST.part" && mv "$DST.part" "$DST" || exit 1
fi

# offset of the Linux root partition (GPT entry 2) in bytes
OFF=$(PYTHONHOME=$R/usr $LD $R/usr/bin/python3 - "$DST" <<'P'
import struct, sys
f = open(sys.argv[1], 'rb'); f.seek(512); h = f.read(92)
lba, n, size = struct.unpack_from('<QII', h, 72)
f.seek(lba * 512)
for i in range(n):
    e = f.read(size)
    if i == 1: print(struct.unpack_from('<Q', e, 32)[0] * 512)
P
)
echo "root partition at byte $OFF"

L=; n=20
while [ $n -lt 64 ]; do losetup -o "$OFF" /dev/block/loop$n "$DST" 2>/dev/null && { L=/dev/block/loop$n; break; }; n=$((n+1)); done
[ -n "$L" ] || { echo "no free loop device"; exit 1; }
DBG() { $LD $R/usr/bin/debugfs "$@" $L; }

ARG='drm.edid_firmware=Virtual-1:edid/ohmarchy-120.bin'
T=$DIR/grub.cfg.tmp
DBG -R 'cat /boot/grub/grub.cfg' > $T 2>/dev/null
if grep -q "$ARG" $T; then
  echo "grub.cfg already has the EDID argument"
else
  sed -i "/^[[:space:]]*linux[[:space:]]/s|\$| $ARG|; /^[[:space:]]*initrd[[:space:]]/s|\$| /boot/ohmarchy-edid.cpio|" $T
  cat > $DIR/debugfs.cmds <<EOF
cd /boot
rm ohmarchy-edid.cpio
write $DIR/edid.cpio ohmarchy-edid.cpio
cd /boot/grub
rm grub.cfg
write $T grub.cfg
mkdir /usr/lib/firmware/edid
cd /usr/lib/firmware/edid
rm ohmarchy-120.bin
write $DIR/ohmarchy-120.bin ohmarchy-120.bin
mkdir /etc/mkinitcpio.conf.d
cd /etc/mkinitcpio.conf.d
rm ohmarchy-edid.conf
write $DIR/ohmarchy-edid.conf ohmarchy-edid.conf
EOF
  echo 'FILES+=(/usr/lib/firmware/edid/ohmarchy-120.bin)' > $DIR/ohmarchy-edid.conf
  DBG -w -f $DIR/debugfs.cmds 2>&1 | grep -vE '^debugfs [0-9]|^debugfs: (cd|mkdir)' | grep -v 'File not found by ext2_lookup' | head -20
fi
echo "== check"
DBG -R 'cat /boot/grub/grub.cfg' 2>/dev/null | grep -nE '^[[:space:]]*(linux|initrd)'
DBG -R 'ls -l /boot' 2>/dev/null | grep -E 'edid|initramfs'
DBG -R 'ls -l /usr/lib/firmware/edid' 2>/dev/null | grep ohmarchy
$LD $R/usr/bin/e2fsck -fn $L 2>&1 | tail -2
losetup -d $L
rm -f $T $DIR/debugfs.cmds
ls -ls "$DST"
