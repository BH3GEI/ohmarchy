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
