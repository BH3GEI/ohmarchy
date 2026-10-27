# Route E — reflash ohdev to Omarchy (dual-boot)

Goal: run Omarchy (Arch + Hyprland) on ohdev natively, ideally dual-booting with HongMeng.
ohdev's working data was moved to ohdev2, so ohdev is free to flash. This documents the
read-only reconnaissance (phase 1) and the planned staged bring-up. No partition has been
written, nothing unlocked, no slot switched.

## Device

- **HM740-001 / MNT-W72** HarmonyOS PC (MateBook-class), SoC **Kirin X90**, GPU **Maleoon
  (higpu.v210)**, **32 GB** RAM, ~**1 TB NVMe** (`nvme0n1`, GPT, 118 partitions).
- HongMeng 7.0.0.115. `ssh ohdev` = root (over an frps tunnel, not USB). `ssh ohdev2` = root
  (MOR-M1, the intended flash host; connected to ohdev by USB).

## Bootloader & security state (the enabling facts)

From `/proc/cmdline` and `param get`:

- **`UEFI=true`, `tz_uefi_enable=1`** — the firmware is UEFI. HongMeng doesn't mount efivarfs, so
  `/sys/firmware/efi` is absent on the running system, but the underlying boot is UEFI loading an
  HVB-signed boot image.
- **`ohos.boot.hvb.device_state=unlocked`, `ohos.boot.hvb.enable=orange`** — verified boot is in
  the unlocked/orange state: custom (unsigned) images are allowed. HVB version 1.1, sha256.
- **`bootslots=2`, `currentslot=1`, `partition_type=AABackup`** — not a standard A/B layout; it's
  a main set plus `_b_back` backup copies (Huawei "AABackup").
- `console=ttyS0` — a serial console exists (reachable with the right hardware).

## Partition layout (GPT, `/dev/block/by-name`)

| name | size | notes |
|---|---|---|
| esp | 200 MB | **empty / unformatted** (UEFI isn't scanning it today) |
| boot | 51 MB | HVB/DER-signed boot image (kernel+ramdisk+dtb), `boot_b_back` backup |
| system | 6.7 GB | HongMeng system (single, high partition index) |
| vendor | 920 MB | |
| userdata | 926 GB | the large free space |
| fastboot_b | — | the fastboot UEFI app |
| updater_boot_a/b, updater_ramdisk_a/b | — | eRecovery / updater subsystem |

The UEFI firmware currently chain-loads the signed `boot` partition directly and does **not**
scan a FAT ESP (the ESP is empty). Display is HongMeng's `dpu_res`; a Linux guest would rely on
UEFI GOP → `efifb`.

## Dual-boot options

**E1 (approved, lowest risk) — UEFI + populate the ESP + an EFI bootloader.** Format the empty
ESP FAT32, install GRUB (or systemd-boot) at `\EFI\BOOT\BOOTAA64.EFI`, a generic arm64 Linux
kernel + initramfs, and a GRUB entry that chain-loads HongMeng back. Depends on the firmware
either falling back to the default `\EFI\BOOT\BOOTAA64.EFI` path or allowing a UEFI boot entry —
to be confirmed on-device in UEFI/fastboot. **Reversible** (only the empty ESP is touched; `boot`
is untouched). Expected result: Linux boots to a UEFI-GOP `efifb` framebuffer. Caveat: Kirin X90
has **no mainline Linux support**, so there are no SoC drivers (GPU/Wi-Fi/BT/audio/touch most
likely absent); NVMe/xHCI/serial should work with generic drivers. So "boots to a picture and
runs Omarchy's software-rendered desktop" is realistic; hardware acceleration and peripherals are
case-by-case.

**E2 — replace the `boot` partition with a Linux boot image.** Direct, but needs an aarch64 boot
image the bootloader accepts (orange state should allow unsigned), and still lacks SoC drivers.
Higher risk (touches `boot`; recovery needs fastboot).

**E3 — A/B dual-boot** (one slot HongMeng, one Linux). Under the AABackup scheme it's unclear the
backup set can boot independently. Higher risk.

## Flash tooling

ohdev2 (HongMeng, aarch64) has xHCI USB host controllers but **no fastboot/hdc/adb** installed —
an aarch64 fastboot client must be provided. Alternative host: the Windows machine
`magicbook_outside` has `hdc.exe`. ohdev's USB device controller (`ea100000.hiusbc`) is currently
not attached (ssh is over the network, not USB).

## Brick risk & recovery

Unlocked + orange should make `fastboot flash` usable once in fastboot. The eRecovery/updater
subsystem is present (official restore path likely). `boot`/`vendor`/`system` have `_b_back`
backups, so a mis-flash of the main set can be restored from backup. Safest first write is the
empty ESP only (E1); avoid touching `boot` unless necessary.

## Staged plan

Phase 2 (after ohdev is free again — it is first needed for a B-release regression):
1. Prepare ESP contents offline: `BOOTAA64.EFI` (GRUB/systemd-boot), an EFI shell, a generic
   arm64 kernel + initramfs (efifb, nvme, xhci, serial), GRUB menu with a "back to HongMeng"
   entry if achievable.
2. Provide an aarch64 fastboot client on ohdev2; confirm USB enumeration.
3. Confirm the eRecovery key combo (brick backstop) before any reboot.
4. Then, with approval and step-by-step reporting: format the ESP, reboot into UEFI/fastboot,
   try to boot. Only the ESP is written first; `boot` is left intact.

## USB-boot via Ventoy + vendor DTB driver analysis (2026-10-27)

Yao's USB stick is a **Ventoy** drive (don't wipe): sda1 exFAT (label Ventoy, auto-mounted by
HongMeng at `/mnt/data/external/4E21-0000`, ~29 GB free, holds ArchLinux/Debian/Omarchy(x86
omarchy-4.0.6.iso)/Ubuntu/Win11/Win7/driver + virtio-win), sda2 `VTOYEFI` with `grub/arm64-efi`
(Ventoy has ARM64 UEFI). Plan: **add** an arm64 artifact under `Omarchy-arm64/` alongside the
existing files — never touch the internal disk, never touch existing USB files. exFAT is writable
(~593 MB/s). This is zero-risk: the internal NVMe is not touched at all.

