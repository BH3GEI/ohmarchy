Omarchy (Arch Linux ARM + Hyprland) as a whole OS in the Oseasy虚拟机 app on a
HarmonyOS PC, with linux-aarch64 7.2.12 and the patched vmwgfx driver for
Oseasy's SVGA device. How to install and what to expect:
[docs/oseasy-whole-os.md](../blob/main/docs/oseasy-whole-os.md).

Known limits: 60 Hz on screen (the guest renders at 120); Oseasy forgets the
VM at power-off, so each start is an install session; one VM at a time on the
whole machine (close 鸿融's VM and the Docker VM first).

**Draft.** Check the files before publishing. Licenses: LICENSES.md (the
repository is MIT, kernel-derived code GPL-2.0); the sources of the GPL and LGPL
packages in the disk image are attached (package-sources tar).
