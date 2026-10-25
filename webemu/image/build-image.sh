#!/bin/bash
# Build the route L guest: Arch Linux 32 (i686) with pacman, systemd and Arch's own
# kernel, as an ext4 disk image plus the kernel and initramfs for v86.
# Runs in an Alpine container of the host's own architecture (pacman there is
# native); the package scriptlets and mkinitcpio run i686 code in the new root,
# so docker needs qemu-user binfmt for linux/386 (colima on a Mac has it).
# Files go in and out with `docker cp`, so no bind mount is needed. Output: webemu/image/out/{arch32.img,vmlinuz,initramfs.img}
#   DOCKER_HOST  docker socket (colima: unix://$HOME/.colima/default/docker.sock)
#   IMG_MB       disk image size in MiB (default: rootfs size x 1.3 + 256)
set -e
cd "$(dirname "$0")"
mkdir -p out
N=routel-image-$$
docker create --name $N --privileged -e IMG_MB="${IMG_MB:-}" \
  alpine:3.20 sh /w/inside.sh > /dev/null
trap 'docker rm -f $N > /dev/null' EXIT
docker cp . $N:/w
docker start -a $N
for f in arch32.img vmlinuz initramfs.img; do docker cp $N:/w/out/$f out/$f; done
ls -la out