**Firmware passes a Device Tree, not ACPI** (`/sys/firmware/devicetree` + `/sys/firmware/fdt`
present; no `/sys/firmware/acpi`). The vendor DTB was exported from `/sys/firmware/fdt` (724 KB,
30531 dts lines) and its `compatible` list analyzed to predict which mainline drivers can bind:

| subsystem | DTB compatible | mainline driver? |
|---|---|---|
| CPU arch timer | `arm,armv8-timer` | ✅ built-in |
| legacy timer | `arm,sp804` (primecell) | ✅ |
| framebuffer (via UEFI GOP) | — (not DT; GOP) | ✅ efifb/simpledrm |
| display controller | `hisilicon,dpufb`, `dkmd,dpu_device` | ❌ vendor DPU (GOP only) |
| USB | `hisilicon,hiusb`, `hisilicon,hiusbc`, `huawei,huawei_usb` | ❌ no dwc3/xhci match |
| serial console | `hisilicon,uart` | ❌ (not pl011/dw-apb; efifb console only) |
| I2C | `hisilicon,hisi-i2c-master` | ❌ → `hid-over-i2c` input can't attach |
| PCIe | `hi_pcie`, `hi_pcie,portNN` | ❌ no `pcie-kirin` match |
| NVMe | (behind `hi_pcie`) | ❌ unreachable without PCIe |
| storage | `hisilicon,antlia-sdhci`, `hisilicon,bootdevice` | ❌ custom |

**Verdict:** on this Kirin X90 a generic/mainline arm64 Linux will bind essentially nothing but
the arch timer and the UEFI-GOP framebuffer. Expect an **efifb picture with no input, no USB, no
storage, no serial, no acceleration.** There is no public Kirin X90 Linux BSP (HongMeng is not
Linux), so an interactive native desktop is not reachable with mainline drivers today. This makes
the **all-RAM** design mandatory (kernel + an initramfs holding the whole Omarchy root, loaded by
GRUB before ExitBootServices — nothing is read from storage after boot) and sets v1's success
bar at "boots to a framebuffer picture", with an on-screen dmesg/probe log (large font) for Yao
to photograph. The exported DTB is kept at `scratchpad/routee/dtb/kirinx90.dtb` for offline study.

## Can we reuse HongMeng's Linux drivers? (investigation, 2026-10-27)

HongMeng reuses Linux drivers via a userspace driver container (HDF `devhost`) + a Linux-compat
shim, per the OSDI'24 HongMeng paper. On ohdev:

- The driver host runs `/bin/devhost.elf` against **`/lib/libdh-linux.so.6.6.127-oh`** → the
  Linux-compat base is **Linux 6.6.127**. One `devhost` instance (name=`common`) hosts the Linux
  drivers; it links `libdh-linux`, `libdh-lnxbase`, and HongMeng microkernel service libs
  (`libhmsrv_fs/io/net/sec/kernfs`, `libhmulibs`). The Kirin X90 drivers appear to be built into
  `libdh-linux.so.6.6.127-oh` (loaded as an anon mapping; not separate `.ko`s, and there is no
  `/lib/modules`).
- **Execution model:** these are *userspace* drivers for the HongMeng microkernel — they call the
  microkernel via `libhmsrv_*`, not the Linux kernel. They are **not** loadable kernel modules.

**Feasibility:**
- (a) *Load the binaries on a native Linux kernel* — **not viable.** They are userspace
  microkernel drivers bound to `libdh-linux` + `libhmsrv_*` + the HongMeng IPC model, not Linux
  `.ko`s; there is no Linux kernel ABI to load them into.
