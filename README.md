# ohmarchy: Omarchy on HarmonyOS

Running [Omarchy](https://omarchy.org) (Arch Linux + Hyprland) on a HarmonyOS PC,
driven from a Linux host over `hdc` (route D: from a root shell on the
machine; route F: on a Mac, with no HarmonyOS hardware). Developed on a HUAWEI MateBook Fold (HarmonyOS 7.0) with the
AArch64 Omarchy build from [riverscn/omarchy-aarch64-image](https://github.com/riverscn/omarchy-aarch64-image).
The current development machine (`ohdev`) is a HUAWEI MateBook 14 HM740 (HarmonyOS 7.0.0.115).

| Route | What runs on the HarmonyOS machine | Status |
|---|---|---|
| **A. Linux engine apps**: [docs/linux-engine-apps.md](docs/linux-engine-apps.md) | Omarchy's neovim setup and CLI tools inside HarmonyOS's Linux engine, each in a native HarmonyOS window | Works |
| **B. Whole OS in the Oseasy VM**: [docs/oseasy-whole-os.md](docs/oseasy-whole-os.md) | The complete Omarchy AArch64 OS (its disk, systemd, NetworkManager, SDDM) on a Debian 6.1 kernel in the Oseasy VM app | Boots, with text console and a network root shell; the Hyprland desktop is not displayed yet (see status). On the MateBook 14: Linux 7.2 boots in Oseasy (HMV ID-register quirk) and vmwgfx-oseasy shows GPU-rendered KMS output (Mesa SVGA3D) in the window at 120 frames/s from the guest (panel stays 60 Hz); Omarchy disk next |
| **C. Whole OS in the 鸿融 Linux VM**: [docs/hongrong-whole-os.md](docs/hongrong-whole-os.md) | Omarchy 4.0.6 (Arch Linux ARM) next to a deepin 25 guest in Huawei's Linux VM app, booting deepin's 6.6 kernel | Boots to the SDDM greeter and the Hyprland desktop, GPU-accelerated through virgl (OpenGL only) after 鸿融 starts the VM from cold |
| **D. Native on the HongMeng kernel**: [docs/native-chroot.md](docs/native-chroot.md) | Arch Linux ARM with Omarchy's packages in a chroot on the host itself (no VM), entered from a root shell | Omarchy's terminal side at native speed (shell, LazyVim, themes, btop, lazygit, mise), and Omarchy's Hyprland desktop in a HarmonyOS app ([docs/native-desktop.md](docs/native-desktop.md)): patched Hyprland rendering on the Maleoon GPU through the system's virglrenderer, presented into the app's window without a copy (workspace animations at up to the panel's 120 Hz); Wayland apps also show in route C's desktop via waypipe |
| **E. Bare metal**: (no doc yet) | Linux directly on the HarmonyOS PC's hardware, with no HarmonyOS underneath | Not started; nothing in this repo yet |
| **F. Whole OS in Aetherium on the DevEco emulator**: [docs/emulator-aetherium.md](docs/emulator-aetherium.md) | No HarmonyOS hardware: the complete Omarchy AArch64 OS in a patched Aetherium (QEMU TCG) on DevEco's HarmonyOS 7.0 PC emulator, shown in a HarmonyOS window by a native VNC client | Omarchy 4.0.3 on its own kernel through Limine, first-boot setup, and the Hyprland desktop (llvmpipe) started from a console because SDDM's greeter times out; all in software emulation, so slow |
| **G. Whole OS in the 铠大师 VM**: [docs/vm-kaidashi.md](docs/vm-kaidashi.md) | The complete Omarchy AArch64 disk (UEFI + GRUB, linux-aarch64 7.2 with the HMV ID-register quirk) in sanway's Windows-on-ARM VM app `com.sanway.ecoengine` | A VM boots a Linux ISO (fake `install.wim` passes its Windows-only check; Secure Boot off; no login needed). Same machine as Oseasy (`svga-pci`, no EDID, 800×600 EFI framebuffer), one VM at a time; the desktop waits on route B's SVGA work |
| **H. Aetherium on the device**: [docs/device-aetherium.md](docs/device-aetherium.md) | The same QEMU-in-a-HAP as route F, but on the real HarmonyOS PC (`ohdev`): a TCG baseline to the Hyprland desktop, plus an investigation of whether QEMU can use the HMV hypervisor for hardware acceleration | In progress: HMV interface decoded by static analysis (ioctl ABI reusing KVM magic 0xAE, not KVM-compatible); TCG baseline and acceleration test next |

<!-- progress:start -->
## Progress (updated hourly; last: 2026-10-24 04:25 PDT)

| Route | Now | Latest |
|---|---|---|
| B. Oseasy VM | Next in the VM slot: stream the Omarchy-only disk into the Oseasy VM, then Hyprland, glmark2/es2gears against 鸿融's virgl, workspace fps, cold-boot time | GPU-rendered KMS output now shows in the Oseasy window (Mesa SVGA3D, GL ES 3.0, hardware 3D); the guest renders 120 fps but the host panel stays at 60 Hz, so 60 reach the screen |
| C. 鸿融 VM | Stage 1 of the Omarchy-only disk test: three warm reboots over the serial console; network for hand-started VMs next (鸿融 removes its bridge when it stops) | Omarchy-only disk (Omarchy 4.0.6, linux-aarch64 7.2.12 with the HMV patches, pacman-owned modules) cold-boots to `omarchy login:` in under 2 minutes in a headless StratoVirt started by root on `/dev/hmv` |
| D. Native | One-command install and reset into a second environment (`native/install.sh`, `reset.sh`); Chromium sandbox investigation | Exclusive measurement: workspace switching 119.4 fps; display app idle CPU 1.9% of a core (was 14%); background/foreground 20/20; for the same CPU the native desktop shows about twice the frames of the VM |
| G. 铠大师 VM | After Oseasy: test whether the installer's own power-off counts as "install finished", so the VM is kept and later starts with a full network | Root cause of the dead guest network: 铠大师's install session uses a hard-coded virtio-net with no `mac` or iothreads; normal starts add both |
| H. Aetherium on the device | Repairing 37 corrupted 64 MiB blocks of the copied disk in place, then the TCG baseline | Static answers: no virgl/venus and no 120 Hz path in Aetherium's QEMU; HMV create-VM permission probe ready for the VM slot |

Two locks on the device: `vm.lock` for the HMV hypervisor (one VM at a time) and `screen.lock` for the foreground; work that needs neither runs in parallel.
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
