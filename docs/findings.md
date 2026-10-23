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

## 鸿融 Linux VM

Observed on a MateBook 14 (HongMeng kernel 1.11.13.0), 鸿融 1.3.1.80.

- Machine: StratoVirt `virt`, GICv3, `accel=hmv`, 6 vCPUs, UEFI from
  `/system/opt/virt_service/virtualized_hwf/stratovirt-uefi-linux`. Devices:
  virtio-blk (qcow2), the install ISO as USB storage on xHCI, a second ISO with
  the guest tools, USB keyboard and tablet, `virtio-gpu-pci` (2D, EDID),
  virtio-net, virtio-sound, vhost-vsock, vhost-user-fs (the host's Documents
  folder), virtio-serial ports for the agent, balloon. The serial console goes
  to `/dev/null`.
- The NIC is on a bridge at `172.16.100.1/24` with NAT (`MASQUERADE`) to the
  host's network and no DHCP. A static address in the guest works.
- deepin 25 (6.6.143) boots and runs its desktop; Fedora 44 aarch64 hangs after
  the firmware hands over (details in [hongrong-whole-os.md](hongrong-whole-os.md)).
- Guest display, first boots: `virtio-gpu-pci` (2D); `virtio_gpu` reports
  `-virgl +edid -resource_blob -host_visible`, `+context_init`, 0 capsets, and
  Mesa falls back to llvmpipe.
- Guest display after 鸿融 restarted the VM (new StratoVirt process):
  `-device vhost-user-gpu-pci,...,xres=2160,yres=1440,virgl=true` on a
  `com.huawei.medivh/uds/gpu.sock` chardev, plus `-display ohui`. The guest
  reports `+virgl`, 2 capsets, and Hyprland renders on
  `virgl (zink Vulkan 1.2(Maleoon 916))`. It stayed that way across a forced
  stop and start. The VM's `config/*.json` were not modified, and the host's
  `libvm_manager.z.so`, `vhost-device-gpu` and `libvirglrenderer.so.1` are the
  stock images, so 鸿融 itself chose virgl; what decides between 2D and virgl
  is still open.
- The virgl backend: `/system/bin/virt_service/vm_engine/stratovirt/vhost-device-gpu`
  (rust-vmm vhost-device-gpu 0.2.0, `--gpu-mode virglrenderer --use-gles false`,
  user hwf_service, capsets virgl/virgl2). It maps an OpenHarmony port of
  virglrenderer, libepoxy, Mesa 25.0.1's EGL and gallium (zink) and the
  Maleoon Vulkan driver (`vulkan.hvgr_v210.so`, `/dev/hvgr0`), and presents
  through a native window from `libhwf_kits.z.so`. No Venus, so no Vulkan for
  the guest; StratoVirt logs `dmabuf not support now`, so no blob resources.
- In `libvm_manager.z.so`, `GetOHDisplayVmCmd` builds
  `vhost-user-gpu-pci,...,virgl=true` when a VM's `accelerationEnabled` is set
  and its guest type is Linux (the same flag gives Windows guests `svga-pci`
  with DXVK), and `VmManager::SetDisplay2dForUos`, called from `CreateVm`,
  clears that flag for Linux guests. Found by disassembly. The VM above runs
  with virgl anyway, so that path does not apply on every start.
- Guest tools (`vm-agent` 1.3.1.80, on the second ISO): agent services, a Mesa
  19.2.6 build, and dkms sources for virtio input/sound/fs and a logging
  device. The Kylin tree's `virtio_gpu` is upstream Linux 5.4 plus one stable
  fix; nothing hypervisor-specific, and it does not build on 6.6. The postinst
  recognizes only UOS and Kylin.
- Input: `uitest uiInput keyEvent` and clicks reach the guest; `inputText` does
  not.

## Kernel

- Kernels >= 6.5 hang early in the Oseasy VM (Omarchy's 7.2.3, a community report
  covering 6.5 and 6.12). Debian's 6.1.0-50 boots.
- Debian 6.1 arm64 has neither `CONFIG_SYSFB_SIMPLEFB` nor simpledrm, so the
  only KMS options are the SVGA driver or `driver/efidrm`.
- Omarchy's root on a foreign kernel needs that kernel's modules. Without them
  ufw fails halfway and leaves the INPUT policy at DROP. The initramfs overlay
  installs the 6.1 modules on first boot.
- busybox chooses the applet from its file name, so a copy named anything other
  than `busybox` fails with "applet not found".

## HongMeng kernel (route D)

Observed on a Kirin X90 HarmonyOS PC, HongMeng kernel 1.11.13.0, from a root
shell on the host. Details and workarounds: [native-chroot.md](native-chroot.md).