- (b) *Rebuild from GPL source on our kernel* — **blocked by source availability.** No public
  Huawei GPL tarball for MNT-W72 / HM740 / Kirin X90 was found; HarmonyOS PC is a closed
  microkernel product (OpenHarmony on Gitee is the OS framework, not the Kirin X90 SoC Linux
  drivers). The GPL-covered Linux code lives inside `libdh-linux`, but the adapted Kirin X90
  driver source (`hi_pcie`, `hiusbc`, `dpufb`, …) is not published. Target kernel version if it
  ever appears: **6.6.127**.

**Conclusion:** driver reuse does not give native Linux working hardware on the Kirin X90 today
(neither binary nor source). Route E's realistic ceiling stays the **efifb picture** (all-RAM, no
input/IO). Follow-ups worth a look but unlikely to carry HM740's SoC drivers: OpenHarmony Gitee
`kernel_linux_6.6` and the HDF/`liblinux` repos; and a formal GPL-source request to Huawei's FLOSS
portal. Refs: HarmonyOS is a microkernel with few public kernel details
([CNX](https://www.cnx-software.com/2025/05/20/huawei-matebook-pro-first-harmonyos-laptop/),
[Wikipedia: HarmonyOS](https://en.wikipedia.org/wiki/HarmonyOS)); HM740 uses Kirin X90
([Huawei Central](https://www.huaweicentral.com/huawei-hm740-harmonyos-pc-equips-kirin-x90-chip-confirmed/)).

## All-in-RAM USB stick (2026-10-27)

Built by `tools/routee/build-ram-usb.sh` in route D's Arch container on ohdev, written to
Yao's second stick (FAT32, label Y233, `/mnt/data/external/6019-BC8F`; the Ventoy stick is no
longer used). It is an ordinary removable ESP, so the firmware starts it without any boot manager:

| File | Size | What |
|---|---|---|
| `/EFI/BOOT/BOOTAA64.EFI` | 4 956 160 | standalone GRUB 2.16 arm64-efi; finds `/Omarchy-arm64/omarchy-ram.id`, reads `grub.cfg` there |
| `/Omarchy-arm64/grub.cfg` | 1 316 | Omarchy in RAM / debug (earlycon, loglevel=7, full dmesg) / debug + `efi=noruntime` / hello test / `fwsetup` / reboot / exit |
| `/Omarchy-arm64/Image` | 51 489 280 | Arch Linux ARM's generic `linux-aarch64` 7.3-1 (TUNA) |
| `/Omarchy-arm64/dev.cpio` | 488 | `/dev/console` and `/dev/null`, the first initrd |
| `/Omarchy-arm64/omarchy-root.cpio.zst` | 2 050 738 109 | route B's whole root (`omarchy-small.img`, 5.8 GB unpacked) as the second initrd |

GRUB reads both initrds into memory before ExitBootServices. The kernel unpacks the root into
its tmpfs rootfs, so nothing is read from storage after that. The stick needs about 8 GB of RAM:
the 2 GB initrd plus the 5.8 GB it unpacks to, until the initrd is freed.

**Kernel and drivers.** The generic kernel already has dwc3, xhci-plat, usb-storage, uas, usbhid,
nvme, DesignWare and ECAM PCIe, and efifb built in, and i2c-hid-of, hid-multitouch, exfat and vfat
as modules. The drivers it lacks are built from linux-7.3 against its headers (`extra/ohm/`):
efidrm, simpledrm (and `drm_sysfb_helper`), pcie-kirin, and the HiSilicon PHYs (hi3660-usb3,
hi3670-usb3/pcie, hi6220-usb, inno-usb2, histb-combphy, hix5hd2-sata). By the DTB analysis
above, none of these is expected to bind on the Kirin X90. They are loaded so that the report
shows it.

**`/init`** (`tools/routee/init`, bash from the Omarchy root itself) does these steps in order:
1. Loads those modules.
2. Prints a report on the EFI framebuffer in 32-point type (`latarcyrheb-sun32`), for a photo. It lists:
   - the devices bound to each driver, and the vendor DT nodes (`hi_pcie`, `hiusbc`, `dpufb`, …) with their counts;
   - block devices, input devices, USB and PCI devices;
   - the last kernel errors and warnings.
3. Writes the report and dmesg to `Omarchy-arm64/logs/` if a partition with that directory shows up.
4. Hands the framebuffer from efifb to efidrm: unbinds `efi-framebuffer.0` from efifb, then loads
   efidrm, which binds it under its own driver name. This gives Hyprland `/dev/dri/card0`.
5. Execs systemd. The existing tty1 autologin then starts Hyprland with software rendering
   (`/etc/profile.d/ohmarchy-ram.sh`: `QT_QUICK_BACKEND=software`, `LIBGL_ALWAYS_SOFTWARE=1`
   on efidrm/simpledrm).

`/etc/fstab`'s disk entries are commented out, and route B's VM kernel (7.2.12) is removed from
the root. File capabilities are not kept by `debugfs rdump`, which only matters for a few setcap
binaries.

Not yet booted on the machine. Untested points:
- GRUB reading a 2 GB initrd from a USB stick;
- the firmware accepting an unsigned GRUB from removable media (Secure Boot must be off);
- the efifb → efidrm hand-over on this GOP.
