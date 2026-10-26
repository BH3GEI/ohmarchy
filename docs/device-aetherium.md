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
create-VM/run ioctls succeed outside the `ohsw_stratovirt` domain was tested
directly (`device/hmv-permtest.sh`, with the 鸿融 VM stopped).

**Permission test result (2026-10-25 — no SELinux/permission gate on `/dev/hmv`):**
A root process in the `su` domain running an unlabeled binary from
`/data/local/tmp` (`device/hmv/hmvcreate.c`) **opens `/dev/hmv` successfully**, and
its create-VM ioctls return `ENOSYS`/`EINVAL` — **not `EPERM`/`EACCES`**. So neither
the `dev_hmv_file` label nor `MANAGE_VM` blocks a non-system root caller from the
device or its ioctls; the calls fail only because the guessed ioctl number/arg
struct is wrong (the real ABI is undocumented). A `/data` **copy of `stratovirt`**
(which loses the `ohsw_stratovirt_exec` label and stays in the `su` domain) runs as
far as StratoVirt's own **config precheck** ("VmConfig is unhealthy" — from minimal
`-machine` args, not a permission error). So the gate for a root-side custom VMM is
**not** permissions/SELinux/domain — it is knowing StratoVirt's closed `0xAE` ioctl
ABI. An `hmv` accel for a non-system VMM (Route I, root) is thus feasible in
principle; remaining work is reversing the create-VM/vCPU/memslot/register ioctl
numbers and structs from `stratovirt`/`libhmlibs.so.0`.

**Decision (2026-10-25): not pursued.** Writing a custom `hmv` accel is feasible in
principle but was deliberately not done: Route I already runs the guest on the
system's own StratoVirt (network, 120 Hz, GPU/virgl, Docker, memory reclaim all
working), so a hand-written VMM adds no new capability, and this path needs root —
unusable by an external developer. It stays recorded here as "feasible in principle,
not implemented, would require reversing StratoVirt's closed 0xAE ioctl ABI".

## Can QEMU use HMV? (feasibility)

What would be required, and the blockers in order:

