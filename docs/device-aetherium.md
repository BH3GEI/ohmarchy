# Route H: Omarchy in Aetherium on the HarmonyOS device

Route F runs Aetherium (QEMU in a HAP, [AetheriumSimulator/qemu-hmos](https://github.com/AetheriumSimulator/qemu-hmos))
on the DevEco **emulator**, where there is no hardware virtualization, so it is
TCG (pure software). Route H is the same app on a **real device** — a MateBook 14
(HM740, HarmonyOS 7.0, Kirin X90) reached over `ssh ohdev` — with two goals:

1. **TCG baseline on the device:** cold-boot Omarchy to the Hyprland desktop on
   its own unpatched 7.x kernel, and measure boot time, on-screen frame rate
   (hidumper/hitrace), refresh rate, host CPU and temperature, for a table
   against routes C (鸿融), D (native) and B/G.
2. **Acceleration investigation:** can qemu-hmos use HarmonyOS's own hardware
   virtualization (HMV) instead of TCG? Either prototype an `hmv` accel for
   QEMU, or document with evidence why a third-party app cannot.

The device is shared with other sessions and one HMV hypervisor runs the system
VMs one at a time; work here is coordinated and must not reboot the device or
disturb the 鸿融 main VM.

## HMV hypervisor interface (static analysis)

Pulled from the device and analysed on a host (no VM started):
`stratovirt` (the system VMM), `libvm_manager.z.so`, and the HMV userspace shim
`/vendor/lib64/chipsetsdk/libhmlibs.so.0`.

- **`/dev/hmv`** — char device `10:232`, `root:hwf_service` mode 0660, SELinux
  label `u:object_r:dev_hmv_file:s0`. The system VMM runs it:
  `stratovirt -machine virt,gic-version=3,mem-share=on,accel=hmv -cpu host,... -smp 6 -m 8192`,
  in SELinux domain `u:r:ohsw_stratovirt:s0`, with `ohos.permission.MANAGE_VM`.
- **Not KVM-API-compatible.** A read-only probe from the `su` domain opened
  `/dev/hmv` successfully but every standard KVM ioctl returned `ENOSYS`
  (`KVM_GET_API_VERSION`, `KVM_GET_VCPU_MMAP_SIZE`, `KVM_CHECK_EXTENSION` for
  ten caps). So QEMU's `accel/kvm` with `device=/dev/hmv` will not work.
- **It is ioctl-based and reuses the KVM magic byte `0xAE`, with HMV-specific
  command numbers.** The shim `libhmlibs.so.0` (2 KB, no imports, raw `svc`)
  exports exactly two run-loop primitives, both `ioctl` (aarch64 syscall 29):

  | function | ioctl request | decode |
  |---|---|---|
  | `hmv_join_actvpool_thread` | `0x4004ae08` | `_IOR(0xAE, 0x08, 4)` |
  | `hmv_wait_next_vmexit`      | `0x4004ae09` | `_IOR(0xAE, 0x09, 4)` |

  `stratovirt` dlsyms these two at runtime ("failed to get function
  hmv_join_actvpool_thread/…"). The rest of the HMV interface (create VM/vCPU,
  memory slots, boot config, MMIO/PSCI/MSR exits) is in StratoVirt's own
  `hypervisor/src/hmv/` (module paths `hmv/mod.rs`, `hmv/ioctl/system.rs`,
  `hmv/hm_cpu.rs`, `hmv/aarch64/{mod,psci,pvtime}.rs`), not in upstream openEuler
  StratoVirt — a closed Huawei branch. The exit model is an "active thread pool"
  plus `wait_next_vmexit`, not KVM's `KVM_RUN` mmap.

`stratovirt` itself issues a large set of ioctls with the `0xAE` magic from its
closed `hmv/ioctl` module (reconstructed from the disassembly): create/VM/vCPU
and register traffic — e.g. nr `0x01` (`_IOW`/`_IOWR`), `0x18`/`0x19` (112-byte
get/set), `0x1a`/`0x1b` (11264-byte get/set, the full vCPU state), and frequent
per-vcpu ops `0x79` (64-byte, ×8), `0xe1` (24-byte, ×6), `0xb0` (`_IOWR`, ×5).
These are the HMV equivalents of KVM's create-vm / create-vcpu / get-set-regs,
with the same magic but HMV-specific nr/size/semantics. The two run-loop
primitives (`0x08` join-pool, `0x09` wait-vmexit) are the only ones factored out
into `libhmlibs.so.0`.

**Implication so far:** an HMV accel for QEMU is conceivable (it is an ioctl ABI
on an fd), but it would mean re-implementing StratoVirt's `hmv/ioctl` set, and
the gating question is permissions: `/dev/hmv` opens from `su`, but whether the
create-VM/run ioctls succeed outside the `ohsw_stratovirt` domain / without
`MANAGE_VM` is not yet tested (it needs the VM lock and the 鸿融 VM stopped).
More ioctl numbers decoded from `stratovirt` and the permission test: pending.

## Status

In progress. Static HMV analysis done (above). TCG baseline and the on-device
acceleration test are next; the app is signed with the device's debug profile
(`UDID` from `bm get --udid`, same `sign.sh` as route D, bundle
`com.caidingding233.qemuhmos`).
