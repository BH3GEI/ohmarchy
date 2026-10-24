# Route G: the whole Omarchy OS in the 铠大师 VM

[铠大师](https://kaidashi.helplook.com) (`com.sanway.ecoengine`, vendor
sanway.tech / 晟为数科) is a Windows-on-ARM VM app for HarmonyOS PCs, sold on
AppGallery since the HarmonyOS PC launch in May 2025. This route tries to run
Omarchy's own disk (UEFI + GRUB, linux-aarch64 7.2 with the HMV ID-register
quirk) in it, and to compare it with 鸿融 (route C) and the native desktop
(route D).

## Status

Survey done (read-only), on ohdev (MateBook 14 `HM740-001`, HarmonyOS
`7.0.0.115`, HongMeng kernel 1.11.13.0), 2026-10-24:

- 铠大师 3.5.8.14 is installed but has never created a VM on this machine (no
  `vm_manager` directory for it, no StratoVirt start in the logs).
- It drives the same system VM service as Oseasy (`@hms:virtService.vmManager`),
  so `vm_manager` builds the StratoVirt command line; the app chooses only
  parameters (CPU, memory, disk, firmware vars, Secure Boot keys,
  `accelerationEnabled`).
- It only accepts a Windows 11 24H2+ ARM64 ISO, checked from the WIM metadata
  (below). No override button in the strings, unlike Oseasy.
- One VM at a time, system-wide (`Not support vm multi-instance`,
  虚拟机启动失败，已有虚拟机在运行中).

- **The ISO check is beaten**: a Debian 12 netboot ISO with a 2.5 KB fake
  `sources/install.wim` (`tools/kaidashi/make-fake-wim.sh`) is accepted as
  安装版本 WINDOWS 11 PRO, 2026-10-24 16:07.
- The wizard (选择镜像 → 配置环境 → 安装系统) offers only name, CPU (6),
  memory (8 GB) and disk size (256 GB default), plus 自动创建D盘分区 and a
  desktop card. No display, firmware or Secure Boot options. No login was asked
  for up to the 开始安装 button (not pressed yet: it creates the VM).

Next: press 开始安装 during a `vm.lock` slot (鸿融's VM has to be off: one VM at
a time), record the StratoVirt command line, and boot the probe entry to read
the devices, Secure Boot state and EDID from the serial log.

## The app

| | |
|---|---|
| Bundle | `com.sanway.ecoengine` 3.5.8.14 (versionCode 3050814), vendor `sanway.tech`, `appDistributionType: app_gallery`, `installSource: pre-installed`, SDK 6.0.2.130, target API 60002022 |
| HAP | 472 MB, md5 `5271455c1ec9e6875df1fb071f398706`; 441 MB of it is `resources/rawfile/server.iso` (the Windows guest tools, 铠大师 "WOA server") |
| Installed | `/data/app/el1/bundle/public/com.sanway.ecoengine/entry.hap`, 2026-10-23 09:10 |
| Native code | `libentry.so` (NAPI: `extractWim`, `genIsoFile`), `7z.so`/`lib7z_.so` (7-Zip), `libgenisoimage.so`; no VMM of its own |
| Abilities | `VMConsoleAbility` (main), `VirtualAbility` (VM window), `InstallVmAbility`, `BridgeAbility`, `ReleaseServerAbility`, a form card |
| Permissions | internet, microphone, camera, pasteboard, Download/Documents, `ACCESS_USER_FULL_DISK`, `KEEP_BACKGROUND_RUNNING`, print, `PRIVACY_WINDOW`; none for virtualization |
| Licensing | account login (SMS / WeChat QR), membership and payment (`/appstore/payment`, `checkTpmChangedNoVipStartVm`, 会员) |

`ets/modules.abc` (ArkTS bytecode, ark 12.0.6.0) is protected: `ark_disasm`
from DevEco 26.0.0.105 and from SDK 6.1 both abort with "checksum mismatch",
and with the checksum fixed, "Invalid file offset, from method:
GetSpanFromId". The findings below come from its strings and from the
resource index.

Versions of the other VM apps at the same time (AppGallery auto-updates them):
鸿融 `com.huawei.medivh` 1.1.1.103, Oseasy `com.oseasy1.ohvm` 3.1.1.7.

## The VMM

Nothing in the app starts a VMM. It calls the system kit
`@hms:virtService.vmManager` (`createVm`, `startVm`, `stopVm`, `destroyVm`,
`createSnapshot`, `setVmNetMode`, `addSharedFolder`, `getGraphicDevice`,
`checkVmCapability`, …) with `cpuNum`, `memSize`, `diskSize`, `biosPath`,
`dbContent`/`dbxContent` and `accelerationEnabled`. The system `vm_manager`
(uid `hwf_service`) turns that into a StratoVirt process with `accel=hmv` on
`/dev/hmv`, the same engine 鸿融 and Oseasy use.

`/system/lib64/libvm_manager.z.so` has three display choices:

