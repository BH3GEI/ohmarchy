# ohmarchy: Omarchy on HarmonyOS

English | [中文](README.zh-CN.md)

Running [Omarchy](https://omarchy.org) (Arch Linux + Hyprland) on a HarmonyOS PC,
driven from a Linux host over `hdc` (route D: from a root shell on the
machine; route F: on a Mac, with no HarmonyOS hardware). Developed on a HUAWEI MateBook Fold (HarmonyOS 7.0) with the
AArch64 Omarchy build from [riverscn/omarchy-aarch64-image](https://github.com/riverscn/omarchy-aarch64-image).
The current development machine (`ohdev`) is a HUAWEI MateBook 14 HM740 (HarmonyOS 7.0.0.115).

| Route | What runs on the HarmonyOS machine | Status |
|---|---|---|
| **A. Linux engine apps**: [docs/linux-engine-apps.md](docs/linux-engine-apps.md) | Omarchy's neovim setup and CLI tools inside HarmonyOS's Linux engine, each in a native HarmonyOS window | Works |
| **B. Whole OS in the Oseasy VM**: [docs/oseasy-whole-os.md](docs/oseasy-whole-os.md) | The complete Omarchy AArch64 OS (its disk, systemd, NetworkManager, SDDM) on a Debian 6.1 kernel in the Oseasy VM app | Boots, with text console and a network root shell; the Hyprland desktop is not displayed yet (see status). On the MateBook 14: Omarchy's own disk (7.2 + vmwgfx-oseasy) boots in Oseasy and Hyprland runs on Mesa SVGA3D (GPU), not yet presenting; GPU-rendered KMS output shows at 120 frames/s, and a small visible window voting 120 Hz ([ohmarchy-120](oseasy/vote120/)) takes the panel to 120 Hz without changing Oseasy |
| **C. Whole OS in the 鸿融 Linux VM**: [docs/hongrong-whole-os.md](docs/hongrong-whole-os.md) | Omarchy 4.0.6 (Arch Linux ARM) next to a deepin 25 guest in Huawei's Linux VM app, booting deepin's 6.6 kernel | Boots to the SDDM greeter and the Hyprland desktop, GPU-accelerated through virgl (OpenGL only) after 鸿融 starts the VM from cold |
| **D. Native on the HongMeng kernel**: [docs/native-chroot.md](docs/native-chroot.md) | Arch Linux ARM with Omarchy's packages in a chroot on the host itself (no VM), entered from a root shell | Omarchy's terminal side at native speed (shell, LazyVim, themes, btop, lazygit, mise), and Omarchy's Hyprland desktop in a HarmonyOS app ([docs/native-desktop.md](docs/native-desktop.md)): patched Hyprland rendering on the Maleoon GPU through the system's virglrenderer, presented into the app's window without a copy (workspace animations at up to the panel's 120 Hz); Wayland apps also show in route C's desktop via waypipe |
| **E. Bare metal**: (no doc yet) | Linux directly on the HarmonyOS PC's hardware, with no HarmonyOS underneath | Not started; nothing in this repo yet |
| **F. Whole OS in Aetherium on the DevEco emulator**: [docs/emulator-aetherium.md](docs/emulator-aetherium.md) | No HarmonyOS hardware: the complete Omarchy AArch64 OS in a patched Aetherium (QEMU TCG) on DevEco's HarmonyOS 7.0 PC emulator, shown in a HarmonyOS window by a native VNC client | Omarchy 4.0.3 on its own kernel through Limine, first-boot setup, and the Hyprland desktop (llvmpipe) started from a console because SDDM's greeter times out; all in software emulation, so slow |
| **G. Whole OS in the 铠大师 VM**: [docs/vm-kaidashi.md](docs/vm-kaidashi.md) | The complete Omarchy AArch64 disk (UEFI + GRUB, linux-aarch64 7.2 with the HMV ID-register quirk) in sanway's Windows-on-ARM VM app `com.sanway.ecoengine` | Concluded: same svga-pci path as B, 60 Hz; tools kept. A Linux ISO boots (fake `install.wim`, no login, Secure Boot off), but every VM is an install session that 铠大师 deletes on power-off; details in the doc |
| **H. Aetherium on the device**: [docs/device-aetherium.md](docs/device-aetherium.md) | The same QEMU-in-a-HAP as route F, but on the real HarmonyOS PC (`ohdev`): attempt a TCG baseline to Hyprland and investigate HMV hardware acceleration | Done (negative): without root nothing works — HMV is closed to third parties (hardcoded appIdentifier allowlist + MANAGE_VM, see [docs/vm-api.md](docs/vm-api.md)); TCG will not even initialize (QEMU aborts in `tcg_region_init`, the HAP is denied executable/JIT memory), so the baseline numbers are not obtainable on-device. HMV from a root VMM has no SELinux gate (only the undocumented 0xAE ABI); no virgl/venus 3D and no 120 Hz path. Route F covers TCG in the emulator |
| **I. Our own VM on the hypervisor**: [docs/vm-own.md](docs/vm-own.md) | headless backend for D: Docker + full kernel. Omarchy's 7.2 kernel in a StratoVirt VM started as root on `/dev/hmv` (no VM app); D's terminal uses its dockerd over ssh | First run: network both ways, 120 Hz mode, virgl on the Maleoon GPU, Docker + compose; service `ohmarchy-vm` written, D's docker context set up, waiting for a slot |

<!-- progress:start -->
## Progress (updated hourly; last: 2026-10-25 04:15 PDT)

| Route | Now | Latest |
|---|---|---|
| B. Oseasy VM | Wrapped up for today. Open, waiting for Yao: 鸿融 app launch times (its VM boots to the SDDM login) and running next to another VM (one VM at a time on HMV) | **The fix passes 4 h 24 min of GPU-load soak** (77 min, then 3 h 07 min with a 50 ms detection window; 75a22f2, 38539b4): no oops, BUG, WARNING, hung task or RCU stall, netconsole heartbeat unbroken, 120 frames/s to the host and 60 composed on screen throughout. The two runs before the fix hung at 38 and 51 min. Cause (a145d58): the driver freed command-buffer headers as soon as it read COMPLETED, before the host had finished writing them, which corrupted the DMA pool; completed headers now wait 5 ms. No late write was caught even with the 50 ms window, so the cause is inferred, not observed; 5 ms stays. **120 Hz cannot be reached from outside Oseasy** (f456da6): a 1x1 vote window that draws nothing does switch the panel to 120 Hz, but the system then composites on the GPU and only 35–47 VM frames/s reach the screen; with Oseasy focused the panel is back at 60 Hz. Oseasy app cold start 1.1–1.9 s (a1c47a7) |
| C. 鸿融 VM | Paused (session idle since 09:14 PDT): 鸿融's own "import qcow2" with the StratoVirt-shaped header, on-screen fps at 120 Hz | Developer image passes in a real 鸿融 VM: desktop, network, virgl on the Maleoon GPU (glmark2 596), Docker, warm reboot, 30-min soak; CRTC at 120 Hz |
| D. Native | 24 h soak finished (2026-10-24 02:52 to 10-25 02:53 PDT): 23 of 25 hourly smoke tests pass; the 2 failures are the first hours, when the desktop was down; Hyprland unchanged for the last ~17 h, desktop memory 240 to 275 MB over that time. Write-up pending | A1: 74 of 78, 0 failed, P95 1.13 s. Docker, compose and bind mounts from the home directory work through route I's VM |
| I. Own VM | Wrapped up for today | Known limitation (6340109): files created through the share come out 0660/0771, set by HarmonyOS's own virtiofsd; `--mapped-perm` only changes what the guest sees, `--posix-acl` conflicts with uid translation, chmod has no effect. D's own files are 0644 and builder owns everything, so D is not affected |
| H. Aetherium on the device | Concluded (81cb74d, 5a6b00a) | **Without root, Aetherium does not run on the device**: HMV is closed to third parties, and TCG aborts in `tcg_region_init` (4 vCPU / 4 GB and 1 vCPU / 2 GB alike); inferred cause, without a direct AVC: the app domain gets no executable memory. Running QEMU's TCG as root was considered and declined, since route I already runs with HMV as root |
| G. 铠大师 VM | Concluded | Same `svga-pci` path as B; Linux only lives in an install session |

Two locks on the device: `vm.lock` for the HMV hypervisor (one VM at a time) and `screen.lock` for the foreground; work that needs neither runs in parallel. Starting or killing processes on the device also needs `vm.lock`.
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

Concluded (outcome B: no persistent Omarchy VM in 铠大师). The tools remain:

```sh
tools/kaidashi/wrap-iso.sh IN.iso OUT.iso            # any UEFI ISO passes 铠大师's Windows-only check
tools/kaidashi/installer/build.sh WORKDIR linux-aarch64-7.2.12-*.pkg.tar.xz   # 7.2.12 probe/installer ISO
perl -e 'alarm 180; exec @ARGV' ssh ohdev sh -s < tools/kaidashi/probe.sh       # read-only survey
tools/kaidashi/kds-run.sh start ROW ENTRY            # drive the wizard (take vm.lock + screen.lock first)
```

Details, evidence and the comparison: [docs/vm-kaidashi.md](docs/vm-kaidashi.md).

## Route H quick start

On a host with `ssh ohdev` (HarmonyOS device, root), DevEco Studio and `python3`.
Coordinated. NOTE: on the real device the in-app QEMU aborts at `tcg_region_init` (no
executable memory for the HAP), so the VM does not boot on ohdev; these steps document the
flow (and work in the route-F emulator). See docs/device-aetherium.md for the full result.

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

## Route I quick start

On the host, as root, with `omarchy-own.img` prepared (`tools/ownvm/prep-disk.sh`):

    sh /data/local/kaidashi/bin/ohmarchy-vm start     # returns when the guest's ssh answers
    sh /data/local/kaidashi/bin/ohmarchy-vm status    # VM, guest, dockerd, balloon, host RSS
    sh /data/local/kaidashi/bin/ohmarchy-vm stop

In D's terminal: `docker run --rm hello-world` (context `ohmarchy`). Details:
[docs/vm-own.md](docs/vm-own.md).
