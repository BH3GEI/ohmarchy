# Documents

Every file in `docs/`, grouped by the same route tree as the
[README](../README.md#the-routes-as-a-tree) ([中文](../README.zh-CN.md)). Documents
marked (中文) are written in Chinese.

- [report/index.html](report/index.html) (中文): status report (2026-10-26): routes, status,
  technical facts per route, the B public try-out. Single HTML page, open it in a browser.

## 1. VM apps, plug and play, no root（一、虚拟机 app 即插即用，不用 root）

### B: Oseasy

- [oseasy-whole-os.md](oseasy-whole-os.md): the route-B work log: the VMM and its devices, the
  `vmwgfx-oseasy` driver, the installer ISO, every run from the Fold to the MateBook 14.
- [oseasy-install.md](oseasy-install.md) (中文): install guide for ordinary users, file manager
  and Oseasy UI only, no root (draft).
- [oseasy-vendor-request.md](oseasy-vendor-request.md) (中文): what we ask the Oseasy vendor
  for to support Linux guests properly.
- [hongrong-vendor-request.md](hongrong-vendor-request.md) (中文): bug report for 鸿融: Firefox in
  the guest crashes the host's GPU process (zink calls vkCmdBindShadersEXT) and the VM is stopped.
- [vm-oseasy.md](vm-oseasy.md): short pointer page to oseasy-whole-os.md.

### C: 鸿融

- [hongrong-whole-os.md](hongrong-whole-os.md): Omarchy as a 鸿融 VM: deepin-hosted main VM,
  the pure developer image, the os_type import fix, 120 Hz EDID, guest agent.
- [internal/hongrong-team-brief.md](internal/hongrong-team-brief.md) (中文): technical brief and
  requests for the 鸿融 team.
- [logs/hongrong-pure-7.2.12-serial-20261024.log](logs/hongrong-pure-7.2.12-serial-20261024.log):
  serial log of the developer image booting the 7.2.12 kernel.

### G: 铠大师

- [vm-kaidashi.md](vm-kaidashi.md): Omarchy's disk in 铠大师 and why every VM stays an
  install session (concluded).

## 2. Native on the HongMeng kernel（二、原生：直接跑在鸿蒙内核上）

### D: native desktop

- [native-chroot.md](native-chroot.md): Arch Linux ARM and Omarchy in a chroot on the HongMeng
  kernel; the full table of HongMeng quirks.
- [native-desktop.md](native-desktop.md): the Hyprland desktop shown by a HarmonyOS app: GPU
  path, 120 Hz, sound, input, keyboard shortcuts.
- [native-compat.md](native-compat.md): app by app, what opens and works on the native desktop.
- Acceptance tests and results: [acceptance.md](acceptance.md) (under Cross-cutting).

### I: own background VM

- [vm-own.md](vm-own.md): our own StratoVirt VM on `/dev/hmv` as D's Docker back end.

### J: native inside an app sandbox

- The J work log is [no-root-routes.md](no-root-routes.md) (under Cross-cutting).

## 3. Other explorations（三、其它探索）

- **A** [linux-engine-apps.md](linux-engine-apps.md): Omarchy's neovim setup and CLI tools in
  HarmonyOS's Linux engine.
- **F** [emulator-aetherium.md](emulator-aetherium.md): Aetherium (QEMU in a HAP) on the
  DevEco emulator, no hardware needed.
- **H** [device-aetherium.md](device-aetherium.md): the same app on the device; TCG cannot get
  executable memory; `/dev/hmv` probing (concluded).
- **K**: no document; see the README.
- **L** [route-l-arkweb.md](route-l-arkweb.md): v86 with Arch Linux 32 in an ArkWeb page
  (paused).
- **E**: not started; no document.

## Cross-cutting（通用）

- [findings.md](findings.md): what was tried and why other paths fail.
- [acceptance.md](acceptance.md): what "usable" means for the native desktop (D), how each part
  is tested, latest results, and what needs someone on site.
- [no-root-routes.md](no-root-routes.md): the no-root question for J and L: what a plain HAP may
  run (XPM probe), the busybox loader, and the stage-by-stage Hyprland build for OHOS musl.
- [vm-api.md](vm-api.md): whether a third-party app can create VMs without root (it cannot:
  `MANAGE_VM` plus a hardcoded allowlist).
- [hmv-idreg-report.md](hmv-idreg-report.md) (中文): report to Huawei on the vCPU hang when a
  guest reads newer ID registers.
- [demo.md](demo.md): demo scripts for D, I, C and B, with click coordinates and timings.
- [demo-operator.md](demo-operator.md) / [demo-operator.zh-CN.md](demo-operator.zh-CN.md):
  operator manual for the person driving the demo by hand (draft).
- [img/](img/): screenshots and photos referenced by the documents.
