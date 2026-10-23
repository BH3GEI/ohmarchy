# Route C: the whole Omarchy OS in the 鸿融 Linux VM

鸿融 (`com.huawei.medivh`) is Huawei's own Linux VM app for HarmonyOS PCs. Like
Oseasy it runs StratoVirt on the HarmonyOS hypervisor and shows the guest in a
native window, but it is built for Linux guests: it gives them a `virtio-gpu`
display that stock kernels drive. That is enough to put Omarchy's Hyprland
desktop on screen.

Omarchy runs as a second OS next to a deepin 25 guest: Arch Linux ARM lives in
a directory on deepin's data partition and boots deepin's kernel.

![Omarchy desktop in 鸿融, fastfetch in foot](img/hongrong-omarchy-fastfetch.jpg)

## Status

Verified on a MateBook 14 (HongMeng kernel 1.11.13.0), 鸿融 1.3.1.80:

- Omarchy 4.0.6 (stable channel packages, plus the quattro branch's aarch64
  package list) with Hyprland 0.56.2 boots to the SDDM greeter, logs in, and
  runs the desktop: Quickshell bar, notifications, foot, fastfetch.
- Kernel: deepin's 6.6.143-arm64-desktop-hwe. Root: `/arch` on deepin's data
  partition (ext4), mounted by an mkinitcpio hook.
