# Findings

Observations from bringing Omarchy to a HarmonyOS PC (MateBook Fold,
HarmonyOS 7.0). Each was observed on the device unless marked otherwise.

## HarmonyOS virtualization

- VMs run under the system's `vm_manager` with StratoVirt on the HarmonyOS
  hypervisor. A VM created through the private interfaces directly (no app) can
  boot and even render Omarchy's desktop, but it cannot show it: only a
  HarmonyOS app (UIAbility) can own a window, and the VM manager's caller
  checks exclude ordinary apps. That route ends at a serial console.
- Third-party VM apps such as Oseasy do get a window, so they are the way to
  run a whole OS with a visible screen.

## The Oseasy VM

- Machine: StratoVirt `virt`, GICv3, 6 vCPUs, 8 GB, UEFI with disk-first boot.
  Devices: virtio-blk (qcow2), xHCI with USB keyboard and tablet,
  virtio-multitouch, virtio-net, virtio-balloon, vhost-user-fs (tag
  `shared_dir`), an audio shared-memory device, virtio-serial ports for the
  vendor agent, and `svga-pci`.
- `svga-pci` is a VMware SVGA II device (`15ad:0405`) with a 16-byte **MMIO**
  BAR0 (registers), a 256 MiB VRAM BAR1 and a 2 MiB FIFO BAR2. Stock `vmwgfx`
  expects I/O ports and fails with "Unsupported SVGA ID 0xffffffff". With
  indexed MMIO (`driver/vmwgfx-oseasy`, `hvm_mmio=1`) it binds: SVGA 2, 3D,
  DX/SM4, guest-backed objects, screen object 2. It reports no screen targets,
  DEPTH 0 and BYTES_PER_LINE 0, and its preferred mode matches the window size.
- The UEFI GOP framebuffer lives in VRAM, and efifb works. Firmware, GRUB,
  Limine and the 6.1 kernel console are all visible.
- Once a guest driver enables SVGA mode, the window stops updating. Output
  through screen objects or the legacy display unit (with the depth fix) never
  appears. The host does set up a Vulkan swapchain at that point.
- The NIC is bridged to `172.16.100.1/24` on the HarmonyOS side, with no DHCP.
  The `hdc` shell can connect to the guest but cannot listen, and `hdc rport`
  binds 127.0.0.1 only.
- File sharing (virtiofs) is configured only for Windows guests with Oseasy's
  tools: `virtiofsd` runs without a shared directory. The serial console goes to
  a host log that the `hdc` shell cannot read.
- The app expects a Windows install. Its progress page times out with
  安装过程出现异常, and the VM keeps running. Closing the VM leads to
  安装失败 → 再次安装, which recreates the disk.

## Kernel

- Kernels >= 6.5 hang early in this VM (Omarchy's 7.2.3, a community report
  covering 6.5 and 6.12). Debian's 6.1.0-50 boots.
- Debian 6.1 arm64 has neither `CONFIG_SYSFB_SIMPLEFB` nor simpledrm, so the
  only KMS options are the SVGA driver or `driver/efidrm`.
- Omarchy's root on a foreign kernel needs that kernel's modules. Without them
  ufw fails halfway and leaves the INPUT policy at DROP. The initramfs overlay
  installs the 6.1 modules on first boot.
- busybox chooses the applet from its file name, so a copy named anything other
  than `busybox` fails with "applet not found".

## Host link

- A USB-C cable between the host laptop and the HarmonyOS machine keeps
  renegotiating power and alternate modes, which drops `hdc` every 10 to 45 s.
  A USB 2.0 data cable avoids that. Alternatively use wireless hdc:
  `hdc tmode port 5555`, then `hdc tconn <ip>:5555`. That needs a network
  without client isolation.

## Route A (Linux engine)

- The Linux engine container exposes the machine's GPU as "Virtio-GPU Venus".
  The third-party launcher's X11 bridge composites each app into its own
  HarmonyOS window. Terminal apps work well; a nested Hyprland session does
  not fit this model.
