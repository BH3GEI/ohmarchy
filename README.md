# ohmarchy: Omarchy on HarmonyOS

Running [Omarchy](https://omarchy.org) (Arch Linux + Hyprland) on a HarmonyOS PC,
driven from a Linux host over `hdc` (route D: from a root shell on the
machine; route F: on a Mac, with no HarmonyOS hardware). Developed on a HUAWEI MateBook Fold (HarmonyOS 7.0) with the
AArch64 Omarchy build from [riverscn/omarchy-aarch64-image](https://github.com/riverscn/omarchy-aarch64-image).
The current development machine (`ohdev`) is a HUAWEI MateBook 14 HM740 (HarmonyOS 7.0.0.115).

| Route | What runs on the HarmonyOS machine | Status |
|---|---|---|
| **A. Linux engine apps**: [docs/linux-engine-apps.md](docs/linux-engine-apps.md) | Omarchy's neovim setup and CLI tools inside HarmonyOS's Linux engine, each in a native HarmonyOS window | Works |
| **B. Whole OS in the Oseasy VM**: [docs/oseasy-whole-os.md](docs/oseasy-whole-os.md) | The complete Omarchy AArch64 OS (its disk, systemd, NetworkManager, SDDM) on a Debian 6.1 kernel in the Oseasy VM app | Boots, with text console and a network root shell; the Hyprland desktop is not displayed yet (see status). On the MateBook 14: Oseasy 3.1.1.7 surveyed (VirtualBox-style VMSVGA with a DXVK backend, qcow2 import); 7.2 kernel with the HMV ID-register quirk next |
| **C. Whole OS in the 鸿融 Linux VM**: [docs/hongrong-whole-os.md](docs/hongrong-whole-os.md) | Omarchy 4.0.6 (Arch Linux ARM) next to a deepin 25 guest in Huawei's Linux VM app, booting deepin's 6.6 kernel | Boots to the SDDM greeter and the Hyprland desktop, GPU-accelerated through virgl (OpenGL only) after 鸿融 starts the VM from cold |
| **D. Native on the HongMeng kernel**: [docs/native-chroot.md](docs/native-chroot.md) | Arch Linux ARM with Omarchy's packages in a chroot on the host itself (no VM), entered from a root shell | Omarchy's terminal side at native speed (shell, LazyVim, themes, btop, lazygit, mise), and Omarchy's Hyprland desktop in a HarmonyOS app ([docs/native-desktop.md](docs/native-desktop.md)): patched Hyprland rendering on the Maleoon GPU through the system's virglrenderer, presented into the app's window without a copy (workspace animations at up to the panel's 120 Hz); Wayland apps also show in route C's desktop via waypipe |
| **E. Bare metal**: (no doc yet) | Linux directly on the HarmonyOS PC's hardware, with no HarmonyOS underneath | Not started; nothing in this repo yet |
| **F. Whole OS in Aetherium on the DevEco emulator**: [docs/emulator-aetherium.md](docs/emulator-aetherium.md) | No HarmonyOS hardware: the complete Omarchy AArch64 OS in a patched Aetherium (QEMU TCG) on DevEco's HarmonyOS 7.0 PC emulator, shown in a HarmonyOS window by a native VNC client | Omarchy 4.0.3 on its own kernel through Limine, first-boot setup, and the Hyprland desktop (llvmpipe) started from a console because SDDM's greeter times out; all in software emulation, so slow |
| **G. Whole OS in the 铠大师 VM**: [docs/vm-kaidashi.md](docs/vm-kaidashi.md) | The complete Omarchy AArch64 disk (UEFI + GRUB, linux-aarch64 7.2 with the HMV ID-register quirk) in sanway's Windows-on-ARM VM app `com.sanway.ecoengine` | A VM boots a Linux ISO (fake `install.wim` passes its Windows-only check; Secure Boot off; no login needed). Same machine as Oseasy (`svga-pci`, no EDID, 800×600 EFI framebuffer), one VM at a time; the desktop waits on route B's SVGA work |
| **H. Aetherium on the device**: [docs/device-aetherium.md](docs/device-aetherium.md) | The same QEMU-in-a-HAP as route F, but on the real HarmonyOS PC (`ohdev`): a TCG baseline to the Hyprland desktop, plus an investigation of whether QEMU can use the HMV hypervisor for hardware acceleration | In progress: HMV interface decoded by static analysis (ioctl ABI reusing KVM magic 0xAE, not KVM-compatible); TCG baseline and acceleration test next |

<!-- progress:start -->
## Progress (updated hourly; last: 2026-10-24 01:25 PDT)

| Route | Now | Latest |
|---|---|---|
| B. Oseasy VM | Building the boot probe with the patched 7.2.12 kernel, then queueing for the VM slot to test whether `vmwgfx` surface blits refresh the Oseasy window | `vmwgfx` for the HarmonyOS SVGA device ported to 7.2 with refresh/vblank parameters and packaged; Oseasy holds one VM per app, so the existing Windows VM was backed up (sha256-verified) before any import |
| C. 鸿融 VM | Building an Omarchy-only disk (no deepin) with the new package, then testing it in a separate StratoVirt instance while the main VM is shut down | linux-aarch64 7.2.12 with the HMV ID-register patches packaged ([PKGBUILD](hongrong/kernel/)); earlier build kills traced to the native app-launch test cleaning up the build user's processes |
| D. Native | Sound: PipeWire to the HarmonyOS app's OHAudio renderer (code in, device test next); then performance (B) | A1 re-run with a system D-Bus (udisks2, polkit, upower only): 73 pass, 0 failed; A2 core operations: files, clipboard, Chinese input and the file chooser pass, sound pending |
| G. 铠大师 VM | First probe VM run: recording the real StratoVirt command line and devices, then restoring the 鸿融 main VM | The fake Windows 11 ISO passes 铠大师's check and boots a Linux console (efifb); no sign-in was needed |
| H. Aetherium on the device | Copying the Omarchy disk to `ohdev`; the patched Aetherium is installed | HMV decoded: its own ioctl ABI under KVM's 0xAE magic, not KVM-compatible; Aetherium's QEMU is TCG-only, so HMV acceleration would need a new QEMU accel backend ([feasibility](docs/device-aetherium.md)) |

VM tests share one HMV hypervisor and take turns (one VM at a time).
<!-- progress:end -->

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

The native desktop ([docs/native-desktop.md](docs/native-desktop.md)): run
`native/desktop/fetch-sources.sh` on a machine with GitHub access before copying
`native/`, then

```sh
sh /data/local/archtest/arch.sh run 40-install-desktop.sh builder   # patched aquamarine + Hyprland in /opt/ohmarchy
/data/local/archtest/bin/omarchy desktop start       # GPU via bin/vtest-broker and the app (native/vtest)
```

and install the app with `native/app/build.sh` (DevEco Studio's tools); open
"Omarchy (native)" on the HarmonyOS desktop.

Which apps and features work there: [docs/native-compat.md](docs/native-compat.md).

## Route F quick start

On a Mac (or any DevEco host) with DevEco Studio, `hdc`, `gh` and `python3`:

```sh
emulator/10-create-emulator.sh       # HarmonyOS 7.0 2in1 emulator image + instance, boot
emulator/20-fetch-inputs.sh          # Aetherium HAP (patched by emulator/lib/patch_aetherium.py), Omarchy qcow2, RemoteDesk
emulator/30-install.sh               # install the HAPs, copy the disk to 下载, forward VNC 15901 and serial 14321
emulator/40-create-vm.sh             # create and start the VM in Aetherium (UI driven by text)
emulator/50-first-boot.sh USER PASS  # answer Omarchy's first-boot wizard over VNC
emulator/60-desktop.sh USER PASS     # wait for the first-boot setup (15-50 min), boot straight into Hyprland
```

Details and the manual equivalents: [docs/emulator-aetherium.md](docs/emulator-aetherium.md).

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
tools/kbuild/      build out-of-tree arm64 modules against Debian headers with clang;
                   upstream kernel builds and an automated bisect for the 鸿融 VM
tools/ohdev/       ssh helper for a HarmonyOS host: screenshots, taps, key-by-key typing into VMs
hongrong/          route C: Arch bootstrap from deepin, Omarchy install, initcpio hook, configs
  kernel/patches/  patches for Omarchy's linux-aarch64 in 鸿融
tools/hongrong/    hrvm: remote power cycle of the 鸿融 VM and one-shot kernel boot tests
emulator/          route F: emulator, inputs, Aetherium patch (lib/), install, VM creation, first boot, desktop
  guest/           runs inside Omarchy: tty1 autologin into Hyprland, no SDDM, stay awake
tools/emu/         emulator UI over hdc: ui.py (tap/wait by visible text), ui.sh (taps, screenshots)
tools/vnc/         VNC frame grab and key injection (RFB, stdlib only)
tools/serial/      serial console: Limine menu, debug root shell, login.py, run.py (commands in a logged-in shell)
linux-engine/      route A install scripts (run inside the Linux engine container)
native/            route D: image build, session manager (arch.sh), launcher (omarchy), Arch + Omarchy setup
  desktop/         native Hyprland desktop: aquamarine/Hyprland patches, launcher, shims
  app/             HarmonyOS app showing it (ArkTS + C++, XComponent); sign.sh uses the SDK's test keys
  vtest/           vtest-broker (GPU connections to the app) and virgl_test_server (host-side GPU)
  vm/              waypipe receiver for route C's desktop
docs/
```

## License

`driver/` is derived from the Linux kernel and is GPL-2.0. Upstream projects
used by the scripts keep their own licenses.

## Route G quick start

Not runnable yet. Survey the app (read-only):

```sh
perl -e 'alarm 180; exec @ARGV' ssh ohdev sh -s < tools/kaidashi/probe.sh
tools/kaidashi/hap-survey.sh work/kaidashi   # static look at the HAP on a host
```

Details and status: [docs/vm-kaidashi.md](docs/vm-kaidashi.md).

## Route H quick start

On a host with `ssh ohdev` (HarmonyOS device, root), DevEco Studio and `python3`.
Coordinated and TCG-only for now (HMV acceleration is under investigation):

```sh
device/sign-hap.sh                 # sign the route-F patched Aetherium with the device debug profile
device/push-inputs.sh              # push the HAP and the Omarchy qcow2 to ohdev (one transfer at a time)
                                   #   big files: device/push-resumable.sh (the frps tunnel drops long streams)
device/install.sh                  # bm install the signed HAP as root
# create the VM and run it from the Aetherium window (see docs/device-aetherium.md)
```

Static HMV analysis uses `device/hmv/` and `device/ohsh` (run a script on the
device as root). Details and the acceleration findings:
[docs/device-aetherium.md](docs/device-aetherium.md).
