# ohmarchy: Omarchy on HarmonyOS

Running [Omarchy](https://omarchy.org) (Arch Linux + Hyprland) on a HarmonyOS PC,
driven from a Linux host over `hdc` (route D: from a root shell on the
machine). Developed on a HUAWEI MateBook Fold (HarmonyOS 7.0) with the
AArch64 Omarchy build from [riverscn/omarchy-aarch64-image](https://github.com/riverscn/omarchy-aarch64-image).

| Route | What runs on the HarmonyOS machine | Status |
|---|---|---|
| **A. Linux engine apps**: [docs/linux-engine-apps.md](docs/linux-engine-apps.md) | Omarchy's neovim setup and CLI tools inside HarmonyOS's Linux engine, each in a native HarmonyOS window | Works |
| **B. Whole OS in the Oseasy VM**: [docs/oseasy-whole-os.md](docs/oseasy-whole-os.md) | The complete Omarchy AArch64 OS (its disk, systemd, NetworkManager, SDDM) on a Debian 6.1 kernel in the Oseasy VM app | Boots, with text console and a network root shell; the Hyprland desktop is not displayed yet (see status) |
| **C. Whole OS in the 鸿融 Linux VM**: [docs/hongrong-whole-os.md](docs/hongrong-whole-os.md) | Omarchy 4.0.6 (Arch Linux ARM) next to a deepin 25 guest in Huawei's Linux VM app, booting deepin's 6.6 kernel | Boots to the SDDM greeter and the Hyprland desktop, GPU-accelerated through virgl (OpenGL only) after 鸿融 starts the VM from cold |
| **D. Native on the HongMeng kernel**: [docs/native-chroot.md](docs/native-chroot.md) | Arch Linux ARM with Omarchy's packages in a chroot on the host itself (no VM), entered from a root shell | Omarchy's terminal side at native speed (shell, LazyVim, themes, btop, lazygit, mise); no GPU or DRM, so no native Hyprland, but Wayland apps show as windows in route C's desktop via waypipe |
| **E. Whole OS in Aetherium on the DevEco emulator**: [docs/emulator-aetherium.md](docs/emulator-aetherium.md) | No HarmonyOS hardware: the complete Omarchy AArch64 OS in a patched Aetherium (QEMU TCG) on DevEco's HarmonyOS 7.0 PC emulator, shown in a HarmonyOS window by a native VNC client | Boots Omarchy's own kernel through Limine to the first-boot wizard and setup on virtio-gpu, all in software emulation; the Hyprland desktop is not verified yet (setup stalls near the end) |

What was tried and why other paths fail: [docs/findings.md](docs/findings.md).

## Route B quick start

On a Linux host (`hdc` from the OpenHarmony SDK, USB debugging enabled on the
HarmonyOS machine):

```sh
oseasy/10-fetch-inputs.sh       # Omarchy image (3.7 GB), Debian 6.1 kernel debs, Debian netinst ISO
oseasy/20-build-modules.sh      # SVGA driver + efidrm module against Debian's 6.1 headers
oseasy/30-prepare-image.sh      # qcow2 -> raw, read the partition layout and root UUID
oseasy/40-build-boot.sh         # 6.1 boot entries (UKIs) + Limine menu into the image's ESP
oseasy/50-make-installer-iso.sh # Debian netinst ISO carrying the Omarchy disk image
oseasy/60-push-iso.sh           # copy the ISO to the HarmonyOS Download folder
```

Then follow the install steps in [docs/oseasy-whole-os.md](docs/oseasy-whole-os.md#install-in-oseasy).
Settings live in `oseasy/config.sh`; outputs go to `work/`.

Host tools: bash, python3, curl, unzip, bsdtar (libarchive), cpio, gzip,
qemu-img, sfdisk/blkid (util-linux), mtools, xorriso, kmod (depmod), make,
clang (with the `aarch64` target, any recent version), hdc.

## Route C quick start

In the 鸿融 VM: install deepin 25 (arm64), give it a static address on
`172.16.100.0/24`, then as root in deepin `hongrong/10-bootstrap-arch.sh USER PASSWORD`,
reboot, and in Arch `~USER/hongrong/20-install-omarchy.sh USER`. Details and
caveats: [docs/hongrong-whole-os.md](docs/hongrong-whole-os.md#install).

## Route D quick start

As root on the HarmonyOS machine (a root shell that may `unshare`, `mount` and
`chroot`; see [docs/native-chroot.md](docs/native-chroot.md#getting-a-root-shell-on-the-host)),
in a copy of `native/`:

```sh
sh 10-make-image.sh                                  # Arch Linux ARM into /data/local/archtest/arch.img
sh /data/local/archtest/arch.sh start
sh /data/local/archtest/arch.sh run 20-setup-arch.sh builder
sh /data/local/archtest/arch.sh stop; sh /data/local/archtest/arch.sh start
sh /data/local/archtest/arch.sh run 30-install-omarchy.sh builder
/data/local/archtest/bin/omarchy                     # Omarchy shell as builder
/data/local/archtest/bin/omarchy -g foot             # a window in route C's Hyprland (native/vm/route-d-display in the VM)
```

## Route E quick start

On a Mac (or any DevEco host) with DevEco Studio, `hdc`, `gh` and `python3`:

```sh
emulator/10-create-emulator.sh   # HarmonyOS 7.0 2in1 emulator image + instance, boot
emulator/20-fetch-inputs.sh      # Aetherium HAP (patched by emulator/lib/patch_aetherium.py), Omarchy qcow2, RemoteDesk
emulator/30-install.sh           # install the HAPs, copy the disk to 下载, forward VNC 15901 and serial 14321
```

Then create the VM in Aetherium as described in
[docs/emulator-aetherium.md](docs/emulator-aetherium.md#create-the-vm).

## Layout

```
oseasy/            build pipeline for route B (10..60), config, boot menu template
  initramfs/       overlay added to the 6.1 initramfs: network shell, GPU modes, first-boot module install
  installer/       scripts run in the Debian installer's rescue shell inside the VM
  lib/             uki.py (assemble UKIs), modsubset.py (module + dependency subset)
driver/
  vmwgfx-oseasy/   vmwgfx for the HarmonyOS SVGA device (indexed MMIO, display-unit selection)
  efidrm/          omarchy_efidrm: simpledrm on the EFI framebuffer for the Debian 6.1 kernel
tools/fold/        hdc helpers: screenshots, taps, keys, typing into the VM, guest shell, file copy
tools/kbuild/      build out-of-tree arm64 modules against Debian headers with clang
tools/ohdev/       ssh helper for a HarmonyOS host: screenshots, taps, key-by-key typing into VMs
hongrong/          route C: Arch bootstrap from deepin, Omarchy install, initcpio hook, configs
emulator/          route E: emulator setup, input fetch, Aetherium patch (lib/), install
tools/emu/         hdc UI helper for the emulator (taps, text, screenshots)
tools/vnc/         VNC frame grab and key injection (RFB, stdlib only)
tools/serial/      serial console: Limine menu renderer/driver, root shell runner
linux-engine/      route A install scripts (run inside the Linux engine container)
native/            route D: image build, session manager (arch.sh), launcher (omarchy), Arch + Omarchy setup
  vm/              waypipe receiver for route C's desktop
docs/
```

## License

`driver/` is derived from the Linux kernel and is GPL-2.0. Upstream projects
used by the scripts keep their own licenses.
