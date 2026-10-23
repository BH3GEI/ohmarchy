# Settings for the native route (sourced by native/10-make-image.sh on the
# HarmonyOS host). Every value can be overridden from the environment.
: "${ARCH_BASE:=/data/local/archtest}"   # image, mount point, session state, bin/omarchy
: "${ARCH_IMG_SIZE:=64G}"                # sparse ext4 image holding the Arch root
: "${ALARM_URL:=https://mirrors.tuna.tsinghua.edu.cn/archlinuxarm/os/ArchLinuxARM-aarch64-latest.tar.gz}"