- An unmodified Arch Linux ARM userland runs on the HongMeng kernel in a
  chroot. Working: threads, futexes, epoll, eventfd, timerfd, signalfd,
  inotify, memfd with sealing, io_uring, ptrace (gdb, strace), large sparse
  mmaps, pseudo-terminals, sockets. Page size 4K. `uname` reports the HongMeng
  kernel; glibc does not mind.
- Namespaces: ipc, mnt, net, pid, time, uts. No user or cgroup namespaces, and
  cgroup v1 only, so systemd cannot be pid 1. No Landlock, so pacman needs
  `DisableSandbox`.
- No `/dev/dri` and no `/dev/kvm`. Hyprland (aquamarine) finds no allocator;
  sway runs on its headless backend with pixman. So route D is the native-speed
  CLI and development environment, and route C is the desktop. Wayland apps
  from route D reach route C's Hyprland through waypipe over the VM bridge
  (the host connects out to the guest; CPU rendering on the host).
- `splice()` from a drained pipe whose writers are gone into another pipe
  fails with EPIPE instead of returning 0. coreutils 9.12 `cat` hits this on
  every `cat > file <<EOF` and exits 1.
- Loop devices: only `loop0` has a node under `/dev` (all are in `/dev/block`),
  toybox `mount -o loop` fails with EFAULT, and a loop stays bound when the
  mount namespace that mounted it is torn down.
- `/data` is hmfs, `nosuid,nodev`, `errors=panic`. tmpfs labels its files
  `u:object_r:tmpfs:s0`, and ext4 refuses to take that label over on `mv`.
- Binding a device node onto a file fails; `mknod -m` is masked by umask;
  devpts has no `ptmx` and no `newinstance`.
- `prctl(PR_SET_KEEPCAPS)` is not permitted, so `setpriv` fails; coreutils
  `chroot --userspec` works.
- There is no user namespace, so uids inside are host uids. HarmonyOS uses most
  uids below 10000 for its services (1000 `system`, 1001 `radio`, ...).
- The built-in terminal (`com.huawei.hmos.hishell`) runs as an app uid and the
  system has no `su`. A setuid `/system/bin/sudo` exists (sudoers under
  `/data/service/el1/public/sudo_config/`); not tried.
- GitHub is not reachable from the host's network here; TUNA, gitee,
  `pkgs.omarchy.cn` and keys.openpgp.org are.
- Possible building blocks for a native display bridge, not exercised: the
  host has no Venus or vtest server (its virglrenderer is built without
  Venus); `/dev/system_heap2` is a mode-666 dma-heap; root's SELinux `su`
  domain is permissive, and `normal_hap_attr` (ordinary apps) may `connectto`
  unix sockets of the `su` domain.

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

## Route E (DevEco emulator + Aetherium)

Observed in DevEco Studio 26.0's emulator (HarmonyOS 7.0.0.107, 2in1) on an
Apple Silicon Mac.

- The emulator CLI (`Emulator -install`) refuses image downloads with
  "Currently, this capability is available only in the Chinese mainland." It
  decides from DevEco's local `options/country.region.xml` before making any
  request; with `CN` there, the download itself goes to
  `devecostudio-drcn.deveco.dbankcloud.com` and needs a CN egress
  (`-http_proxy` works).
- Inside the emulator: `hdc shell` is uid `shell`, `hdc smode` fails
  ("undebuggable version"), no `/dev/kvm` or hypervisor nodes. The emulator does
  not expose EL2, so only TCG VMs run. Unsigned HAPs install.
- Aetherium's test HAP (`test-14456eb6…`) needs three fixes before QEMU starts
  and shows a screen: the unconditional `-tpmdev emulator` (its QEMU lacks the
  built-in TPM), a 2 MiB firmware for a 64 MiB pflash, and the virtio-gpu MMIO
  mapping. See docs/emulator-aetherium.md.
- QEMU's `virt` machine creates legacy virtio-mmio transports by default.
  virtio-blk, -net and -rng work on them, virtio-gpu does not: the guest leaves
  the device at status `0x83` (ACK|DRIVER|FAILED) with `virtio_gpu` loaded and no
  `/dev/dri/card0`. `virtio-gpu-pci` works.
- With `virtio-gpu-pci`, Omarchy's own 7.2.3 kernel, Limine and Plymouth run
  unmodified; the first-boot wizard appears on tty1.
- Omarchy's root account is locked and the owner is created by the tty1
  wizard. Before that, `systemd.debug_shell=ttyAMA0`, appended in Limine's
  editor over the serial console, is the way in.
- The emulator's only IME (Celia Keyboard) asks for an agreement whenever a text
  field is focused, and its pinyin mode turns `uitest inputText` letters into a
  candidate; Enter commits the raw letters. VNC key events into the guest avoid
  the IME entirely.