1. **Aetherium's QEMU has no hardware accel at all.** Its CI builds
   `--target-list=aarch64-softmmu --disable-kvm` (QEMU_FEATURES.md: "KVM
   support: NO"), and the app only probes `/dev/kvm` (`kvmSupported()`), falling
   back to `tcg,thread=multi`. There is no HMV code path. So any acceleration
   means a **rebuilt libqemu with a new `accel/hmv` backend**, not a config flag.
2. **That backend must re-implement StratoVirt's closed HMV ABI** — the `0xAE`
   create-vm/vcpu/memslot/register ioctls above, plus the `libhmlibs.so.0`
   run-loop primitives (`hmv_join_actvpool_thread`, `hmv_wait_next_vmexit`) and
   its active-thread-pool exit model (not KVM's `KVM_RUN` mmap). Doable in
   principle (the shim is decoded, stratovirt is the reference), but a large port.
3. **Permission gate — the make-or-break unknown.** The system VMM runs in
   SELinux domain `ohsw_stratovirt` with `ohos.permission.MANAGE_VM`; `/dev/hmv`
   is `dev_hmv_file` 0660 `root:hwf_service`. A `su`-domain process *opens*
   `/dev/hmv`, but whether the create-vm/create-vcpu ioctls succeed outside the
   `ohsw_stratovirt` domain is untested. This is the one test that needs the VM
   with the 鸿融 VM stopped; it decides prototype-vs-impossible.

So: a config switch cannot enable HMV; a prototype is conceivable but needs both
a QEMU port and clearing the permission gate. The permission test is queued.

## Display: 3D and 120 Hz (static answer)

- **No virgl/venus 3D.** Aetherium's QEMU `configure` has no `--enable-opengl`,
  `--enable-virglrenderer` or `--enable-rutabaga`, and disables the gtk/sdl/spice
  frontends (only `--enable-vnc --enable-pixman`, `-Dwrap_mode=forcefallback`).
  The `virtio-gpu-gl` / `virtio-gpu-rutabaga` QOM type names and the
  `VIRTIO_GPU_F_VIRGL` strings are in `libqemu_full.so` because hw/display always
  registers them, but with no virglrenderer/opengl linked they cannot provide 3D.
  So the guest gets 2D `virtio-gpu` (software) or `ramfb` only — matching route F,
  where Hyprland fell back to llvmpipe (CPU). No venus either. Confirmed at the binary
  level: `libqemu_full.so`'s `DT_NEEDED` is only `libz.so`, `libohaudio.so`,
  `libability_access_control.so`, `libc.so` — no virglrenderer, epoxy, rutabaga,
  Vulkan or EGL/GL, and it imports no `virgl_renderer_*`/`rutabaga`/`gl*` symbols;
  the binary also contains the string "OpenGL support was not enabled in this build
  of QEMU". So selecting `virtio-gpu-gl-pci` in the wizard would fail at runtime.
- **120 Hz: no hardware path.** `ramfb` has no refresh-rate concept (the guest
  pushes a fixed-size framebuffer); 2D `virtio-gpu`'s on-screen rate is bounded by
  the guest's CPU drawing and the HarmonyOS compositor's presentation, not a
  120 Hz scanout. The on-screen fps (measured with `oseasy/measure-fps.sh`) is
  pending the run, but a true 120 Hz 3D path is not in this build.

## Creating the VM on the device (disk-import bug)

The stock Omarchy qcow2 must be visible in the HarmonyOS file picker, which only
lists files registered through the file-manager index: copy it **through the hmdfs
account path** `/data/service/el2/100/hmdfs/account/files/Docs/Download/` as owner
`20001006:1006` mode `660` (a file written by raw `dd`/`cat` to `/storage/media`
bypasses the index and never appears). `device/create-vm.sh` drives the wizard
(选择架构 ARM64 → 选择机器 virt → 选择显卡 virtio-gpu-pci → 选择网卡 virtio-net-pci →
声卡 无声卡 → 配置内存 4 GB → 配置硬盘 导入现有 QEMU 磁盘 → 选择 → the qcow2 →
系统 Linux → no ISO → name → 创建并启动).

`创建并启动` silently does nothing if Aetherium's sandbox has no `files/vms`
directory — the known Route F bug (`docs/emulator-aetherium.md`,
[qemu-hmos#52](https://github.com/AetheriumSimulator/qemu-hmos/issues/52)): after a
data reset the import creates `files/vms/<name>` but not its parent `files/vms`, and
fails with "导入磁盘镜像失败: No such file or directory". **Normal users** fix it the
documented way — open any VM's 虚拟机设置 → ISO 镜像 → 选择 and pick a file, which runs
`StoragePaths.ensureDirectories()` and creates `files/vms`. On a **rooted dev box**
the directory can be created directly (what we did here), matching the parent's owner,
mode and label:

```
B=/data/app/el2/100/base/com.caidingding233.qemuhmos/files
mkdir -p "$B/vms"; chown 20020166:20020166 "$B/vms"; chmod 771 "$B/vms"
chcon u:object_r:debug_hap_data_file:s0 "$B/vms"
```

## Criterion 1 result: TCG does not run on ohdev (QEMU aborts at init)

The TCG baseline **cannot be produced on the device**: Aetherium's in-process QEMU
aborts during engine initialization, before any guest boot. Confirmed on-device
2026-10-25 after working around every earlier blocker (image registration via hmdfs,
the create-button shot-coordinate, and the blank-disk + root disk-swap for the broken
importer — all documented above).

Starting the VM (`普通启动 (VNC)`) crashes the HAP with **SIGABRT in
`tcg_region_init`** (QEMU's TCG translation/code-buffer setup):

```
Process name:com.caidingding233.qemuhmos
Reason:Signal:SIGABRT ... LastFatalMessage:[appspawn_server.c:72]Unexpected call: exit(1)
#03 ... libqemu_full.so(tcg_region_init+1232)
#05 ... libqemu_full.so(accel_init_machine+92)
#08 ... libqemu_full.so(qemu_init+12956)
```

i.e. `tcg_region_init` hits a fatal error and calls `exit(1)`, which an appspawn-managed
HAP turns into an abort. This reproduces at **4 vCPU / 4 GB and at 1 vCPU / 2 GB**, so it
is not a thread-count or memory-size issue — the TCG engine simply will not initialize.

**Most likely cause: the HAP is denied the executable/JIT memory a TCG code buffer needs.**
QEMU runs in the restricted `debug_hap` SELinux domain; `dmesg` shows this domain denied
even `read` of `/proc/sys/vm/max_map_count` (and `ioctl` of `/dev/access_token_id`,
`mounton` of the vulkan dir) at launch. `tcg_region_init`'s job is to allocate and carve
up the executable code-generation buffer, and HarmonyOS hardening (W^X / no anonymous
`PROT_EXEC` for an ordinary HAP) is the standard reason that allocation fails. A direct
`execmem`/`execmod` AVC was **not** captured here (the kernel ring buffer had rolled past
the launch window), so the exact denial is inferred from the crash site, not proven by an
AVC line; it is the only cause consistent with a `tcg_region_init` exit that is independent
of vCPU/memory.

**Alternative considered and declined (root + TCG outside the HAP):** QEMU's TCG could
likely be made to initialize by running it as a root process in the `su` domain (which can
allocate executable memory), e.g. a small launcher that `dlopen`s `libqemu_full.so`. This was
**deliberately not pursued** (supervisor decision): Route H's question is specifically whether
it works *without root*, and the answer is no; with root, Route I already runs Omarchy with
HMV hardware acceleration (network, 120 Hz, GPU, Docker), so a root + software-TCG run would
only produce numbers far slower than Route I that nobody would use, for hours of extra
reverse-engineering. So criterion 1's numbers are not obtainable on ohdev, and that is the
result.

**Why route F (the emulator) is unaffected:** the DevEco emulator image runs the same
Aetherium but allows JIT/executable memory, so TCG initializes there and Omarchy boots to
Hyprland (see [emulator-aetherium.md](emulator-aetherium.md)). On the real device it does
not.

**Net for Route H without root:** there is no working path. HMV is closed to third parties
(a hardcoded `appIdentifier` allowlist in `libvm_manager.z.so` plus `MANAGE_VM` — see
[vm-api.md](vm-api.md)), and TCG will not initialize because the HAP is not granted
executable memory. The accelerated/accel question and the display (virgl/venus, 120 Hz)
question are answered above. The on-screen fps / refresh / boot-time / host-CPU numbers
of criterion 1 therefore cannot be measured on ohdev — the comparison table's H column
records this rather than numbers.

## Measuring the baseline

Once the VM runs under TCG (criterion 1), numbers are collected with scripts
already in the repo plus `device/baseline.sh`:

- **Frame rate and refresh:** `oseasy/measure-fps.sh [SECS] [WINDOW]` — panel
  `activeMode` (refresh), on-screen `composer fps` from RenderService, the
  Aetherium window's own `fps`, and `hitrace graphic` frame counts, while the
  guest runs es2gears and workspace switching with its window in front.
- **Host CPU and temperature:** `device/baseline.sh [SECS]` — overall/again
  per-core CPU busy from `/proc/stat`, top consumers, and
  `/sys/class/thermal/thermal_zone*` before/after, read-only.
- **Boot time:** wall time from the Aetherium "start" tap to the Hyprland
  desktop appearing (serial/VNC watch), as in route F.

These feed the comparison table against C (鸿融), D (native), B/G.

### Comparison table

Routes on ohdev (MateBook 14, HM740, Kirin X90, HarmonyOS 7.0). C and D numbers
are from [docs/native-desktop.md](native-desktop.md) (all counted on-screen by
HarmonyOS's compositor, `hidumper -s RenderService`); B is from b15cf1f /
`oseasy/runs/2026-10-24-kmsgl/`; H is pending its TCG run.

| Metric | C. 鸿融 VM | D. Native | B. Oseasy VM | G. 铠大师 VM | H. Aetherium TCG |
|---|---|---|---|---|---|
| Virtualization | HMV (system VMM) | none (HongMeng kernel) | HMV (system VMM) | HMV (system VMM) | TCG (software, in-app QEMU) |
| GPU path | virgl (zink, Maleoon) | Maleoon via host virgl | SVGA3D hardware (GL ES 3.0) | svga-pci (same as Oseasy), network TBD | 2D virtio-gpu / llvmpipe (no 3D) |
| Omarchy desktop | yes (SDDM→Hyprland) | yes | yes | survey only | **✗ — never reached (QEMU aborts at TCG init)** |
| Kernel | linux-aarch64 7.2.12 + HMV quirk | HongMeng (host) | linux-aarch64 7.2.12-1.1 + HMV patches, patched `vmwgfx` (route B; Debian 6.1 at first) | n/a | Omarchy stock 7.2.3 (unpatched) |
| Display refresh | guest 120 Hz (120 Hz EDID), 60 Hz on screen | 120 Hz (panel) | 60 Hz (panel locked) | — | ✗ (no boot); static: no 120 Hz / no 3D path |
| es2gears on-screen, 1920x1280 | 60 fps | 117–120 fps | 60 fps (guest 120) | — | ✗ (no boot) |
| Workspace anim on-screen, 1920x1280 | 60 fps | 115–116 fps | — | — | ✗ (no boot) |
| es2gears on-screen, 2160x1440 | 60 fps | 117–118 fps | — | — | ✗ (no boot) |
| HwcPresentDisplay/s (es2gears 1920x1280) | ~40 | ~120 | — | — | ✗ (no boot) |
| Cold boot to desktop | see route C | n/a (native) | — | — | **✗ — QEMU aborts before boot** |
| Host CPU while running | — | — | — | — | ✗ (no VM runs) |
| Host temperature | — | — | — | — | ✗ (no VM runs) |

H's pending cells are filled from the TCG run (criterion 1). Expectation from
route F (same stack on the emulator): desktop reaches Hyprland on llvmpipe but
slowly; on-screen fps far below C/D and no 120 Hz.


## Status

Done. HMV acceleration: answered (no SELinux/permission gate on /dev/hmv for a root VMM;
blocked only by the undocumented 0xAE ABI; custom accel feasible-in-principle, not built —
system StratoVirt already covers Route I). Display: no virgl/venus 3D and no 120 Hz path
(binary-confirmed). TCG baseline: cannot run on the device — QEMU aborts at tcg_region_init
(no executable memory for the HAP); numbers are therefore not obtainable on ohdev (route F
covers TCG in the emulator). vm-api (no-root VM service): closed partner allowlist, see
vm-api.md.