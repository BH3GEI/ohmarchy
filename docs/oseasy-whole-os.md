# Route B: the whole Omarchy OS in the Oseasy VM

[Oseasy虚拟机](https://appgallery.huawei.com/) (`com.oseasy1.ohvm`, AppGallery) is a
Windows-on-ARM VM app for HarmonyOS PCs. It runs StratoVirt on the HarmonyOS
hypervisor and shows the guest in a native window. It accepts any ISO after two
warnings, so it can run a complete Omarchy AArch64 install.

## Status

Verified on a MateBook Fold, HarmonyOS 7.0.0.111, Oseasy 3.1.0:

- The Omarchy disk image installs from a remastered Debian installer ISO.
- The Limine menu shows in the VM window and boots the 6.1 entries.
- Debian's 6.1 kernel boots Omarchy's root (systemd, NetworkManager, SDDM). The
  console is visible on the EFI framebuffer, and the network root shell works in
  the initramfs and in the running system.
- Omarchy's own 7.x kernel hangs early in this VM, as did every kernel >= 6.5
  tried here and in a community report. Use 6.1.

Open:

- **Desktop display.** With only the EFI framebuffer there is no DRM device, so
  SDDM's Hyprland greeter cannot start. The SVGA driver
  (`driver/vmwgfx-oseasy`) binds the Oseasy SVGA device with 3D, DX/SM4 and
  guest-backed objects, but once it enables SVGA mode Oseasy stops refreshing
  the window. Neither screen-object nor legacy-mode output reaches it. Next
  candidates: 3D surface presents through the SVGA path, and the
  `omarchy_gpu=efidrm` entry (KMS on the EFI framebuffer, software rendering).
- The pipeline in `oseasy/` reproduces the manually verified steps from public
  inputs (Omarchy release image, Debian packages). A full end-to-end run on the
  Fold with a fresh image is still pending: the first-boot module install and
  the tty1 first-boot wizard on a fresh image have not been exercised yet.

## Build

See the quick start in the [README](../README.md). The result is
`work/omarchy-install.iso`: the Debian 12 arm64 netinst ISO plus
`omarchy.raw.gz` (the Omarchy disk with the 6.1 boot entries in its ESP),
`omarchy-write.sh` and `write-esp.sh`.

Boot entries written to the ESP (`oseasy/limine.conf.in`):

| Entry | Kernel command line extra | Purpose |
|---|---|---|
| EFI framebuffer | (none) | default: console on efifb, Omarchy userspace |
| hold in initramfs | `omarchy_hold=1` | stops before the root mount for debugging; `touch /run/omarchy/go` continues |
| efidrm KMS | `omarchy_gpu=efidrm` | experimental: `omarchy_efidrm` provides card0 on the EFI framebuffer |
| SVGA 3D driver | `omarchy_gpu=svga` | experimental: `vmwgfx` with `hvm_mmio=1 hvm_display=2` |
| stock 7.x kernel | | Omarchy's own UKI, kept for reference (hangs) |

## Install in Oseasy

1. Push the ISO: `oseasy/60-push-iso.sh` copies it to the Download folder (下载).
2. Open Oseasy虚拟机 → 立即创建 → **点击选择 ISO** → pick `omarchy-install.iso`
   in 下载 → it reports 镜像不符合要求 (系统架构: 未知) → 下一步 →
   **继续安装** → **仍要安装** → keep the default 6 cores / 8 GB / 128 GB →
   开始安装 (a low-battery prompt may appear; charge the machine).
3. The VM opens on the installer's GRUB. Choose *Advanced options → Rescue
   mode*, then: English → United States → American English → network
   autoconfiguration fails, so Continue → *Do not configure the network at this
   time* → hostname Enter → time zone Enter → "No partitions found" Continue →
   *Execute a shell in the installer environment* → Continue.
4. In the shell: `sh /cdrom/omarchy-write.sh` (writes the disk, about 6 to 8
   minutes), then `sync; reboot -f`. The VM boots its disk before the installer
   media, so it now comes up in the Limine menu.
5. Oseasy's main window waits for a Windows install and later reports
   安装过程出现异常. Press 确定; the VM keeps running.

Typing into the VM from the host: `tools/fold/type.sh 'command'` (keep
commands short and without single quotes), `tools/fold/key.sh 2054` (Enter),
`tools/fold/shot.sh name` (screenshot).

## First boot

Pick **EFI framebuffer**. The initramfs:

- gives the VM NIC `172.16.100.2/24` (the HarmonyOS side of the bridge is
  `172.16.100.1`; there is no DHCP) and serves a root shell on tcp/5000;
- installs Debian's 6.1 modules into Omarchy's root from the ESP
  (`/ohmarchy/modules-<kver>.tar.gz`), since the root only carries modules for
  Omarchy's own kernel;
- blacklists autoloading of `vmwgfx` (its probe takes the framebuffer and then
  fails on this device), keeps NetworkManager off the VM NIC, allows the bridge
  subnet in ufw, and installs `omarchy-netremote.service` for the running
  system.

Omarchy's first-boot wizard (owner account, keyboard, hostname, time zone) runs
on tty1 before SDDM; answer it with the keyboard in the VM window.

## Network shell

From the host: `tools/fold/guest.sh 'uname -a; ip -br addr'`. The HarmonyOS
shell may open outgoing TCP connections (`netcat`) but not listening sockets,
so the guest always listens:

| Port | Service |
|---|---|
| 5000 | root shell (busybox `tcpsvd`) |
| 5001 | upload: first line is the destination path, then the bytes |
| 5002/5003 | one-shot transfers used by `tools/fold/guest-put.sh` and `guest-get.sh` |

## Reinstall or reset

- Closing the VM window asks 创建尚未完成，确定退出 → 确定 → 安装失败 →
  **再次安装** recreates the disk and boots the ISO again. This wipes the
  Omarchy disk.
- `write-esp.sh` rewrites only the ESP from the ISO and keeps the root
  filesystem. It needs the installer booted again.
- To reset the app completely: `hdc shell bm clean -n com.oseasy1.ohvm -d`.

## MateBook 14 (ohdev), 2026-10-24

Second device: HUAWEI MateBook 14 `HM740-001`, HarmonyOS `7.0.0.115`
(OpenHarmony 7.0.0.120), HongMeng kernel 1.11.13.0. Survey script:
[`oseasy/probe.sh`](../oseasy/probe.sh) (read-only).

### What Oseasy is

- `com.oseasy1.ohvm` **3.1.1.7** (versionCode 3110007), vendor 武汉噢易云计算股份有限公司,
  `appDistributionType: app_gallery`, `installSource: pre-installed`, compiled
  with SDK 6.1.1.125. The HAP is 290 MB, of which 227 MB is
  `resources/rawfile/oetool.iso` (the Windows guest tools). Native code is only
  `libentry.so`/`libcommon.so`; the app does not run a VMM itself.
- It asks for no virtualization permission of its own. The VM is described to
  the system `@ohos.virtualization` kit (strings in `ets/modules.abc`:
  `cpuNum memorySize diskSize biosPath graphicDevice xres yres
  accelerationEnabled storageDevice networkDevice …`,
  `virtualization.on('vmMemoryChange')`), and `vm_manager` (uid `hwf_service`)
  starts StratoVirt for it. Its VM lives next to 鸿融's under
  `/data/service/el0/virt_service/100/vm_manager/<appid>/com.oseasy1.ohvm/img/`
  (`vm.qcow2` + `stratovirt-vars`); here the app id is `68eaa5b5` and the disk
  holds a Windows 11 install from 2026-10-23.
- Image intake (resource strings): a Windows 11 ARM ISO (download from Microsoft
  or local file), **or an imported `.qcow2`** (导入虚拟机镜像 / 自动查找 .qcow2 镜像,
  with the warning 请您确保当前qcow2文件是ARM架构Windows虚拟机文件). Nothing in
  the strings points at a signature or checksum on the image; the ISO check is
  an architecture probe (`iso_validate_result`, 系统架构: 未知 on the Fold) that
  can be overridden. Licensing: a one-time trial per device, then purchase
  (每台终端仅1次试用机会).
- The app also carries a small agent client for Linux guests: it connects to
  `tcp://172.16.100.2` and speaks a length/tag framed protocol with the commands
  `heartbeat shutdown reboot stop-linux stopvm-async install_complete
  auth_confirm` (`initLinuxSupport` / `removeLinuxSupport`).

### The VMM

Oseasy's last start (`/data/log/hwf_service/vmlog4`, 2026-10-23 09:38, pid 15337):

- `stratovirt` (`/system/bin/virt_service/vm_engine/stratovirt/stratovirt`),
  `hypervisor: Hmv` (it holds `/dev/hmv`, `crw-rw---- root:hwf_service 10,232`,
  like 鸿融's StratoVirt), 6 vCPUs, 8 GB, `mem_share`.
- Firmware: `/system/opt/virt_service/virtualized_hwf/stratovirt-uefi` (鸿融's
  Linux VM uses `stratovirt-uefi-linux`), vars in the app's `img/`.
- Disks: `vm.qcow2` on virtio-blk (io_uring, discard), the install ISO and
  `oetool.iso` as USB storage on xHCI.
- Display: `svga-pci` plus `-display ohui`. Its backend is
  `devices/src/display/svga/processor_dx/*`: SVGA3D guest-backed surfaces,
  VGPU10 (DX10/SM4) command and DXBC shader parsing, executed on D3D11 through
  DXVK on Vulkan (`stratovirt_d3d11.log`: `D3D_FEATURE_LEVEL_11_1`, presenter
  `VK_PRESENT_MODE_MAILBOX_KHR`, 5 images), plus a DXVA2 video decoder. The guest
  surface follows the host window (`HostWindowInfoEvent 2100x1511` →
  `update surface size`). 鸿融 gives Linux guests virgl (`vhost-device-gpu`,
  zink on Maleoon) instead.
- Other devices: USB keyboard and tablet, virtio-multitouch, virtio-net (tap,
  2 queues), `ivshmem-scream` audio, virtio-serial ports for the vendor agent,
  vhost-user-fs, balloon, pvpanic, a log device. The serial console is
  `RedirectToLog`.
- In this log only Oseasy's VM runs (鸿融's VMs were created later the same
  day), so whether both apps can run at once is not answered yet.

Sources: [Oseasy launch coverage, mydrivers](https://news.mydrivers.com/1/1048/1048600.htm),
[unwire.hk hands-on (ISO install)](https://unwire.hk/2025/05/12/harmonyos-windows11/notebook/),
[ithome](https://www.ithome.com/0/940/942.htm).
