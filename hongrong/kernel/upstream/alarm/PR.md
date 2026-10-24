# linux-aarch64: boot in HarmonyOS PC virtual machines (鸿融 / HMV)

## Summary

Every kernel since v6.9 hangs at boot inside the Linux VM of HarmonyOS PCs
(the 鸿融 app, StratoVirt on Huawei's HMV hypervisor): the boot CPU stops
before secondaries are brought up, with no output. This adds two patches:

- `0006`: upstream `5a9d62555e71` ("irqchip/gic-v3-its: Don't clamp nvecs to
  zero when id_bits is 32", Cc stable, not in 7.3). The hypervisor's ITS
  reports 32 event ID bits; without it MSI allocation fails, every PCI device
  falls back to INTx and virtio-vsock never gets an interrupt.
- `0007`: an opt-in boot parameter, `arm64.hmv_idreg_quirk`. HMV hangs the
  vCPU when the guest reads ID_AA64PFR2_EL1 (and possibly other ID registers
  Linux started reading after v6.8) instead of returning zero as the
  architecture requires. With the parameter, those registers read as zero
  without being accessed. **Without it, nothing changes**, so other boards
  are unaffected.

`pkgrel` is bumped; no config change.

## Affected registers

ID_AA64ISAR3_EL1, ID_AA64PFR2_EL1, ID_AA64FPFR0_EL1, ID_AA64MMFR4_EL1,
AIDR_EL1, SMIDR_EL1, MPAMIDR_EL1: everything v6.8 did not read at boot. Two
places read them: `__cpuinfo_store_cpu()` (since v6.9) and, for the GICv5
boot capability, `__read_sysreg_by_encoding()` (since v6.17).

## Reproduce

1. On a HarmonyOS PC with the 鸿融 app, install any aarch64 distribution in
   the VM and boot linux-aarch64 7.x: no output after the EFI stub, and the
   host log `/data/log/hwf_service/vmlog` never shows
   `psci.rs ... vCPU 1 is running`.
2. With this package and `arm64.hmv_idreg_quirk` on the command line, all
   vCPUs start, systemd reaches `running`, and warm reboots work.

Tested on a HUAWEI MateBook 14 (HM740, Kirin X90, HongMeng kernel 1.11.13.0,
鸿融 1.1.1.103) with linux-aarch64 7.2.11 (desktop, virgl, vsock, network)
and 7.2.12 (cold boot + 3 warm reboots); 0006 and 0007 apply to 7.3 as is.
Full analysis: https://github.com/BH3GEI/ohmarchy/blob/main/docs/hmv-idreg-report.md

## Files

- `0006-irqchip-gic-v3-its-Don-t-clamp-nvecs-to-zero-when-id_bits-is-32.patch`
- `0007-arm64-arm64.hmv_idreg_quirk-to-read-new-ID-registers-as-zero.patch`
- `PKGBUILD.diff` against ALARM master (7.3-1)
