#!/system/bin/sh
# Run as root on the HarmonyOS host from this directory. Downloads Arch Linux
# ARM, builds $ARCH_BASE/arch.img (sparse ext4) from it, and installs arch.sh
# and the arch launcher. Usage: sh 10-make-image.sh
set -e
here=$(cd "$(dirname "$0")" && pwd)
. "$here/config.sh"
B=$ARCH_BASE
IMG=$B/arch.img

[ -e "$IMG" ] && { echo "$IMG exists, not touching it"; exit 1; }
mkdir -p "$B/dl" "$B/arch" "$B/bin"

# 1. Arch Linux ARM tarball
t=$B/dl/alarm.tar.gz
if [ ! -f "$t" ] || ! md5sum -c "$t.md5" > /dev/null 2>&1; then
    curl -fL -C - -o "$t" "$ALARM_URL"
    curl -fsL "$ALARM_URL.md5" | sed "s|  .*|  $t|" > "$t.md5"
fi
md5sum -c "$t.md5"

# 2. Sparse ext4 image, filled in a throwaway mount namespace. The root has to
#    be a mount point anyway (pacman's CheckSpace).
truncate -s "$ARCH_IMG_SIZE" "$IMG"
mke2fs -t ext4 -q -F "$IMG"
unshare -m sh -c '
set -e
n=0
until losetup "/dev/block/loop$n" "$1" 2>/dev/null; do
    n=$((n+1)); [ -b "/dev/block/loop$n" ]
done
L=/dev/block/loop$n
mount -t ext4 "$L" "$2"
tar -xpzf "$3" -C "$2"
sync
umount "$2"
# Usually already detached by the umount here.
losetup -d "$L" 2>/dev/null || true
' sh "$IMG" "$B/arch" "$t"

# 3. Session manager and launcher
cp "$here/arch.sh" "$B/arch.sh"
cp "$here/omarchy" "$B/bin/omarchy"
chmod 755 "$B/arch.sh" "$B/bin/omarchy"
echo "Done. Next: sh $B/arch.sh start; sh $B/arch.sh run $here/20-setup-arch.sh USER"
