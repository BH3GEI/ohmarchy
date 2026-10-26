**试用版 / trial build: 不保存状态。在 Omarchy 里重启，数据还在；关机以后，OSEasy 只给"再次安装"，它会先清空硬盘再重装，所以数据不保留，每次重新开始都是一个全新的系统。窗口内 120Hz（Hyprland / fastfetch 报告）。在 OSEasy 里是固定大小的浮动窗口，不能全屏，也不能最大化。**
Trial build: nothing is kept. A reboot inside Omarchy keeps your data; after a
power-off OSEasy only offers "reinstall", which wipes the disk and installs again,
so every new start is a fresh system. 120 Hz inside the window (as Hyprland and fastfetch report
it). In OSEasy the VM is a fixed-size floating window: no fullscreen, no maximize.

Omarchy (Arch Linux ARM + Hyprland) as a whole OS in the OSEasy虚拟机 app on a
HarmonyOS PC, with linux-aarch64 7.2.12 and the patched vmwgfx driver for
OSEasy's SVGA device. The disk image is inside the install ISO: download the ISO
(join its parts first if it is split, see below) and install it in OSEasy.

- 安装说明（给普通用户，不需要 root）/ How to install: [docs/oseasy-install.md](../blob/main/docs/oseasy-install.md)
- 技术细节 / Technical notes: [docs/oseasy-whole-os.md](../blob/main/docs/oseasy-whole-os.md)

Known limits: a fixed-size floating window (no fullscreen or maximize); after a
power-off OSEasy only reinstalls (the disk is wiped), so each new start is a
fresh system; one VM at a
time on the whole machine (close 鸿融's VM first; the Docker VM of the native
desktop stops by itself 30 s after use).

**Draft.** Check the files before publishing. Licenses: LICENSES.md (the
repository is MIT, kernel-derived code GPL-2.0); the sources of the GPL and LGPL
packages in the disk image are attached (package-sources tar, in parts).