| Device | Used for |
|---|---|
| `svga-pci,id=svga,bus=pcie.0,addr=0x4.0x0[,xres=1600,yres=1200]` | Windows guests (Oseasy's VM); backend is StratoVirt's `devices/src/display/svga/processor_dx/*`, SVGA3D/VGPU10 on D3D11 through DXVK on Vulkan |
| `virtio-gpu-pci,...,xres=2160,yres=1440,enable_bar0=false[,edid=true]` | Linux guests, 2D |
| `vhost-user-gpu-pci` + `vhost-device-gpu --gpu-mode virglrenderer` | Linux guests with acceleration (鸿融's VM now) |

all with `-display ohui`. 铠大师 only creates Windows guests, so it should get
`svga-pci` like Oseasy; to be confirmed from the command line once a VM exists.

Bundled Secure Boot keys (`resources/rawfile/securityBoot/`), all Microsoft:
PK "Windows OEM Devices PK", KEK "Microsoft Corporation KEK 2K CA 2023",
db "Windows UEFI CA 2023", "Microsoft Corporation UEFI CA 2011",
"Microsoft Windows Production PCA 2011", "Microsoft UEFI CA 2023", dbx
"Microsoft Windows Production PCA 2011". If they are enrolled with Secure Boot
on, an unsigned GRUB will not start; shim (signed by the 2011 UEFI CA) would.

## Image intake

- Source: download (from sanway's server) or a local ISO in a public directory
  (当前不支持从应用目录安装，请选择本地公共目录镜像文件), no spaces in the path.
- Check (`CheckISOVersion.ts`, `checkIsoWorker.ets`, `extractwim.cpp`): 7-Zip
  pulls `sources/install.wim` out of the ISO, then the app reads the WIM's XML
  metadata (UTF-16LE, `XmlPullParser`) and looks at `ARCH` (must be `12`,
  ARM64), `MAJOR`/`MINOR`/`BUILD`/`SPBUILD` (`10.0.26100`, 24H2), and the
  name (`WINDOWS 11`). Failure: 镜像校验失败！当前仅支持Windows 11 24H2及以上的ARM64系统镜像安装。
- It notices a changed image afterwards (镜像被修改，请重新选择镜像！).
- No signature or checksum of the ISO in the strings. The app writes its own
  `autounattend` (arm64 components, `<RefreshRate>60</RefreshRate>`) and guest
  tools ISO with genisoimage; the install ISO is attached as `Windows_install.iso`.
- Result with the probe ISO (`tools/kaidashi/probe-iso/build.sh`, Debian
  `mini.iso` + fake WIM + Joliet names, volume id `CCCOMA_A64FRE_ZH-CN_DV9`):
  accepted. The ISO has to be in a public folder (下载) to show up in the picker.

  ![ISO check passed](img/kaidashi/iso-check-passed.jpeg)
  ![Wizard step 3](img/kaidashi/wizard-step3.jpeg)

- There is no qcow2 import in the UI (unlike Oseasy): only 镜像数据导出 and
  backup/restore of 铠大师's own VM. Importing a `.qcow2` is only for 铠大师's own exports (with a password,
  `InputPwdForQcow2`).

## Probe ISO

`tools/kaidashi/probe-iso/build.sh WORKDIR` remasters Debian 12's arm64 netboot
`mini.iso` (Microsoft-signed shim, Debian-signed GRUB and 6.1 kernel, so it
starts with or without Secure Boot) with xorriso: the fake `install.wim`, a GRUB
menu and `probe.cpio.gz`. The default entry boots with `rdinit=/probe.sh
console=tty0 console=ttyAMA0`; `probe.sh` prints PCI IDs and BARs, the EFI
`SecureBoot`/`SetupMode` variables, ACPI tables, framebuffer and DRM modes,
EDID and dmesg as `KDSPROBE` lines, then opens a shell on tty1. StratoVirt sends
the guest serial port to the hwf_service log (`RedirectToLog`), which root can
read in `/data/log/hwf_service/vmlog`. Other entries: the Debian rescue
installer and `fwsetup`.

## Sources

- [铠大师 help centre](https://kaidashi.helplook.com) (from the app's `config.json`); vendor site [sanway.tech](https://www.sanway.tech), app backend `https://harmony.sanway.tech`
- [Xinhua: 铠大师虚拟机 on AppGallery with the HarmonyOS PC, 2025-05-20](https://www.news.cn/tech/20250520/b808f567fee140b5b7746be18bd1e842/c.html)
- [Toutiao: 铠大师 at the HarmonyOS PC sales start](https://www.toutiao.com/zixun/7546784896979732543/)
- [CSDN: 铠大师 install walkthrough (needs the official Windows 11 ISO)](https://gitcode.csdn.net/6aa0e30f1a35784c8420a73c.html)
- Route B findings on the same machine: [oseasy-whole-os.md](oseasy-whole-os.md#matebook-14-ohdev-2026-10-24)
- HMV ID-register quirk: [hmv-idreg-report.md](hmv-idreg-report.md)

Scripts: [`tools/kaidashi/probe.sh`](../tools/kaidashi/probe.sh) (read-only, on
the device), [`tools/kaidashi/hap-survey.sh`](../tools/kaidashi/hap-survey.sh)
(static, on a host).

## Commits

(each push is listed here)
