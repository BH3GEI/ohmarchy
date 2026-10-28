# ohmarchy: Omarchy on HarmonyOS

English | [中文](README.zh-CN.md)

## Where to find things (for the review)

**Start here**
- **[Demo videos (showcase page) ↗](https://ohmarchy-demo.vercel.app)** — the single canonical presentation: three segments and a full cut, played on one clean page
- [Handover (Chinese)](docs/handover.zh-CN.md): status, what we still do, what HarmonyOS needs to merge, allow or provide, what must be maintained, incidents and rules
- [Demo operator manual](docs/demo-operator.md) ([中文](docs/demo-operator.zh-CN.md), whose part 4 covers the new native sandbox)
- [Public release b-20261027](https://github.com/BH3GEI/ohmarchy/releases/tag/b-20261027): the OSEasy install ISO and all GPL sources

**Routes**

| Route | Documents |
|---|---|
| B OSEasy | [Install guide](docs/oseasy-install.md) · [Technical record](docs/oseasy-whole-os.md) · [Early notes](docs/vm-oseasy.md) · [Guest-agent protocol](docs/oseasy-agent-protocol.md) · [Linux agent](oseasy/linux-agent/README.md) · [Bring-up runbook](oseasy/linux-agent/bringup.md) |
| C 鸿融 | [Technical record](docs/hongrong-whole-os.md) |
| D Native (demo) | [Install](docs/native-chroot.md) · [Desktop](docs/native-desktop.md) · [Compatibility](docs/native-compat.md) · [Acceptance](docs/acceptance.md) |
| D Native sandbox (new design) | [README and known boundaries](native/sandbox/README.md) · [Shared abstract sockets](native/sandbox/abstract-sockets-ohdev.md) · [Docker test patches](native/sandbox/docker-test/README.md) |
| I Own VM | [Technical record](docs/vm-own.md) |
| J Linux in an app sandbox | [Technical record](docs/no-root-routes.md) |
| E Bare metal / USB | [Technical record](docs/route-e.md) |
| Others (A, F, G, H, L) | [A](docs/linux-engine-apps.md) · [F](docs/emulator-aetherium.md) · [G](docs/vm-kaidashi.md) · [H](docs/device-aetherium.md) · [L](docs/route-l-arkweb.md) |

**For HarmonyOS and vendors**
- [HMV issue report (ID registers, Chinese)](docs/hmv-idreg-report.md)
- [Requests to OSEasy (Chinese)](docs/oseasy-vendor-request.md)
- [Brief for the 鸿融 team (Chinese)](docs/internal/hongrong-team-brief.md)
- [Can a third-party app create VMs (virtualization API and whitelist)](docs/vm-api.md)

**Other**: [Findings](docs/findings.md) · [Demo scripts](docs/demo.md) · [Internal report page](docs/report/index.html) · [Full document index](docs/README.md)

The goal is to run [Omarchy](https://omarchy.org), DHH's Arch Linux + Hyprland desktop, on a
HarmonyOS PC. The test machine `ohdev` is a HUAWEI MateBook 14 HM740: Kirin X90 (20
threads, 32 GB), Maleoon 916 GPU, a 2880x1920 panel that runs at up to 120 Hz, HarmonyOS
7.0.0.115 and the HongMeng kernel 1.11.13.0. The first work was done on a MateBook Fold
(HarmonyOS 7.0) with the AArch64 Omarchy build from
[riverscn/omarchy-aarch64-image](https://github.com/riverscn/omarchy-aarch64-image).

Headline results:

- **B, Oseasy (a third-party Windows VM app).** Omarchy installs from scratch in about
  3 minutes and gets GPU 3D through a patched `vmwgfx` driver (three fixes plus a
  watchdog). It ran 4 h 24 min under GPU load without a fault. 60 Hz on screen.
- **C, 鸿融 (Huawei's Linux VM app).** A ready-made Omarchy disk image with a patched
  7.2.12 kernel imports through 鸿融's own UI. No root needed. It has virgl 3D (glmark2
  596) and Docker. The guest renders at 120 Hz, but 鸿融 shows it at 60 Hz.
- **D, native, no VM.** Arch Linux ARM and Omarchy 4.0.6 run as ordinary processes on the
  HongMeng kernel. Omarchy's Hyprland desktop shows in a HarmonyOS app window at 120 Hz,
  rendered on the Maleoon GPU. Workspace switching runs at 119 fps on screen, cold start
  takes about 8 s, 74 of 78 apps open within 3 s, and a 24 h soak passed. Needs root on
  the host.
- **I, our own VM as D's back end.** Docker and a full Linux kernel for the native desktop.
  A headless Omarchy VM on the system hypervisor that D's `docker` reaches over ssh.
  Since caecc94 it starts on demand when `docker` is first used. Needs root.
- **Routes concluded negative.** Without root no app can use the hypervisor (Huawei keeps
  a hardcoded partner allowlist) or get executable memory (XPM). So the no-root routes
  are the two VM apps (B, C) and J, which is still being built: Linux programs compiled
  as `.so` files and signed into an app.

## The routes as a tree

```
Omarchy on a HarmonyOS PC
├─ 1. Plug and play in VM apps (no root)
│   ├─ B  Oseasy        ★ the public release line
│   ├─ C  鸿融           internal result (the app is not publicly released yet)
│   └─ G  铠大师         concluded: Linux only lives in an install session
├─ 2. Native on the HongMeng kernel (best experience)
│   ├─ D  native desktop                root; 120 Hz; the demo lead
│   ├─ I  own background VM             root; Docker for D
│   └─ J  native inside an app sandbox  no root; Hyprland built, going on device
└─ 3. Other explorations (concluded or fallback)
    ├─ A  HarmonyOS Linux engine            terminal tools only
    ├─ F  Aetherium on the DevEco emulator  no hardware needed; slow
    ├─ H  Aetherium on the device           negative: no executable memory
    ├─ K  QEMU TCI                          idea only
    ├─ L  Linux in ArkWeb                   paused
    └─ E  bare metal                        not started
```

Line 1 runs Omarchy inside a VM app and needs no root (Oseasy is the line for the public
release); line 2 runs it directly on the HongMeng kernel, the best experience, but D and I
need root until HarmonyOS opens the pieces listed in
[For the HarmonyOS teams](#for-the-harmonyos-teams); line 3 holds everything else we tried.
Every document is listed by the same tree in [docs/README.md](docs/README.md).

## Status at a glance

| Route | What it is | Status | Best numbers | Root? | Demo? |
|---|---|---|---|---|---|
| **1. VM apps (no root)** | | | | | |
| **B** Oseasy VM | the whole Omarchy OS in the Oseasy app, 7.2.12 kernel, patched `vmwgfx`; the image is inside the install ISO | works with limits (60 Hz on screen; fixed-size window, no fullscreen; nothing kept after power-off) | public ISO 1.855 GiB; disk written from the ISO in 231 s, ~4 min to the desktop; 2100x1511 at 120 Hz in the guest; 4 h 24 min GPU soak, 0 faults | no | yes, ~4 min |
| **C** 鸿融 VM | the whole Omarchy OS in Huawei's Linux VM app, virgl GPU | works with limits (60 Hz on screen) | import under 1 min (9.6 GB); glmark2 596; Docker; 30 min soak | no | yes, 3 min 41 s |
| **G** 铠大师 VM | Omarchy's disk in sanway's Windows VM app | concluded negative | 7.2.12 boots, but every VM is an install session that is deleted at power-off | no | no |
| **2. Native on the HongMeng kernel** | | | | | |
| **D** Native | Arch + Omarchy in a chroot on the HongMeng kernel; Hyprland shown by a HarmonyOS app | works | 119 fps workspaces, es2gears 117-120 fps on screen; cold start ~8 s; 74/78 apps, P95 1.13 s; 24 h soak | yes | yes, ~80 s |
| **I** Our own VM | StratoVirt on `/dev/hmv` as root, headless; Docker back end for D, started on demand | works | guest up in 5-10 s; up to 12 GiB, idle ~1.2 GiB host RSS; x86-64 images via qemu-user; demo 91 s | yes | yes, with D |
| **J** Linux in an app sandbox | Linux programs built as `.so`, signed into the HAP, run by fork + dlopen | prototype works (busybox); Hyprland 0.56.2 built for OHOS musl, not yet run on the device | busybox `sh` inside D's display app; Hyprland links against the self-built stack (845dc1b) | no | no |
| **3. Other explorations** | | | | | |
| **A** Linux engine apps | Omarchy's neovim setup and CLI tools in HarmonyOS's own Linux container, each in a HarmonyOS window | works with limits (terminal tools only, no Hyprland session) | | no | no |
| **F** Aetherium on the DevEco emulator | QEMU TCG in a HAP inside the HarmonyOS PC emulator on a Mac | works with limits (software only, slow) | first-boot setup 14-50 min | no (no device) | no |
| **H** Aetherium on the device | the route-F QEMU app on the real machine | concluded negative | QEMU aborts in `tcg_region_init` (no executable memory) | no | no |
| **K** QEMU TCI | QEMU's interpreter, which needs no executable memory | not started (idea only, deprioritised) | | no | no |
| **L** Linux in ArkWeb | v86 (x86 → wasm JIT) with Arch Linux 32 in an ArkWeb page inside a HAP | paused by decision (2026-10-25), never run on the device | desktop Chrome: root shell in ~32 s | no | no |
| **E** Bare metal | Linux directly on the hardware | not started | | | no |

<!-- progress:start -->
## Progress (updated hourly; last: 2026-10-28 07:28 PDT)

Now: the demo is one clean showcase page — [ohmarchy-demo.vercel.app](https://ohmarchy-demo.vercel.app) — with a consistent, honestly-captioned video set (the earlier old/new mix is archived, not deleted). Before that, policy acceptance tests on the device turned up two of our own earlier claims that were wrong, and both are now corrected in the docs. The sandbox's permission controls (`policy.conf`) are verified and committed. Handover: [docs/handover.zh-CN.md](docs/handover.zh-CN.md). B is public: [release b-20261027](https://github.com/BH3GEI/ohmarchy/releases/tag/b-20261027). Rehearsal recordings: [release rehearsal-20261028](https://github.com/BH3GEI/ohmarchy/releases/tag/rehearsal-20261028).

| Item | State |
|---|---|
| Correction: sandbox network isolation | **Was wrong, now honest** (1e54663). `ohm-capdrop --enter` did not join the net namespace, so processes started by `ohm-sandbox run` (desktop, terminal, apps) share the host network; earlier "can't reach 127.0.0.1" checks ran in the host netns and passed by coincidence. Per-sandbox netns is a finished, CLI-verified patch held back (the display/audio/ime bridge needs a host-side door first — post-demo). Demo now shows the real boundaries: can't see host files (mount ns) or host processes (pid ns) |
| Correction: a HarmonyOS ask withdrawn | **Good news** (1e54663): HongMeng already isolates abstract sockets per network namespace, like Linux (measured). The ask to add that (handover item 15) is withdrawn; the libc fence is now a redundant layer, not the boundary |
| Permission controls configurable | **Done + verified** (fdaa81b): a `policy.conf` the user edits (network, abstract-socket allowlist, shared host paths, capabilities, extra /dev), safe default, fail-closed on a bad file, each relaxation logged, `ohm-sandbox policy check`. On-device: dev=fuse, cap_keep, abstract_allow, broken-file fail-closed, read-write share all work; read-only share unusable (HongMeng won't remount a bind read-only) |
| Docker network isolation | **Verified real** (17f7fa0, 3cefa2c): with `NET=pasta`, dockerd and containers get Docker's own net namespace; containers can't reach a real listener on the host's 127.0.0.1 or LAN address (measured first-listener-then-connect). `demo.sh` refuses to run if dockerd shares the host netns |
| Autostart | init started `ohm-sandboxd` this boot (the `/system` cfg works); a real bug (boot-serve's `bm dump` gets no uid in init's context) was fixed live by reading the app's el1 dir owner (c3b077a). Full hands-off needs one more reboot to confirm |
| OSEasy persistence | **Blocked by the device, not our code** (7194b6b): after reboot OSEasy's picker can't enumerate user files (system Files app can) — an OSEasy-side grant that doesn't restore across reboot, and gets worse each reboot. Protocol work + agent + runbook ready; needs one clean environment |
| Demo videos | **One clean showcase page**: [ohmarchy-demo.vercel.app](https://ohmarchy-demo.vercel.app) — three segments (native+Docker, sandbox, 鸿融) and a rebuilt full cut, consistent names `demo-1/2/3` + `demo-full`, honest captions. Same set on [release rehearsal-20261028](https://github.com/BH3GEI/ohmarchy/releases/tag/rehearsal-20261028); earlier mixed/old cuts archived, not deleted. 21 screenshots + report in `docs/img/rehearsal/` |

Also: 鸿融 demo-disk password + sudo/unlock verified; E waiting for boot-key tries.
<!-- progress:end -->

What was tried and why other paths fail: [docs/findings.md](docs/findings.md).

## For the HarmonyOS teams

The routes boil down to two lines of work, and each needs something from a different team.

### Line 1: what the VM apps are asked for

**1. Plug and play in the VM apps (B Oseasy, C 鸿融).** A user installs a VM app from
AppGallery and boots our image; no root. This works today. What keeps it from perfect is in
the apps themselves: neither asks the system for a higher refresh rate, so the screen stays
at 60 Hz; Oseasy's lifecycle is built around a Windows guest agent (no "start" button for a
Linux VM; "再次安装" wipes the disk, so the system is being moved into an ext4 image file in Oseasy's shared folder that the probe boots directly, ~10 s, state kept); 鸿融 needs its guest agent
(增强服务) in the VM to show it as running and to shut it down. Being prepared for public
release: no-root install, images on GitHub Releases, a user guide.

- **鸿融 team** ([docs/internal/hongrong-team-brief.md](docs/internal/hongrong-team-brief.md),
  Chinese): present a fullscreen VM at the guest's (or the panel's) 120 Hz; make the guest
  agent (增强服务) install on any distribution, without dpkg; document the 本地文件 import
  format (the qcow2 os_type byte); write `logind.conf` as a drop-in instead of replacing it;
  show the real VM state and shut down through ACPI when no agent is installed; pass the
  HMV ID-register and ITS issues on.
- **Oseasy vendor** ([docs/oseasy-vendor-request.md](docs/oseasy-vendor-request.md),
  Chinese): a real start/shut-down lifecycle for Linux guests (no disk wipe before
  "再次安装"); a Linux guest agent or the published agent protocol; 120 Hz display modes;
  a shared folder that keeps owners and permissions; optionally, importing an existing
  disk image.

### Line 2: what HarmonyOS would need to provide for native

**2. Native (D, with I as its Docker backend).** The best result: 120 Hz, the Maleoon GPU
directly, 74 of 78 apps open in under 3 s, Docker from the native terminal. It needs root.
For it to become "install one app from AppGallery and get the Omarchy desktop", HarmonyOS
would have to provide:

| What HarmonyOS would need to provide | Why | How we work around it now |
|---|---|---|
| **Let an app run the Linux programs it ships** (relax XPM for this case, or a dedicated signature or permission) | Today an app can only run code signed into its HAP | J: rebuild the whole stack as .so files signed into the app — works, but it's a lot of porting and there's no `pacman` at run time |
| **Kernel features: user namespaces, cgroup v2, shared `CLONE_FS`** | Needed for sandboxes, containers and Chromium's sandbox | A root chroot; Docker in I's VM; Firefox as the browser |
| **Open the VM API** (`MANAGE_VM` is a hard-coded allowlist of 8 apps) | I's background VM | Root on `/dev/hmv` |
| **Fix two HMV issues** (unknown ID registers hang the vCPU; ITS event IDs) | Current Linux kernels hang on HMV | Kernel patches; report: [docs/hmv-idreg-report.md](docs/hmv-idreg-report.md) |

With the first two, D would run without root at today's performance.

## Recommended demo (about 10 minutes)

Scripts and click coordinates are in [docs/demo.md](docs/demo.md); `tests/demo/{d,i,b}.sh`
drive the same steps remotely. The hypervisor runs one VM at a time, so the order is
chosen to hand it on cleanly.

| # | Part | What it shows | Time (rehearsed) |
|---|---|---|---|
| 1 | **D native desktop** ([demo.md D](docs/demo.md#d-omarchy-natively-on-harmonyos)) | `omarchy desktop start` on the host, then open "Omarchy (native)". Hyprland with the Omarchy bar, a foot terminal with fastfetch (Arch on the HongMeng kernel), workspace switching at 119 fps, Firefox, the Omarchy menu, Files | 80 s end to end (635265e) |
| 2 | **I Docker from the native terminal** ([demo.md I](docs/demo.md#i-docker-on-the-native-desktop)) | `ohmarchy-vm start` on the host, then in D's terminal `docker run hello-world` and a compose service with a bind mount from the home directory. Files come back as 0644, owned by the desktop user. Then `ohmarchy-vm stop` | 91 s, all PASS (f62265a) |
| 3 | **C 鸿融** ([demo.md C2](docs/demo.md#c-omarchy-in-鸿融)) | Yao's main VM: start from 鸿融, log in, terminal + fastfetch, Chromium on omarchy.org, workspace switching. Stop it **from 鸿融's UI** | 3 min 41 s (6df8c0d) |
| 4 | **B Oseasy** ([demo.md B](docs/demo.md#b-omarchy-in-oseasy)) | Starting from no VM: create the VM in Oseasy, the installer writes Omarchy, reset, and Hyprland is up 6 s later. Then es2gears, workspace switching and app launches (foot 0.08 s, nautilus 0.6 s, chromium 0.8 s) | ~3 min plus ~1 min setup (73afc8e) |

D and I take about 3 minutes together, C about 4 and B about 4, so roughly 10 to 11
minutes. C1 (importing the developer image through 鸿融's UI, about 6 min) is the
alternative to C2. It needs Yao's main VM backed up and deleted first, because 鸿融
1.1.1.103 holds one VM.

Why the other routes are not demoed: A shows only terminal tools in a third-party
launcher, not Omarchy's desktop. E is not started. F runs only in the emulator and takes
14-50 min to its first desktop. G and H are concluded negative. J runs only busybox so
far. K is not started. L is paused and has never run on the device.

For the person at the keyboard on stage: the operator manual,
[docs/demo-operator.md](docs/demo-operator.md) (中文:
[docs/demo-operator.zh-CN.md](docs/demo-operator.zh-CN.md)).

## 1. VM apps: plug and play, no root

### Route B: the whole OS in the Oseasy VM

**How it works.** Oseasy虚拟机 (`com.oseasy1.ohvm` 3.1.1.7, from AppGallery) is a
Windows-on-ARM VM app. It has no VMM of its own. It describes the VM to the system
`@ohos.virtualization` kit, and `vm_manager` starts StratoVirt on the HarmonyOS hypervisor
(HMV): `accel=hmv`, 6 vCPUs, 8 GB, UEFI.

The display device is `svga-pci`, a VMware SVGA II (`15ad:0405`) with a 16-byte **MMIO**
register BAR, 256 MiB of VRAM and a 2 MiB FIFO. The host backend follows VirtualBox's
VMSVGA: SVGA3D/VGPU10 commands run on D3D11 through DXVK, on Vulkan on the Maleoon GPU,
and the result is presented with a mailbox swapchain into the app's XComponent. Input
arrives as USB keyboard and tablet plus virtio-multitouch. The network is a bridge at
`172.16.100.1/24` with NAT and no DHCP; the guest is `172.16.100.2`. Audio is
`ivshmem-scream`, which has no Linux driver.

```
guest: Hyprland → Mesa SVGA3D (GLES 3.0) → vmwgfx-oseasy → svga-pci
host:  StratoVirt SVGA backend → D3D11 (DXVK) → Vulkan (Maleoon) → Oseasy's window
```

**Kernel.** On the Fold every kernel from 6.5 on hung early, so the first pipeline used
Debian's 6.1. The cause turned out to be the HMV ID-register quirk (see
[Shared findings](#harmonyos-virtualization)). Omarchy's `linux-aarch64` 7.2.12-1.1 with
`arm64.hmv_idreg_quirk` boots in Oseasy, as it does in 鸿融.

**The driver: `driver/vmwgfx-oseasy-7.2/`.** This is Linux 7.2.12's vmwgfx with HMV
support ([patch](driver/vmwgfx-oseasy-7.2/hvm-oseasy-vs-linux-7.2.patch)), packaged by
`oseasy/vmwgfx-7.2/build.sh`. Stock vmwgfx expects I/O ports and fails. The patch adds:

- `hvm_mmio=1`: registers go through the MMIO BAR. `hvm_display=2`: screen objects (the
  host rejects screen targets). `msg_enabled=0`: no VMware backdoor. `hvm_refresh=120` with
  a timer vblank (`hvm_vblank`), because the device has no EDID.
- No cursor plane under HVM. The device reports `CURSOR_MAX_DIMENSION` 0, so every atomic
  commit that touched the cursor failed.
- A whole-surface upload before screen-object blits, only for dumb buffers the GPU has not
  written. Without it, CPU-written buffers showed black.
- **Fix 1: a 1 ms fence poll** (`hvm_irq_poll_us`, default 1000). vmwgfx signals fences
  from its interrupt handler, and this device raises no interrupts in practice, so a
  nonblocking commit could wait forever on a fence. Hyprland stalled with
  `isPageFlipPending true`. The timer does the interrupt thread's work.
- **Fix 2: `GEM_CLOSE` on TTM prime handles.** Hyprland 0.56 checks every client dma-buf
  with `drmPrimeFDToHandle` + `drmCloseBufferHandle`. vmwgfx returns TTM handles, which
  `GEM_CLOSE` rejects with `EINVAL`, so Hyprland refused every GPU-rendered client (es2gears
  never drew, nautilus never mapped). The ioctl wrapper now turns that into
  `ttm_ref_object_base_unref()`. A leak check of 2 x 2000 rounds came out clean.
- **Fix 3: a delay before command-buffer headers are retired** (`VMW_CMDBUF_RETIRE_US`,
  5 ms). GPU soaks hung after 38 and 51 min. Over netconsole this showed as an oops in
  `dma_pool_alloc` with a free-list link corrupted at the bytes of `SVGACBHeader.errorOffset`,
  which the device writes. With polling, the guest freed a header as soon as it read
  `COMPLETED`, possibly before the device's last write. Completed headers now wait 5 ms
  before going back to the pool, and any late write is logged. The cause is inferred from
  the backtrace: no late write was ever caught, with a 5 ms window or with a 50 ms one.
- **Page-flip watchdog** (`hvm_flip_watchdog_us`, default 50 ms). The 1 ms poll completes
  a flip whose vblank event was armed but never delivered, and counts each time it does.
  On the device it fired 0 times, including under `AQ_TRACE`, which used to bring on the
  stall. It stays in as a safety net (61e5998).

**Getting the disk in.** In this Oseasy version the create flow only takes ISOs. So
`PROBE_DEFAULT=4 oseasy/probe/build.sh` makes an installer ISO whose default GRUB entry
(install mode) listens on `172.16.100.2:5003`, receives a zstd stream of the Omarchy disk
(`omarchy-pure.img.zst`, 3.35 GB for a 64 GiB image), writes it with
`dd conv=sparse`, adds `vmwgfx-oseasy`, and runs `depmod` and `mkinitcpio` in the target.
On the host, a root shell streams the image (`oseasy/push-disk.sh`). A reinstall takes
131-147 s; the rehearsal measured 61 s for the write.

**Measured** (MateBook 14, 2026-10-24/25, details in the doc):

| | Result |
|---|---|
| Guest frame rate | 120 fps (kmsgl, modetest, Hyprland + es2gears) |
| Frames reaching the host window | 120/s (`dxvk-submit` flushes) |
| On screen | 60 fps; workspace switching 60 |
| glmark2-es2-wayland 1280x720 | 1083 (swap interval 0, measured before the GEM_CLOSE fix) |
| Hyprland after a VM reset | 6-7 s; warm reboots 3 of 3 (21-22 s) |
| App launch (first window) | foot 0.07-0.08 s, nautilus 0.60-0.90 s, chromium 0.81-1.17 s, obsidian 0.66 s |
| GPU-load soak (two es2gears + workspace switching) | 77 min (5 ms hold) + 3 h 07 min (50 ms hold): no oops, 0 late writes |
| Oseasy app cold start | 1.1-1.9 s |

**Limits and why.**

- **60 Hz on screen.** HarmonyOS raises the panel to 120 Hz only when a visible window asks
  for it, and Oseasy never asks (no frame-rate call in its ArkTS or native code). A tiny
  helper window that asks for 120 Hz (`oseasy/vote120`, `com.ohmarchy.vote120`) counts only
  while it has focus. A second layer also moves RenderService from the display hardware
  to GPU composition, which reaches only 35-51 frames/s. So 120 Hz cannot be reached from
  outside Oseasy.
- Oseasy forgets a non-Windows VM once it is powered off and offers only 再次安装. The
  demo therefore starts from no VM. We decided not to emulate Oseasy's Linux guest agent,
  since that would bypass the commercial app's own install checks.
- Oseasy allows one trial per device, then requires a purchase. It holds one VM per app,
  and the system holds one VM in total.
- Diagnostics run under `AQ_TRACE=1` stalled after about 160 frames, because tracing
  widens the lost-flip race. It was removed from `boot-diag.sh`.

Details: [docs/oseasy-whole-os.md](docs/oseasy-whole-os.md) (every run, from the first on
the Fold to the fifteenth).

### Route C: the whole OS in the 鸿融 VM

**How it works.** 鸿融 (`com.huawei.medivh`, now 1.1.1.103) is Huawei's own Linux VM app.
It also runs StratoVirt on HMV, but Linux guests get `vhost-user-gpu-pci,virgl=true`. The
backend is the system's `vhost-device-gpu` (rust-vmm 0.2.0), which runs the system's
OpenHarmony port of virglrenderer on Mesa's zink, on the Maleoon Vulkan driver, and
presents through `libhwf_kits.z.so` into 鸿融's window. There is no Venus, so the guest
has no Vulkan, and no blob resources, so frames are copied. Hyprland ends up on GLES 3.0.
The network is the same `172.16.100.0/24` bridge with NAT and no DHCP. Other devices:
virtio-sound, vsock (used by the guest tools), virtiofs (Documents) and a balloon.

**Two disks.**

1. **Yao's main VM**: deepin 25 installed by 鸿融, with Arch Linux ARM + Omarchy in
   `/arch` on deepin's data partition, booting deepin's 6.6.143 kernel through a
   `subroot` initcpio hook (`hongrong/10-bootstrap-arch.sh`, `20-install-omarchy.sh`).
   This was the first working desktop, and it is the one shown in demo C2.
2. **The developer image**: pure Omarchy 4.0.6, no deepin. It is built from scratch by
   `hongrong/pure/build-disk.sh` (it runs in route D's Arch environment on the host) and
   converted by `hongrong/pure/make-qcow2.sh`: GPT, a 512 MiB ESP with GRUB at the
   removable path, an ext4 root, and a 256 GiB qcow2 (9.6 GB of data). The kernel is
   Arch's `linux-aarch64` 7.2.12-1.1 with two patches
   (`hongrong/kernel/patches/`), installed as a pacman package:
   - `0001`: upstream `5a9d62555e71`. The host's GIC ITS reports 32 event-ID bits,
     `its_create_device()` clamped the vector count to 0, every MSI failed, and vsock never
     got an interrupt.
   - `0002`: `arm64.hmv_idreg_quirk` reads the ID registers Linux started reading after 6.8
     as zero. HMV hangs the vCPU on `ID_AA64PFR2_EL1` (see Shared findings).

**The import fix.** 鸿融 rejected every qcow2 we tried. Its hilog showed that `vm_manager`
runs `stratovirt-img get DISK os_type` and refuses type 0. os_type is the last byte
(offset 255) of StratoVirt's 256-byte qcow2 v3 header. qemu-img writes 0; 鸿融's own disks
have 1. `hongrong/pure/qcow2-stratovirt-header.py` now writes 1 (c9ddc15), and
`omarchy-dev-7.2.12-os1.qcow2` imports through 本地文件 → 开始安装. The VM starts by
itself and shows the SDDM login in under a minute (341225c).

**120 Hz.** 鸿融's backend EDID offers only 60 Hz. `hongrong/edid/mkedid.py` builds a
2160x1440@120 EDID, loaded with `drm.edid_firmware`. If that timing is marked preferred,
virtio-gpu's `mode_valid` deletes it whenever it differs from the host scanout by more than
16 px. With no preferred timing, the guest runs `2160x1440@119.98`. 鸿融 still presents its
fullscreen VM at **60 Hz**, and bringing another window to the front makes 鸿融 leave
fullscreen. This is on 鸿融's side.

**Measured.**

| | Result |
|---|---|
| Renderer | `virgl (zink Vulkan 1.2 (Maleoon 916))`, Mesa 26.2.5 |
| glmark2-es2-wayland fullscreen | 596 |
| On screen | 60 fps (es2gears and workspace switching 59-60), guest at 114-120 |
| Docker | 29.9.2, overlayfs, cgroup v2: hello-world, postgres, compose with nginx (through registry mirrors) |
| Boot | developer image: cold boot + 3 warm reboots pass; 30 min soak with all 6 vCPUs busy, no fault |
| Import | 9.6 GB, under 1 min |
| App launch (main VM, warm) | foot 0.08-0.13 s, nautilus 0.62 s, chromium 0.80-0.86 s, obsidian 1.16-1.30 s |
| Demo C2 | 3 min 41 s |

**Limits.** 60 Hz on screen. One VM in 鸿融 1.1.1.103, and one on the system. AppGallery
updates 鸿融 by itself (it replaced 1.3.1.80 with 1.1.1.103), so turn automatic updates
off. Warm reboots from inside the guest can hang intermittently on the deepin setup (a
virgl MMIO trap after reset), so power off and start from 鸿融 instead. The guest tools'
installer handles only UOS and Kylin. Logging the session out with `loginctl
terminate-session` sent 鸿融 into a greeter loop; restarting the VM from 鸿融 fixes it.

Details: [docs/hongrong-whole-os.md](docs/hongrong-whole-os.md), and the report to
Huawei: [docs/hmv-idreg-report.md](docs/hmv-idreg-report.md).

### Route G: the 铠大师 VM (concluded)

铠大师 (`com.sanway.ecoengine` 3.5.8.14) uses the same `vm_manager` and `svga-pci` path as
Oseasy. Its Windows 11 24H2 check reads only the WIM XML, so a 2.5 KB fake
`sources/install.wim` (`tools/kaidashi/make-fake-wim.sh`, `wrap-iso.sh`) gets any UEFI ISO
accepted. Secure Boot is off, and the 7.2.12 quirk kernel boots. But every VM the wizard
starts is an **install session**. In `libvm_manager.z.so` it ends successfully only when
铠大师's Windows guest service reports back. Otherwise a power-off or closing the window
makes the app delete the VM. Install sessions also get a NIC with no MAC and no iothreads,
which never receives. A persistent Omarchy VM would mean impersonating its Windows guest
service, which is out of scope. It would offer nothing over B anyway: same device, 60 Hz.
Closed 2026-10-24. Details: [docs/vm-kaidashi.md](docs/vm-kaidashi.md).

## 2. Native on the HongMeng kernel

### Route D: native on the HongMeng kernel

#### The chroot

The HongMeng kernel implements enough of the Linux ABI to run an unmodified Arch Linux ARM
userland. Threads, futexes, epoll, eventfd, timerfd, signalfd, inotify, sealed memfd,
io_uring, ptrace (gdb, strace), large sparse mmaps, ptys and sockets all work; the page
size is 4K. The Arch root is a 64 GB sparse ext4 image (`/data/local/archtest/arch.img`),
because `/data` is hmfs mounted `nosuid,nodev`. `native/arch.sh` attaches it with
`losetup`, enters a private **mount + pid namespace** (`unshare -m -p`) with catatonit as
pid 1, and `chroot`s. `bin/omarchy` joins it with `nsenter` and switches user with
coreutils `chroot --userspec`. The session shares the host's network namespace. The
desktop user is `builder`, uid 60000, because HarmonyOS uses most uids below 10000.

Omarchy 4.0.6 installs from its signed AArch64 repository: about 900 packages, through a
proxy because GitHub is unreachable from the host. `omarchy-apply-system` is not run,
because its ufw step would load firewall rules into the HarmonyOS kernel.

HongMeng quirks met, and the fixes in `native/`:

| Quirk | Workaround |
|---|---|
| No user or cgroup namespaces, cgroup v1 only | no systemd as pid 1, no rootless containers; root `unshare -m -p`; shims for `systemd-cat`, `uwsm-app`, `systemd-run --user` |
| No Landlock | `DisableSandbox` in pacman.conf |
| Loop devices: only `loop0` has a `/dev` node; toybox `mount -o loop` gives EFAULT | `losetup` on `/dev/block/loopN` by hand |
| devpts has no `ptmx`; binding device nodes fails | tmpfs `/dev` with `mknod`, the host's `/dev/pts` |
| `splice()` from a drained pipe returns EPIPE instead of 0 (coreutils `cat` exits 1) | `ld.so.preload` shim |
| `statx(fd, "", AT_EMPTY_PATH)` returns EFAULT (GTK apps, glycin) | `hongmeng-statx.c` preload |
| A blocked `msgrcv` is not woken by `msgsnd` (fakeroot, makepkg hang) | `hongmeng-msgrcv.c` preload polls |
| `PR_SET_KEEPCAPS` not permitted (setpriv fails) | `chroot --userspec` |
| `uname` says HarmonyOS/HongMeng (cmake) | `hongmeng-uname.c` |
| **`clone(CLONE_FS)` does not share root and cwd** | Chromium's setuid sandbox cannot jail its zygote, so Chromium runs `--no-sandbox`; Firefox (seccomp-bpf works) is the default browser and opens the web apps |
| **SELinux: root's `su` domain is permissive; no transition to a narrower domain** (`/proc/self/attr/exec` refused) | the broker and session init stay in `su`; their work runs as uid 60000 where possible |
| g++ 16.1 crashes (ICE) on aquamarine/Hyprland | build with clang |

#### The desktop

```
HarmonyOS app "Omarchy (native)" (native/app)       Arch chroot (route D)
  XComponent window  <── presents GPU frames ──┐    Hyprland 0.56.2 (patched) + Omarchy shell
  in-app vtest + system libvirglrenderer        │      GL: Mesa virpipe → /tmp/.virgl_test
    → zink → Vulkan → Maleoon GPU          <────┴──────  (vtest-broker, root, hands the fd to the app)
  keys/pointer/touch/IME ── 16-byte msgs ──>  @ohmarchy-display (aquamarine headless backend)
  OHAudio fast mode      <── PCM ──────────   @ohmarchy-audio (PipeWire sink "HarmonyOS")
```

- **No DRM device.** `native/desktop/patches/aquamarine-0.15.1-hongmeng.patch` adds a
  dma-heap allocator (`/dev/system_heap2`, mode 666) and a headless backend that exports
  frames and takes input over the abstract socket `@ohmarchy-display`.
  `hyprland-0.56.2-hongmeng.patch` renders on surfaceless EGL
  (`EGL_PLATFORM_SURFACELESS_MESA`) with read-back, and adds a present marker: after each
  frame it blits one pixel into a 7x3 texture (`HYPRLAND_READBACK_PRESENT`).
- **GPU path.** The renderer runs inside the app: upstream vtest
  (`native/app/vtest-inapp.patch`) on the device's own `libvirglrenderer.so.1`, which is
  the library 鸿融's VMs render with, bundled into the HAP by `gpu-prep.sh`.
  `NEED_OPENGL=1` makes the system EGL load Mesa's zink on the Maleoon Vulkan driver.
  Mesa's virpipe in the chroot connects to `/tmp/.virgl_test`, and
  `native/vtest/vtest-broker.c` (root on the host) passes the connection to the app, only
  to the app's uid (SO_PEERCRED). When the app sees the marker blit in the command stream,
  it presents the frame with `virgl_renderer_ohos_present` into its window: no copy, no
  vsync wait. The library gets its window from `libhwf_kits.z.so`, so the app ships its own
  `hwf_kits.c` that returns the XComponent's window.
- **120 Hz.** The panel idles at 60 Hz. The app calls
  `OH_NativeXComponent_SetExpectedFrameRateRange({60,120,120})` and drops to 10 Hz after a
  second without frames (which took the app's idle CPU from ~14 % to 1.9 %). The output
  mode is `@120`.
- **GPU clients.** Apps render on llvmpipe by default, because the system virglrenderer
  rejects some of Qt Quick's commands. `ohmarchy-gpu APP` runs an app on virpipe. Its
  read-back is copied on the GPU into a snapshot that Hyprland's texture upload picks up,
  and `libohzc` keeps Mesa from copying the rest of the frame on the CPU.
- **Sound.** PipeWire plays into one sink, "HarmonyOS"; `ohmarchy-audio-relay` serves it on
  `@ohmarchy-audio` to the app's uid only; the app plays it with `OH_AudioRenderer` in fast
  mode (48 kHz, 5 ms callbacks).
- **Input.** Pointer, buttons, scroll and evdev key codes go to aquamarine's headless
  devices. fcitx5 pinyin works (Ctrl+Space). The HarmonyOS IME through `ohime`
  (`OHMARCHY_IME=harmony`) is built but not yet verified on screen.
- **Signing.** The research build accepts HAPs signed with the SDK's OpenHarmony test keys
  and a debug profile bound to the device's UDID (`native/app/sign/sign.sh`), installed with
  `bm install` as root.

#### Acceptance results ([docs/acceptance.md](docs/acceptance.md))

| Item | Result |
|---|---|
| A1 every app opens in 3 s | 74 of 78 pass, 0 failed, 3 unsupported (no camera; systemd user units), 1 skip; median 0.58 s, P95 1.13 s |
| A2 core operations | 6 of 6: LibreOffice and Neovim files, clipboard, Chinese input, sound, file chooser |
| A3 sound | first sound median 101 ms (max 133), during playback 72 ms; A/V within 100 ms; a -12 dBFS tone reaches the sink at -12.0 dBFS. Not yet heard by ear |
| B cold start | about 8 s (session 2.0 s + desktop 5.7-6.1 s) |
| B workspace switch | 119.4 fps (target ≥ 110) |
| B es2gears on screen | 117-120 fps native vs 60 in the 鸿融 VM, for the same CPU (+8.4 vs +8.9 points) |
| B idle | desktop 0.5 % of a core, app 1.9 %, 1.0 GB |
| C stability | 100 open/close rounds (+0.1 % memory); 24 h soak: 23 of 25 hourly runs ok (the 2 failures were our own desktop stops), no memory growth; DPMS 20/20; app background/foreground 20/20; HarmonyOS screen off/on 20/20; network and DNS outage: back within 0.1 s |
| D recovery | fresh install from nothing about 30 min; `reset.sh` to a clean image in 56 s; `check-upgrade.sh`; log bundle |
| E security | ordinary user; sudo asks for a password; no TCP listeners; GPU and sound sockets only for the app's uid; Firefox sandboxed. Open: Chromium started by hand (CLONE_FS), the `su` domain |

**Limits.** No systemd services (NetworkManager, bluez, cups, Wi-Fi/Bluetooth widgets, power
menu). No camera, microphone, backlight or removable media. No Docker of its own, which is
what route I adds. Closing the app ends Hyprland's GPU connection, so restart the desktop
after reopening it. Screenshots read a CPU copy that is no longer filled. The boot service
(`native/boot/`) is installed but has not yet been verified by a reboot. App by app:
[docs/native-compat.md](docs/native-compat.md).

Details: [docs/native-chroot.md](docs/native-chroot.md),
[docs/native-desktop.md](docs/native-desktop.md).

### Route I: our own VM on the hypervisor

**How it works.** As root, `tools/ownvm/ohmarchy-vm` starts the system's StratoVirt on
`/dev/hmv` with no VM app: 6 vCPUs, 8 GiB, virtio-blk, virtio-net on its own tap `ohmvm0`
with rx/tx iothreads, vsock, and `virtio-balloon-pci,deflate-on-oom=true,free-page-reporting=true`.
The GPU is optional (`OVM_GPU=1` adds `vhost-device-gpu` with `virgl=true`). The disk
`omarchy-own.img` is the developer image of route C plus the no-preferred 120 Hz EDID,
edited offline with `debugfs` (`tools/ownvm/prep-disk.sh`).

- **Network.** The host's policy routing sends `172.16.100.2` out over Wi-Fi. Two rules
  (`pref 10500` to main, `pref 10501` from the tap to table 2009) are added on start and
  removed on stop.
- **Docker for D.** `guest-provision.sh` enables Docker with registry mirrors and a narrow
  sudo rule for power-off. dockerd is not exposed on TCP. D's docker CLI first used context
  `ohmarchy` = `ssh://yao@172.16.100.2` (the desktop user's key, the guest's host key
  pinned). Since caecc94 the context is `unix:///tmp/.ohmarchy-docker.sock`, served by
  `tools/ownvm/ohmarchy-docker-gate.c`. That is a root daemon that `omarchy desktop start`
  runs next to the GPU broker, and it accepts only uid 60000 (SO_PEERCRED). On the first
  connection it starts the VM, then proxies each connection to the guest's
  `docker system dial-stdio`. A VM it started is stopped 30 s after the last use with no
  running container. While 鸿融 or OSEasy runs a VM (HMV runs one VM at a time), docker's
  error names that app and a HarmonyOS notification says the same. So the desktop user
  needs no root shell for Docker. The VM may use up to 12 GiB (idle it still costs the host
  ~1.2 GiB: freed pages go back through the balloon in under a minute). x86-64 images run
  under qemu-user (`--platform linux/amd64`; pure Python ~50x slower, C code ~4x). No GPU in
  containers yet ([docs/vm-own.md](docs/vm-own.md#docker-limits-2026-10-27)). The start-at-boot service
  (`ohmarchy-vm.cfg`) stays uninstalled, so that the hypervisor is free for 鸿融 and Oseasy.
- **Home share.** D's `/home/builder` appears in the guest at the same path, so bind mounts
  work. The share is virtiofs with `--translate-uid` (guest root writes as 60000 on the
  host). virtiofsd runs as uid 60000 with no capabilities and `NoNewPrivs`, through
  `tools/ownvm/dropuid.c`, because setpriv fails on HongMeng. `--sandbox none` is needed,
  as when StratoVirt starts virtiofsd for 鸿融. HarmonyOS's own virtiofsd 1.13.0 forced
  every file to 0660 and ignored chmod, so the default is now **upstream virtiofsd 1.14.0**,
  built static with musl (`tools/ownvm/build-virtiofsd.sh`): files 0644, directories 0755,
  chmod works (2235eaf).
- It refuses to start while another StratoVirt runs: 鸿融 uses the same subnet, and HMV
  runs one VM.

**Measured.** Guest ssh up 5-10 s after start. Network, DNS, HTTPS and pacman work. The guest
runs `2160x1440@120` with virgl on the Maleoon GPU when enabled. Docker 29.9.2 with
hello-world (1.2 s from D), compose and published ports. Host RSS is about 1.17 GiB idle for
an 8 GiB guest: after 3 GiB was written and freed in the guest, RSS went from 4109 MiB back
to 1161 MiB in about 6 s. Stop (power-off from inside) takes about 10 s. Demo `i.sh`: all
PASS in 91 s.

**Not done.** Showing this VM's desktop in D's app ("remote virgl"). The transport works
(guest virpipe over TCP → broker → app), but with vtest protocol version 0 the guest's
resource ids collide with Hyprland's in the shared renderer. Version 3 needs shared-memory
fds, which cannot cross TCP. Another process cannot draw into the app's window either
(`OH_NativeWindow_CreateNativeWindowFromSurfaceId` is per process). Decided 2026-10-24: I
stays headless. Running `docker` through `ohmarchy-vm ssh` from the host can hang when
the output comes back over ssh; this does not happen from D's terminal.

Details: [docs/vm-own.md](docs/vm-own.md).

### Route J: Linux in an app sandbox (no root)

**What the sandbox allows.** A probe HAP (`native/xpmprobe`) tested every way to run new code
in a normal debug app:

| Mechanism | Result |
|---|---|
| anonymous RWX mmap, RW → `mprotect` +X, memfd dual map | blocked: no `ALLOW_WRITABLE_CODE_MEMORY`, XPM "jit set mem violated" |
| `execve` an unsigned ELF in the sandbox | blocked, `EACCES` |
| `execve` an ELF packed in the HAP's `libs/` | blocked: installed 0644, `EACCES` |
| `dlopen` an unsigned `.so` from the sandbox | blocked |
| `execve` a signed system binary | works |
| `dlopen` a `.so` signed into the HAP | works |

So a no-root app can only run code that is signed into the HAP at build time, by `dlopen`.
It cannot JIT, run pacman at run time, or exec new binaries. `fork` is allowed.

**Prototype.** busybox 1.36.1 is built as `libbusybox.so` (`device/jloader/build-busybox.sh`,
OHOS clang/musl, applets in-process). The loader forks, `dlopen`s it and calls its `main`.
Pipelines, `$$`, background jobs, command substitution and loops work (`native/jloader`).
It now runs inside D's display app: `native/app/entry/src/main/cpp/jl/bbload.cpp` forks a
single-threaded spawner on `start()` that closes all inherited fds, and it is off by default
(9d4000c, 9a6539d).

**The Hyprland stack for OHOS musl.** D's glibc binaries cannot be loaded into the app's
musl process. Versioned symbols aside, glibc and musl lay out the thread pointer's TCB
differently. So the stack is being rebuilt against OHOS musl, without LLVM, Xwayland or
libinput. The target is about 25-40 MiB instead of the 272 MiB of D's libraries.
`device/userspace/`:

| Stage | Contents | State |
|---|---|---|
| 0 | toolchain: OHOS clang 15 is too old for C++26; upstream clang 23 + libc++ built for musl | done |
| 1 | libffi, pixman, libdrm, libxkbcommon, wayland 1.23.1 | done (543a223) |
| 2 | Mesa 24.3.4, virgl only, no LLVM: ~16 MiB, vtest winsys | done (c6ff963) |
| 3 | one shared C++ runtime `libc++_ohm.so.1` (1.9 MiB, own SONAME), hyprutils 2.6 MiB, hyprlang 0.3 MiB; next the C support stack (cairo, pango, glib, fonts), then aquamarine and Hyprland with D's patches and the HongMeng shims built in. Hyprland 0.56.2 now compiles and links (18 MiB stripped); next is loading it on the device through D's app | built (3da87ce, 6065767, 845dc1b); not yet run on the device |

Details: [docs/no-root-routes.md](docs/no-root-routes.md).

## 3. Other explorations

### Route A: Omarchy apps in HarmonyOS's Linux engine

**How it works.** HarmonyOS PCs ship an official Linux engine (融合开发引擎): an openEuler
container with a terminal and no GUI. A third-party launcher from AppGallery
(融合开发图像引擎, `com.mikannqaq.developer.linuxEngine`) installs an X11 bridge into it
and shows each Linux app as its own HarmonyOS window. The container sees the GPU as
"Virtio-GPU Venus".

**What was built.** `linux-engine/install-omarchy-nvim.sh` and `install-omarchy-cli.sh`
install Omarchy's neovim configuration, plus static ARM64 builds of neovim, fastfetch,
btop and lazygit (openEuler has no neovim package). They retry GitHub downloads through
`gh-proxy.com` and replace Omarchy's theme symlink with a fixed theme.

**Limits.** Each app is a separate HarmonyOS window, so a nested Hyprland session does not
fit. Driving XTerm with `uitest inputText` loses the first characters after focus.
Details: [docs/linux-engine-apps.md](docs/linux-engine-apps.md).

### Route F: Aetherium on the DevEco emulator

**How it works.** No HarmonyOS hardware is needed. DevEco Studio's HarmonyOS 7.0 "2in1"
emulator runs on a Mac. Inside it, [Aetherium](https://github.com/AetheriumSimulator/qemu-hmos)
runs QEMU 10.1 in-process with TCG (the emulator exposes no EL2) and boots the stock Omarchy
4.0.3 disk on its own 7.2.3 kernel through Limine. The guest's screen is shown by the
HarmonyOS VNC client RemoteDesk.

**What was patched.** `emulator/lib/patch_aetherium.py` patches the pinned Aetherium HAP:
the unconditional `-tpmdev emulator` becomes `-L`, `virtio-gpu-pci` replaces the
legacy-MMIO virtio-gpu (which the guest rejects with status `0x83`), and the firmware is
padded to 64 MiB. Reported upstream as issues #49-#53. `emulator/10..60` script everything,
including the first-boot wizard over VNC, and autologin into uwsm, because SDDM's greeter is
killed after 21 s under TCG.

**Result.** The Hyprland desktop runs on llvmpipe. First-boot setup took 14 min scripted and
50 min the first time (mkinitcpio under TCG). It proves the stack works; it is not a usable
desktop. Details: [docs/emulator-aetherium.md](docs/emulator-aetherium.md).

### Route H: Aetherium on the device (concluded)

The route-F app signed for the device (`device/sign-hap.sh`) and installed as root. The goals
were a TCG baseline and an HMV accelerator. Results:

- **TCG cannot start.** QEMU aborts with SIGABRT in `tcg_region_init`, at 4 vCPU/4 GB and at
  1/2 GB alike. The HAP is not allowed writable-executable memory (confirmed directly by
  route J's probe).
- **No 3D and no 120 Hz in this QEMU.** `libqemu_full.so` links no virglrenderer, EGL or
  Vulkan.
- **HMV.** `/dev/hmv` is not KVM-compatible: every KVM ioctl returns `ENOSYS`. It uses the
  `0xAE` magic with its own command numbers; the run loop is `hmv_join_actvpool_thread` /
  `hmv_wait_next_vmexit` in `libhmlibs.so.0`. A root process in the `su` domain opens it,
  and its ioctls fail with `ENOSYS`/`EINVAL`, not `EPERM`. So there is no permission gate
  for root, only an undocumented ABI. A custom accelerator was judged feasible in principle
  and not built: route I already runs on the system StratoVirt.
- **The no-root VM service is closed.** A test app (`native/vmtest`) compiles against a stub
  of `@hms:virtService.vmManager`, installs, loads the module and reaches the service, but
  privileged calls return `201 Permission denied`. `libvm_manager.z.so` requires
  `ohos.permission.MANAGE_VM` **and** an appIdentifier from a hardcoded list of eight
  (Oseasy and 铠大师 are on it).

Details: [docs/device-aetherium.md](docs/device-aetherium.md),
[docs/vm-api.md](docs/vm-api.md).

### Route K: QEMU TCI (idea)

QEMU's TCG interpreter needs no executable memory. Aetherium's `libqemu_full.so` is a JIT
build (no `tci_*` symbols). A TCI build would have to be signed into a HAP as a `.so`, under
route J's rules. Not started, deprioritised.

### Route L: Linux in ArkWeb (paused)

**How it would work.** An ordinary HAP (`webemu/app`, `com.ohmarchy.webemu`) with an ArkWeb
`Web` component serves a page, the v86 emulator, the BIOS, the kernel and the disk (with HTTP
byte ranges) under `https://routel.local/` through `onInterceptRequest`. v86 compiles x86
blocks to WebAssembly at run time. The guest is Arch Linux 32 (i686, pacman 7.1, systemd 259,
kernel 6.19.11), built by `webemu/image/build-image.sh` with a 6 MB initramfs. The page has
an xterm.js console and a probe that tells whether the engine has wasm and JIT.

**Status.** Paused by Yao's decision on 2026-10-25. It never ran on the device (the screen was
busy), so whether ArkWeb gives a third-party HAP a wasm JIT is unknown. On desktop Chrome it
reached a root shell in 32-37 s at 400-1800 MIPS, with 928 JIT modules compiled and 0
failures. There is no guest network (pacman would need a relay). Details:
[docs/route-l-arkweb.md](docs/route-l-arkweb.md).

### Route E: bare metal

Linux directly on the hardware, with no HarmonyOS underneath. Not started; nothing in the
repo.

## Shared findings

### HarmonyOS virtualization

- **Who may run VMs.** Apps reach the hypervisor only through the system VM service
  (`@hms:virtService.vmManager` / `@ohos.virtualization`), which is not in the public SDK.
  `libvm_manager.z.so` requires `ohos.permission.MANAGE_VM` and an appIdentifier from a
  **hardcoded allowlist of eight**. Oseasy and 铠大师 are on it, as AppGallery partners
  with no declared VM permission. A debug-signed app gets `201 Permission denied`. Root can
  start StratoVirt on `/dev/hmv` directly (route I), but only an app can own a window.
- **One VM at a time, system-wide.** Starting a second VM is refused with **401 "Not support
  vm multi-instance"** (Oseasy's `createVm` while 鸿融's VM ran, tested 2026-10-25). Check
  `pidof stratovirt` before starting one.
- **鸿融 shows a running VM as 已关机 without its guest agent.** 鸿融 only moves a VM to
  RUNNING after its in-guest agent (增强服务, vm-agent) reports. Without it the VM stays in VIEWING, the card says 已关机 and the normal 关机 button is greyed out.
  Shut the VM down from inside the guest (Omarchy: Super+Esc → Shutdown); 鸿融 then shows
  已关机 correctly. Force stop only when the guest doesn't respond. A guest-side power-off
  goes through the same STOPPING → STOPPED states as a force stop
  ([docs/hongrong-whole-os.md](docs/hongrong-whole-os.md), eb4646b). Why Oseasy's
  `createVm` was sometimes refused although no VM process was running is still open.
  鸿融 also removes its bridge when its VM stops. Since e0e0b7b the agent, installed from
  the tools CD 鸿融 attaches, works in our developer image: the card shows 运行中 and the
  normal 关机 button shuts the VM down.
- **HMV ID registers.** Since Linux 6.9 the kernel reads `ID_AA64ISAR3_EL1`,
  `ID_AA64PFR2_EL1` and `ID_AA64FPFR0_EL1` at boot, and 6.17 reads `ID_AA64PFR2_EL1`
  again. HMV hangs the vCPU on at least `ID_AA64PFR2_EL1` instead of reading it as zero.
  The guest stops right after the EFI stub. This was found by bisect (merge `0c5ade742e91`,
  then the GICv5 check) and reported in [docs/hmv-idreg-report.md](docs/hmv-idreg-report.md).
  The workaround is the `arm64.hmv_idreg_quirk` kernel patch, used by B, C, G and I.
- **The GIC ITS reports 32 event-ID bits**, which breaks MSI before Linux's fix
  `5a9d62555e71`.
- **GPU backends.** For Linux guests, 鸿融 uses virgl → zink → Maleoon (OpenGL only).
  Windows-type VMs (Oseasy, 铠大师) get `svga-pci` → D3D11 → DXVK → Vulkan.
- **Refresh rate.** The panel follows the frame-rate votes of visible windows. A VM app that
  does not vote stays at 60 Hz. At 120 Hz, `hidumper ... "composer fps"` reads only the last
  384 timestamps and can over-report, so count frames with `hitrace` instead.
- **Debugging guests.** The guest serial console of Oseasy and 铠大师 lands in
  `/data/log/hwf_service/vmlog` (root can read it); 鸿融 sends it to `/dev/null`. Guest RAM
  can be read from the StratoVirt process (`memfd:stratovirt_anon_mem`).

### HongMeng kernel

There is no `/dev/dri` and no `/dev/kvm`. The namespaces available are ipc, mnt, net, pid,
time and uts, with no user or cgroup namespaces, and cgroup v1. There is no Landlock, and
`PR_SET_KEEPCAPS` is refused. `CLONE_FS` is not shared between processes. Root's SELinux
`su` domain is permissive, ordinary apps (`normal_hap_attr`) may connect to its unix sockets
and receive dmabuf fds, and `/dev/system_heap2` is a mode-666 dma-heap. Syscall
differences: `splice` returns EPIPE, `statx` with an empty path returns EFAULT, a blocked
`msgrcv` is not woken. Reading `/proc/PID/cmdline` of an exiting process can spin forever.
HongMeng's grep does not match the NUL-separated cmdline. Full table:
[docs/native-chroot.md](docs/native-chroot.md#hongmeng-quirks).

### Signing and XPM

- The test machine accepts HAPs signed with the SDK's OpenHarmony test keys and a debug
  profile bound to its UDID. A production build would need an AppGallery Connect
  certificate.
- XPM (code integrity) allows ordinary apps no writable-executable memory and no unsigned
  code. Only `.so` files signed into the HAP load, and system binaries exec. That is what
  rules out JIT emulators (H, K in its JIT form) and shapes J.

## On site: what needs someone at the machine

Everything else runs remotely. From [docs/acceptance.md](docs/acceptance.md#on-site-what-needs-someone-at-the-machine):

1. **Hear the sound.** Turn the media volume up (it was 0 in all tests), run
   `tests/audio/run.sh` for ten even beeps, then `mpv --fs` on a video to check lip sync.
2. **Screen off and on with the power button**, 20 times, with "Omarchy (native)" open. The
   timeout path already passed 20/20.
3. **Wi-Fi change.** Turn Wi-Fi off for 30 s and on again with a page open in Firefox, and if
   possible switch networks. Check `tests/stability/soak.sh status` afterwards.
4. **Battery power.** Charge to ≥ 80 %, unplug, fix the brightness, and run
   `tests/perf/battery.sh` for 30 min in each of five states (HarmonyOS only; native idle;
   native + es2gears; 鸿融 idle; 鸿融 + es2gears).
5. **A planned reboot with Yao present**, to verify that the boot service starts the native
   desktop (`native/boot/`). It was not done remotely: the last reboot replaced 鸿融
   1.3.1.80 with 1.1.1.103 by itself.

## Quick starts

One per route, in the order of the tree. Routes A, K and E have none.

### Route B quick start

Current path (7.2.12 kernel + `vmwgfx-oseasy`, MateBook 14). In Arch Linux ARM (route D's
environment works), with the HMV-patched `linux-aarch64` 7.2.12 package and its headers:

```sh
oseasy/vmwgfx-7.2/build.sh linux-aarch64-headers-7.2.12-*.pkg.tar.zst     # vmwgfx-oseasy package
PROBE_DEFAULT=4 oseasy/probe/build.sh OUTDIR linux-aarch64-7.2.12-*.pkg.tar.xz vmwgfx-oseasy-*.pkg.tar.xz
```

Copy `oseasy-probe.iso` to the device's `Download/`, put `omarchy-pure.img.zst` (from route
C's `hongrong/pure/build-disk.sh`) and `oseasy/push-disk.sh` in `/data/local/oseasy/`, then
create the VM in Oseasy as in [docs/demo.md](docs/demo.md#b-omarchy-in-oseasy).
`tests/demo/b.sh` automates the whole flow.

Original path (Fold, Debian 6.1 kernel, EFI framebuffer only). On a Linux host with `hdc`:

```sh
oseasy/10-fetch-inputs.sh       # Omarchy image (3.7 GB), Debian 6.1 kernel debs, Debian netinst ISO
oseasy/20-build-modules.sh      # SVGA driver + efidrm module against Debian's 6.1 headers
oseasy/30-prepare-image.sh      # qcow2 -> raw, read the partition layout and root UUID
oseasy/40-build-boot.sh         # 6.1 boot entries (UKIs) + Limine menu into the image's ESP
oseasy/50-make-installer-iso.sh # Debian netinst ISO carrying the Omarchy disk image
oseasy/60-push-iso.sh           # copy the ISO to the HarmonyOS Download folder
```

Then follow [docs/oseasy-whole-os.md](docs/oseasy-whole-os.md#install-in-oseasy). Settings
live in `oseasy/config.sh`; outputs go to `work/`. Host tools: bash, python3, curl, unzip,
bsdtar, cpio, gzip, qemu-img, sfdisk/blkid, mtools, xorriso, kmod, make, clang (aarch64
target), hdc.

### Route C quick start

Developer image (no root on the device): build it with `hongrong/pure/build-disk.sh`, then
`hongrong/pure/make-qcow2.sh RAW OUT` (it sets os_type 1). Copy the qcow2 to the file
manager's 下载 folder. In 鸿融, delete any existing VM first (it holds one), then
本地文件 → the qcow2 → 打开 → 开始安装. Details:
[docs/hongrong-whole-os.md](docs/hongrong-whole-os.md#developer-image).

Next to deepin (Yao's main VM): install deepin 25 (arm64) in 鸿融 and give it a static
address on `172.16.100.0/24`. Then, as root in deepin, run
`hongrong/10-bootstrap-arch.sh USER PASSWORD` and reboot, and in Arch run
`~USER/hongrong/20-install-omarchy.sh USER`. Details:
[docs/hongrong-whole-os.md](docs/hongrong-whole-os.md#install).

### Route G quick start

Concluded; the tools remain:

```sh
tools/kaidashi/wrap-iso.sh IN.iso OUT.iso            # any UEFI ISO passes 铠大师's Windows-only check
tools/kaidashi/installer/build.sh WORKDIR linux-aarch64-7.2.12-*.pkg.tar.xz   # 7.2.12 probe/installer ISO
perl -e 'alarm 180; exec @ARGV' ssh ohdev sh -s < tools/kaidashi/probe.sh       # read-only survey
tools/kaidashi/kds-run.sh start ROW ENTRY            # drive the wizard
```

### Route D quick start

As root on the HarmonyOS machine (a root shell that may `unshare`, `mount` and `chroot`; see
[docs/native-chroot.md](docs/native-chroot.md#getting-a-root-shell-on-the-host)), in a copy of
`native/`:

```sh
sh 10-make-image.sh                                  # Arch Linux ARM into /data/local/archtest/arch.img
sh /data/local/archtest/arch.sh start
sh /data/local/archtest/arch.sh run 20-setup-arch.sh builder
sh /data/local/archtest/arch.sh stop; sh /data/local/archtest/arch.sh start
sh /data/local/archtest/arch.sh run 30-install-omarchy.sh builder
/data/local/archtest/bin/omarchy                     # Omarchy shell as builder
```

The native desktop ([docs/native-desktop.md](docs/native-desktop.md)): run
`native/desktop/fetch-sources.sh` on a machine with GitHub access before copying `native/`,
build `native/vtest/build-vtest.sh` with DevEco's tools and copy `vtest-broker` to
`/data/local/archtest/bin/`, then

```sh
sh /data/local/archtest/arch.sh run 40-install-desktop.sh builder   # patched aquamarine + Hyprland in /opt/ohmarchy
/data/local/archtest/bin/omarchy desktop start
```

Install the app with `native/app/build.sh` and open "Omarchy (native)". `native/install.sh
USER GPU_BIN_DIR` does all of it in one go (about 30 min); `native/reset.sh` returns to a
clean image. Docker needs route I's VM running.

### Route I quick start

On the host, as root, with `omarchy-own.img` prepared (`tools/ownvm/prep-disk.sh`):

    sh /data/local/kaidashi/bin/ohmarchy-vm start     # returns when the guest's ssh answers
    sh /data/local/kaidashi/bin/ohmarchy-vm status    # VM, guest, dockerd, balloon, host RSS
    sh /data/local/kaidashi/bin/ohmarchy-vm stop

In D's terminal: `docker run --rm hello-world` (context `ohmarchy`; with the docker gate running, this starts the VM by itself).

### Route J quick start

`device/jloader/build-busybox.sh`, then `native/jloader/build.sh` and
`device/jloader-run.sh`. The Hyprland-stack stages are `device/userspace/build-stage{1,2,3}.sh`.

### Route F quick start

On a Mac (or any DevEco host) with DevEco Studio, `hdc`, `gh` and `python3`:

```sh
emulator/10-create-emulator.sh       # HarmonyOS 7.0 2in1 emulator image + instance, boot
emulator/20-fetch-inputs.sh          # Aetherium HAP (patched by emulator/lib/patch_aetherium.py), Omarchy qcow2, RemoteDesk
emulator/30-install.sh               # install the HAPs, copy the disk to 下载, forward VNC 15901 and serial 14321
emulator/40-create-vm.sh             # create and start the VM in Aetherium (UI driven by text)
emulator/50-first-boot.sh USER PASS  # answer Omarchy's first-boot wizard over VNC
emulator/60-desktop.sh USER PASS     # wait for the first-boot setup (15-50 min), boot straight into Hyprland
```

### Route H quick start

Concluded: on the device the in-app QEMU aborts at `tcg_region_init`. The steps document the
flow, which works in the route-F emulator:

```sh
device/sign-hap.sh                 # sign the route-F patched Aetherium with the device debug profile
device/push-inputs.sh              # push the HAP and the Omarchy qcow2 (big files: device/push-resumable.sh)
device/install.sh                  # bm install the signed HAP as root
```

HMV probes: `device/hmv/`, `device/hmv-permtest.sh`; VM-service probe: `native/vmtest/`,
`device/vmapi/probe-run.sh`.

### Route L quick start

See [docs/route-l-arkweb.md](docs/route-l-arkweb.md#reproduce).

## Layout

```
oseasy/              route B: Fold pipeline (10..60), probe/installer ISO (probe/), guest tools and
                     diagnostics (guest/), vmwgfx package (vmwgfx-7.2/), 120 Hz vote app (vote120/), runs/
driver/
  vmwgfx-oseasy-7.2/ vmwgfx for the HarmonyOS SVGA device on Linux 7.2 (MMIO, fence poll, GEM_CLOSE, retire delay, watchdog)
  vmwgfx-oseasy/     the same for Debian 6.1
  efidrm/            simpledrm on the EFI framebuffer for Debian 6.1
hongrong/            route C: Arch next to deepin (10, 20), initcpio subroot hook, configs
  pure/              developer image: build-disk.sh, make-qcow2.sh, os_type header, testvm.sh
  edid/              120 Hz EDID
  kernel/patches/    the two linux-aarch64 patches (ITS nvecs, hmv_idreg_quirk)
native/              route D: image, session (arch.sh), launcher (omarchy), Arch + Omarchy setup, install/reset
  desktop/           aquamarine/Hyprland patches, HongMeng shims, audio relay, session scripts
  app/               the display app (ArkTS + C++: ohdisp, gpu, audio, jl), vtest-inapp.patch, sign/
  vtest/             vtest-broker and the host-side virgl_test_server
  boot/              start at boot (not yet verified by a reboot)
  vm/                waypipe receiver for route C's desktop
  jloader/ xpmprobe/ route J loader and XPM probe apps
  vmtest/            route H probe for the VM service
tools/ownvm/         route I: ohmarchy-vm, disk prep, guest provisioning, dropuid, upstream virtiofsd build
tools/kaidashi/ kaidashi/runs/   route G
emulator/ tools/emu/ tools/vnc/ tools/serial/   route F
device/              route H (sign, push, install, hmv probes, vmapi) and route J (jprobe, jloader, userspace/)
webemu/              route L: image, page, HAP
linux-engine/        route A install scripts
tools/fold/ tools/ohdev/ tools/hongrong/ tools/kbuild/   device helpers, kernel builds and bisects
tests/               route D acceptance (run-all.sh), demo scripts (demo/)
docs/                every document, indexed by route: docs/README.md
```

## License

[MIT](LICENSE) for this repository's scripts, tools, app code and documentation.
Code derived from the Linux kernel is [GPL-2.0](LICENSES/GPL-2.0.txt): `driver/` (each
file keeps its SPDX identifier; upstream vmwgfx files are "GPL-2.0 OR MIT") and every
kernel patch here. Upstream projects that the scripts download or patch keep their own
licenses. Released disk images contain GPL software; their sources are published with
each release. Written offer: for three years after a release, the complete corresponding
source of any GPL or LGPL software in its images is available on request, at no more than
the cost of providing it; ask through this repository's issues.