- GRUB (deepin's) boots Arch by default; deepin stays one menu entry away.
- Network and ssh work from the HarmonyOS host.
- **GPU acceleration (OpenGL) through virgl.** After 鸿融 stops and starts the
  VM (the StratoVirt process is relaunched), the guest gets
  `vhost-user-gpu-pci,virgl=true`: the kernel reports
  `[drm] features: +virgl +edid -resource_blob -host_visible` and 2 capsets,
  and Hyprland's renderer is `virgl (zink Vulkan 1.2(Maleoon 916))`. The host
  renders with Mesa's zink on the machine's GPU. Reboots inside the guest keep
  whatever device the VM was started with. Check from ssh, without touching
  the screen:

  ```sh
  journalctl -k -b | grep -e virgl -e 'cap sets'
  grep -h 'Renderer:' /run/user/$(id -u)/hypr/*/hyprland.log
  ```

Open:

- **GPU limits.** OpenGL only: the host's virglrenderer has no Venus, so no
  Vulkan in the guest. No `resource_blob`/`host_visible`, so frames are copied.
  GLES 3.2 contexts fail and Hyprland falls back to GLES 3.0.
- The first boots after installing got the 2D `virtio-gpu-pci` and llvmpipe
  instead. What makes 鸿融 pick virgl is not pinned down yet (see
  [findings](findings.md#鸿融-linux-vm)). If the desktop turns slow again, run
  the check above and stop and start the VM from 鸿融.
- No Snapper/Limine snapshots (ext4 root, deepin's GRUB), and ufw is off: it
  fails to load its rules on deepin's kernel and would block sshd.
- The install scripts in `hongrong/` reassemble steps that were run by hand.
  They have not been run end to end on a fresh VM yet.

## Why deepin, and why its kernel

- Fedora 44 Workstation Live (aarch64) does not boot in 鸿融: after the
  firmware hands over, the VM's virtio devices are deactivated and never
  re-initialized, nothing reaches the network, and the USB controller (which
  carries the ISO) reports `BME is cleared`. The serial console goes to
  `/dev/null`, so the hang itself was not seen.
- deepin 25.2.0 community (arm64), from the TUNA mirror, boots, installs and
  runs its desktop on 6.6.143. That is a kernel >= 6.5, which hangs in Oseasy,
  so the two apps differ here (鸿融 uses its own `stratovirt-uefi-linux`
  firmware and virtio-gpu).
- 鸿融 recommends UOS V20 and KOS V10. Both need an account to download; deepin
  is UOS's community upstream and its guest tools treat it as UOS.

Borrowing a kernel known to boot avoids testing Arch Linux ARM's own
`linux-aarch64`, which may or may not boot here (not tried).

## Layout on the VM disk

```
vda2  /boot (deepin)  vmlinuz-6.6.143..., initramfs-deepinkernel.img (Arch's), grub/custom.cfg
vda5  data (deepin's /persistent, /home, /var)
      └── arch/       the Arch Linux ARM + Omarchy root
```

The kernel command line is `root=UUID=<vda5> subroot=arch rw`. The `subroot`
initcpio hook (`hongrong/initcpio/`) mounts the partition and bind-mounts
`/arch` as the new root.

## Install

### 1. Get the deepin ISO onto the HarmonyOS PC

deepin 25.2.0 community, arm64, 5,509,810,176 bytes, from the TUNA mirror:

```
https://mirrors.tuna.tsinghua.edu.cn/deepin-cd/25.2.0/arm64/deepin-desktop-community-25.2.0-arm64.iso
SHA256 7c5cb76cec53532313f2b1f435d477a651f9b5f7ca2435dfc12eb7be8d3340fe
```

鸿融's file picker shows the user's 下载 (Downloads) folder. From a root shell on
the HarmonyOS host that folder is
`/data/service/el2/100/hmdfs/account/files/Docs/Download/`, so the ISO can be
fetched in place (about 5 MB/s here):

```sh
cd /data/service/el2/100/hmdfs/account/files/Docs/Download
curl -L -C - -o deepin-desktop-community-25.2.0-arm64.iso \
  https://mirrors.tuna.tsinghua.edu.cn/deepin-cd/25.2.0/arm64/deepin-desktop-community-25.2.0-arm64.iso
sha256sum deepin-desktop-community-25.2.0-arm64.iso
```

`-C -` resumes after an interruption (the host rebooted once mid-download).

### 2. Create the VM in 鸿融

1. Open 鸿融. The first screen is 请选择虚拟机镜像来源: choose 本地文件 (从本地安装iso或导入qcow2镜像文件).
2. In the file picker (选择文件) open 下载, select the deepin ISO, 打开.
3. The 镜像文件 page shows the ISO and the warning that only UOS V20 and KOS
   V10 ARM are tested. Press 开始安装. There is no CPU, memory or disk choice
   here; the VM got 6 cores, 8 GB (3.8 GiB visible to the guest) and a 256 GB
   disk, adjustable later under 硬件设置.
4. In one run a window titled 铠大师 (a Windows-install wizard: 选择镜像 →
   配置环境 → 安装系统) opened instead. Close it and press 开始安装 again.
5. Allow 允许“鸿融”访问你的“下载”文件夹? → 允许. The VM window opens and boots
   the ISO; the first screen is a cursor on black for a few seconds, then the
   kernel and initramfs messages, then the installer.

### 3. Install deepin

1. The installer (欢迎安装deepin系统) opened at 准备安装 with a full-disk layout
   on `/dev/vda`: EFI, `/boot`, swap, root (`Roota`) and `_dde_data`
   (`/persistent`). That disk is the VM's own new qcow2. Press 开始安装; it
   unpacks the system and reboots by itself.
2. First boot: 创建用户 (user name, computer name, password twice), 下一步, then
   正在配置您的电脑, then the login screen.
3. 鸿融 shows a notification 增强服务安装引导 (系统检测到该服务尚未部署) offering
   its guest tools (虚拟机增强服务 on the 鸿融 CD in 计算机). Don't install them on
   deepin: the postinst only handles UOS and Kylin, fails halfway and leaves
   dpkg wanting a reinstall, which blocks apt. If that happened:
   `sudo dpkg --remove --force-remove-reinstreq vm-agent`.

The deepin dialogs can look greyed out while they load; clicks still work.

### 4. Network and ssh in deepin

Open the terminal (taskbar) in deepin. The bridge (`172.16.100.1/24`, NAT to
the host's network) has no DHCP, so give the NIC an address:

```sh
sudo nmcli con add type ethernet ifname enp0s6 con-name lan ipv4.method manual \
  ipv4.addresses 172.16.100.2/24 ipv4.gateway 172.16.100.1 ipv4.dns 223.5.5.5
sudo nmcli con up lan
sudo apt update && sudo apt install -y openssh-server git
sudo systemctl enable --now ssh
```

deepin's default profile has a Chinese name, which the VM's key injection
cannot type, hence a new profile. `apt update` comes first: the offline install
has no package lists.

On the machine you work from, reach the guest through the HarmonyOS host
(`ohdev` here). The host's sshd does not forward ports, so `ssh -J` fails;
`toybox nc` on the host does the job. deepin and Arch answer on the same
address with different host keys, so each gets its own `HostKeyAlias`:

```
Host ohvm
    HostName 172.16.100.2
    HostKeyAlias ohvm-deepin
    User <user>
    ProxyCommand ssh -o BatchMode=yes ohdev toybox nc %h %p

Host ohvm-arch
    HostName 172.16.100.2
    HostKeyAlias ohvm-arch
    User <user>
    ProxyCommand ssh -o BatchMode=yes ohdev toybox nc %h %p
```

Then log in once with the password and install a key:

```sh
ssh-copy-id -o PreferredAuthentications=password ohvm
ssh ohvm 'echo ok'
```

`10-bootstrap-arch.sh` copies `~/.ssh/authorized_keys` into Arch, so `ohvm-arch`
works with the same key after the reboot.

### 5. Arch Linux ARM next to deepin

```sh
ssh ohvm
git clone https://github.com/BH3GEI/ohmarchy && cd ohmarchy
sudo hongrong/10-bootstrap-arch.sh <user> <password>
sudo reboot
```

It extracts Arch Linux ARM into `/persistent/arch`, copies deepin's modules in,
builds the initramfs, sets up the user, sshd and the network, and adds the
default GRUB entry. After the reboot `ssh ohvm-arch` reaches Arch.

### 6. Omarchy

```sh
ssh ohvm-arch
sudo ~/hongrong/20-install-omarchy.sh <user>
sudo reboot
```

Then log in at the SDDM greeter in the 鸿融 window (password only).

To boot deepin once: `sudo grub-editenv /boot/grub/grubenv set next_entry=0`
from deepin, or mount vda2 from Arch and set it there.

## What differs from an ISO install

The scripts follow the ISO's order: repositories and keys, packages,
`omarchy-apply-system --install-user USER --first-install`, then
`omarchy-provision-user --force --first-install` as the user. Changes:

- **Repositories.** The stable `omarchy` package's `omarchy-apply-pacman`
  writes the x86 templates, so `hongrong/etc/pacman.conf` (the quattro branch's
  aarch64 template) is put back afterwards. Mirrors: TUNA for Arch Linux ARM,
  `pkgs.omarchy.cn` for `[omarchy]`. Omarchy's regional profile is x86-only,
  but the `.cn` host serves aarch64 packages too, about 30x faster than `.org`
  from mainland China here.
- **Packages.** `omarchy-base.packages` and `omarchy-aarch64.packages` from
  the quattro branch (pinned commit in the script): 678 packages, about 2 GB.
  All of them resolve on aarch64.
- **User.** The user existed before `omarchy-settings` filled `/etc/skel`, so
  the skeleton is copied in.
- **Snapper.** `install/config/snapper.sh` fails without btrfs/snapper; it runs
  with `OMARCHY_SNAPPER_CONFIGURE_TEST=1` instead.
- **Network.** `apply-system` retires systemd-networkd for NetworkManager, so
  the static address is a NetworkManager keyfile (`hongrong/etc/`).
- **Firewall.** ufw disabled (see Status).
- **SDDM.** Omarchy's greeter has only a password field and logs in
  `userModel.lastUser`. On a fresh install nobody has logged in through SDDM,
  the user name is empty and every login fails ("User not known to the
  underlying authentication module"). `/var/lib/sddm/state.conf` names the
  user.
- **Node.** `omarchy-provision-user --first-install` switches to the ISO
  context and looks for a bundled x64 Node tarball in `/opt/packages`. With
  `OMARCHY_SETUP_CONTEXT=provision-owner` it falls back to `mise` over the
  network (npmmirror).

## Toward Omarchy's own kernel

Goal: boot Omarchy's `linux-aarch64` with a small, documented patch set on top,
instead of deepin's kernel, and hand the hypervisor-side problems to Huawei.
In progress.

### What fails, and where

`linux-aarch64` 7.2.11 does not boot in 鸿融. GRUB loads it, the EFI stub exits
boot services (the host log shows the firmware deactivating the virtio
devices), and then nothing: no earlycon output even with `earlycon=efifb`, and
the host never sees PSCI `CPU_ON` for vCPU 1. A working kernel brings up the
other five vCPUs within 0.4 s of the hand-off, so the hang is on vCPU 0 in early
boot, before SMP. `arm64.nosme arm64.nogcs arm64.nopoe nokaslr` do not help.

Booting each kernel once without an initramfs and reading the host log
(`hrvm ktest`) gives:

| Kernel | Source | Secondary CPUs start |
|---|---|---|
| 6.1.176 | Debian | yes |
| 6.6.143 | deepin | yes |
| 6.8.0 | Ubuntu | yes |
| **v6.8** | upstream, `defconfig` | **yes** |
| **v6.9** | upstream, `defconfig` | **no** |
| 6.11.0 | Ubuntu, upstream `defconfig` | no |
| 6.12.111 | Debian | no |
| 7.2.11 | Arch Linux ARM | no |

So the regression is in v6.9 and does not depend on distribution configs.
v6.9 rewrote arm64's early boot (Ard Biesheuvel's series moving the early page
table and kernel mapping code from `head.S` into C under `arch/arm64/kernel/pi`,
plus LPA2). 41 commits between v6.8 and v6.9 touch those files; a path-limited
`git bisect` over them is running. The same 7.2 kernel boots under QEMU TCG
(route E), so the trigger is something HarmonyOS's hypervisor does differently.

### Patches for `linux-aarch64` so far

- `hongrong/kernel/patches/0001-irqchip-gic-v3-its-Don-t-clamp-nvecs-to-zero-when-id_bits-is-32.patch`:
  upstream `5a9d62555e71` (mainline, Cc stable, not yet in 7.2.11). The
  host's ITS reports 32 event ID bits; without the fix MSI allocation fails,
  every device falls back to INTx, vsock is dead and the guest tools never
  connect. Drop it once Arch's kernel carries it.

### Method and tools

- `tools/hongrong/hrvm`: `start` presses 开机 in 鸿融 (found in the UI tree, and
  only if no other window covers it), `stop` sends SIGTERM to the VM's
  StratoVirt process on the host, which 鸿融 shows as 已关机. The QMP socket
  cannot be connected to from a root shell, and a fully hung VM window keeps
  the keyboard (Home does nothing), so this is the remote power cycle.
  `ktest NAME` sets `ktest=NAME next_entry=arch-ktest` in deepin's grubenv from
  the running system, powers off, starts, and greps the host's
  `/data/log/hwf_service/vmlog` for `vCPU 1 is running`. A failed test lands
  back on the default entry at the next start.
- `tools/kbuild/kernel-build.sh`: upstream `defconfig` `Image` builds in a
  Debian arm64 container (an M3 Max builds one in about 8 to 12 minutes; the
  Image is gzipped for the trip through the host). The source is a blobless
  clone of the TUNA linux mirror on a case-sensitive Docker volume.
- `tools/kbuild/kbisect.sh`: build, upload, `hrvm ktest`, `git bisect good|bad`
  until git names the first bad commit.

## Driving it

- Host: an ssh server on the HarmonyOS host (`ohdev`). For screenshots and
  input it needs hdcd's access token; `tools/ohdev/ohui` runs every UI command
  through it. The deepin and Arch guests are reached through the host with
  `ProxyCommand ssh ohdev toybox nc %h %p` (the host's sshd does not forward
  ports, so `-J` fails).
- Input: `uitest uiInput keyEvent` reaches the VM, `inputText` does not.
  `ohui type` sends one key event per character; back to back the VM drops
  keys, so it waits 50 ms between them. Check focus first: key events go to
  whichever HarmonyOS window is in front.
- Hyprland in this Omarchy uses the Lua config, so `hyprctl dispatch` takes a
  Lua dispatcher, for example from ssh:

  ```sh
  export XDG_RUNTIME_DIR=/run/user/1000
  export HYPRLAND_INSTANCE_SIGNATURE=$(ls -t /run/user/1000/hypr | head -1)
  hyprctl dispatch 'hl.dsp.exec_cmd("xdg-terminal-exec bash -c \"fastfetch; exec bash\"")'
  ```
