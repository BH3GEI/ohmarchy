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

## Developer image

A ready-made Omarchy disk for the 鸿融 app: download one qcow2 file, import it
in 鸿融, start it. No root on the HarmonyOS PC, no deepin, no build step.

**Status (2026-10-25): imports through 鸿融 1.1.1.103's own UI and runs.**
(Checks below from 2026-10-24, 08:00–08:45 PDT, unless dated.) The image, booted as 鸿融's own VM (started from the 鸿融
UI, its bridge network and virtio-gpu), on a HUAWEI MateBook 14:

| Check | Result |
|---|---|
| Boot | linux-aarch64 7.2.12-1.1, 6 vCPUs, systemd `running`; warm reboot from the guest works |
| Desktop | SDDM → Hyprland (Omarchy 4.0.6) as `yao` on the 鸿融 screen |
| Network | 172.16.100.2 on 鸿融's bridge; `pacman -Sy` from the mirrors works |
| GPU | Mesa 26.2.5, `virgl (zink Vulkan 1.2 (Maleoon 916))`; glmark2-es2-wayland fullscreen: **596** |
| Display rate | 60 fps on screen (`hidumper -s RenderService -a "composer fps"`); with the 120 Hz EDID still 60 on screen, see 120 Hz below (2026-10-25) |
| Docker | 29.9.2, overlayfs, cgroup v2: `hello-world`, `postgres:16-alpine` (`pg_isready`), `docker compose` with nginx; through registry mirrors |
| Soak | 30 min, all 6 vCPUs busy (load 6.0): `running` throughout, no RCU stall, soft lockup, hung task or Oops |
| 120 Hz mode | with `hongrong/edid/omarchy-120.bin` (no preferred timing) Hyprland runs `Virtual-1` at 2160x1440@119.98; 鸿融 shows the fullscreen VM at 60 Hz (2026-10-25) |
| Import | 2026-10-25, 12:06 PDT: 本地文件 → `omarchy-dev-7.2.12-os1.qcow2` (9.6 GB) → 开始安装; imported, started by itself and at the SDDM login in under a minute |

**Why import failed before (fixed 2026-10-25).** "导入 qcow2" rejected every variant tried (zlib-compressed,
uncompressed 64 GiB, resized to 256 GiB, StratoVirt-shaped header) with
"镜像可能在传输过程中损坏" or "disk is damaged". The persisted hilog
(`/data/log/hilog/hilog.*.gz`, read with `zcat | strings`) shows the steps:

1. The app's own qcow2 check (`[IsoCheckModel]`): magic, version,
   cluster_bits, virtual size, and L1/L2/refcount tables and data clusters
   within the file. One earlier variant failed here
   ("qcow2 l1 table out of range: end 9007199254745088"); the image created
   directly at 256 GiB passes ("qcow2 validation passed").
2. SHA-256 of the whole file, then `ImportVmDiskImage` in vm_manager.
3. vm_manager `CheckBeforeImportVmDisk` runs
   `stratovirt-img get DISK os_type` and stops with
   "src disk img ostype invalid" when the type is 0. 鸿融's own disks return
   `os type: 1`; qemu-img images return 0.

os_type is the last byte (offset 255) of StratoVirt's 256-byte qcow2 v3
header. `stratovirt-img set DISK os_type=1`
(`/system/bin/virt_service/vm_engine/stratovirt/stratovirt-img`) changes only
that byte; [qcow2-stratovirt-header.py](../hongrong/pure/qcow2-stratovirt-header.py)
now writes it too, giving byte-identical headers. The snapshot in 鸿融's disks
(`snapshot_…`, VM size 0) is 鸿融's auto backup, made after import, and not
required. The os_type 1 image then imported (table above). Making it:
[hongrong/pure/make-qcow2.sh](../hongrong/pure/make-qcow2.sh) RAW OUT.

**120 Hz:** `hongrong/edid` makes an EDID with a 2160x1440@120 preferred mode;
with `drm.edid_firmware=Virtual-1:edid/omarchy-120.bin` the kernel reads it
(`/sys/class/drm/card0-Virtual-1/edid` equals the file) but keeps only the
60 Hz timing when the 120 Hz one is marked preferred: virtio-gpu's
`conn_mode_valid` deletes a preferred mode whose size differs from the host
scanout by more than 16 px (found by the Route I line, docs/vm-own.md).
`mkedid.py` now marks no timing preferred; then the probed modes are
2160x1440@120 and @60, and the active CRTC mode is the 120 Hz one.

On screen (2026-10-25, es2gears fullscreen in the guest, host composer rate
from `hidumper -s RenderService -a "composer fps"`): with the VM fullscreen
in 鸿融 the screen runs at **60 fps**. A 120 Hz vote window
(`com.ohmarchy.vote120`) only counts while it is visible, and bringing any
other window to the front makes 鸿融 leave the VM's fullscreen view for its
main page (composer then 120 fps, VM only in the small preview). So the guest
renders at 120 Hz but 鸿融 1.1.1.103 presents the VM at 60 Hz; this is on
鸿融's side.

### What is in it

- Arch Linux ARM and Omarchy 4.0.6 (Hyprland, SDDM), nothing else.
- `linux-aarch64` 7.2.12 with the 鸿融 patches
  ([hongrong/kernel](../hongrong/kernel)), booted with
  `arm64.hmv_idreg_quirk`; pacman owns the kernel, so `pacman -Syu` keeps
  working as long as the package keeps the patches (see the PKGBUILD).
- One partition layout: 512 MiB EFI system partition with GRUB at the
  removable-media path, ext4 root (64 GiB filesystem layout) in a qcow2 of
  256 GiB virtual size, about 9.6 GB to download.
- Built from scratch by [hongrong/pure/build-disk.sh](../hongrong/pure/build-disk.sh),
  then [make-qcow2.sh](../hongrong/pure/make-qcow2.sh). build-disk.sh now
  also installs the 120 Hz EDID (`drm.edid_firmware`) and `mesa-utils
  glmark2`; that version has not been built yet: the imported
  `omarchy-dev-7.2.12-os1.qcow2` got them by hand
  (`hongrong/edid/install-edid.sh`, `pacman -S mesa-utils glmark2`).

### Import

1. Copy `omarchy-dev-7.2.12-os1.qcow2` into the HarmonyOS file manager's
   Downloads folder.
2. In 鸿融: if a VM exists, it has to go first (1.1.1.103 holds exactly one
   VM; back up its disk if it matters): 更多 → 删除. Then 本地文件 → the
   qcow2 file → 打开 → 开始安装. The VM starts by itself when the import is
   done (under a minute for 9.6 GB).
3. Log in as `yao` (the password is given with the download, not here);
   change it with `passwd`.

### Network

Static address 172.16.100.2/24, gateway and DNS through 172.16.100.1 (鸿融's
bridge has no DHCP). `ssh yao@172.16.100.2` works from the HarmonyOS shell.

### Docker

```sh
sudo pacman -S docker docker-compose
sudo systemctl enable --now docker
```

Docker Hub is slow or unreachable from mainland China: add registry mirrors
in `/etc/docker/daemon.json` (for example `docker.m.daocloud.io`). The Docker
results in the table above come from a VM where both were installed this way;
build-disk.sh does not put Docker into the image.

### 鸿融 shows the running VM as 已关机

Seen on 2026-10-25 (PDT) every time the VM page was opened while the VM ran:
the card says 当前状态：已关机, IP is empty, 关机 and 暂停 are greyed out,
and 更多 offers only 强制关机. It happened after a dock tap back from the
fullscreen VM (right after the 12:06 import, no `aa start` involved) as well
as after `aa start -b com.huawei.medivh -a EntryAbility`.

Cause, from the persisted hilog (`vmStateChange callback, vmState: N`,
`HandleSetVmState`, `AGENT_INACTIVE`) and the strings in 鸿融's
`ets/modules.abc`: 鸿融 moves a VM to `STATE_RUNNING` (vmState 1) only when
its guest agent, the 虚拟机增强服务 (`vm-agent`), reports in. Every start of
this VM goes `STARTING` (3) → `VIEWING` (9) → `AGENT_INACTIVE`
("set isAgentInstalled as false") and stays at 9. The card's status text is
running only for `STATE_RUNNING` (paused for `STATE_PAUSED`) and falls back
to 已关机 for anything else, and the normal 关机 needs the agent. For
comparison, on 2026-10-23 a deepin VM with `vm-agent` (half) installed went
`VIEWING` → "isAgentInstalled change callback: true" → `RUNNING` (1), and its
关机 then sent `StopVm`.

Same behaviour under 鸿融 1.3.1.80 (2026-10-23 starts without the agent also
stop at 9) and 1.1.1.103, so it is not the version change. It is not caused by
how we bring 鸿融 to the front, and not by shutting down from the guest: a
guest `poweroff` is logged as `STOPPING` (4) → `STOPPED` (0), the same as
强制关机.

Repro: import or start any Linux guest without 鸿融's agent (Omarchy has
none; the agent's postinst handles only UOS and Kylin), let it reach the
login screen, open 鸿融's VM page.

Fix in progress: put the agent into the image.
[install-vm-agent.sh](../hongrong/pure/install-vm-agent.sh) takes the
`vm-agent` package from the installed 鸿融 (`entry.hap` →
`resources/rawfile/vm_tools_1.1.1.103.iso` → `虚拟机增强服务.deb`) and installs
only `/opt/vm-agent` (`agent_service`, glibc/aarch64, with its bundled
protobuf, abseil, cJSON and securec; everything else it needs is in Arch) and
its systemd unit. It leaves out the package's Mesa 19.2.6, dkms drivers and
desktop tools. build-disk.sh runs it when `VM_TOOLS` points at a copy of
`entry.hap`. The agent is a vsock server on guest port 3300 that 鸿融's
vm_manager connects to; that needs the ITS patch, which this kernel has.

Tested 2026-10-26 in `omarchy-dev-7.2.12-os1.qcow2` as 鸿融's VM, installing
from the CD 鸿融 attaches (`install-vm-agent.sh / /dev/sr1`; the guest sees
two USB CD drives `sr0`/`sr1` labelled 鸿融, `/dev/disk/by-label/鸿融` points
at `sr1`). On the agent's first connection 鸿融 powered the VM off and started
it again. After that the card showed 当前状态：运行中 with 关机 and 暂停
enabled, and 关机 shut the guest down through systemd; the card went back to
已关机 and 开机. What the agent changed in the guest:

- rewrote `/etc/systemd/logind.conf` (power key poweroff, suspend, hibernate
  and lid ignored) without a `[Login]` header, so logind ignores it;
  Omarchy's `logind.conf.d` drop-ins still apply;
- masked `suspend.target` and `hibernate.target`;
- added `enp0s6.nmconnection` with the host's settings (static
  172.16.100.2/24, gateway 172.16.100.1, DNS 114.114.114.114); after a reboot
  NetworkManager used it instead of `lan`, with the same address, and the
  network worked;
- mounted 鸿融's shared folder (virtiofs) at `/mnt/shared_dir`;
- tried to update itself with `dpkg`, which Arch does not have; harmless.

Workaround: shut the VM down from inside the guest (Omarchy: Super+Esc →
Shutdown, or `systemctl poweroff`); 鸿融 then shows 已关机 and the VM can be
started again with 开机. Use 更多 → 强制关机 only when the guest does not
respond, and run `sync` in the guest first if it is reachable. To get back
from the fullscreen VM to the VM page: tap 鸿融 in the dock if it shows; the
Home key and edge swipes did not leave the fullscreen VM, and from the host
`aa start -b com.huawei.medivh -a EntryAbility` does.

### Known limits

- 120 Hz: the guest runs at 2160x1440@119.98 with the EDID above, but 鸿融
  presents the fullscreen VM at 60 Hz.
- No guest agent: 鸿融 shows the running VM as 已关机 and greys out 关机
  (see above); shut down from inside the guest.
- One VM: 鸿融 1.1.1.103 holds one VM at a time.
- AppGallery updates 鸿融 on its own, and has replaced a newer sideloaded
  build with 1.1.1.103; turn off automatic updates for 鸿融 to keep a version.
- The kernel needs `arm64.hmv_idreg_quirk` until Huawei's hypervisor reads
  unknown ID registers as zero ([report](hmv-idreg-report.md)).
- Firefox's hardware WebRender crashes the host's GPU process and 鸿融 then
  stops the VM ([vendor report](hongrong-vendor-request.md)); the image sets
  software WebRender in `/etc/firefox/policies/policies.json`.

### AI agents

Claude Code, Codex and opencode are configured by `hongrong/pure/guest/setup-ai.sh`
for one OpenAI/Anthropic-compatible relay. In a public image the key is empty
and the first terminal says so: put your own key and base URL into
`~/.config/environment.d/ai.conf` (`ANTHROPIC_AUTH_TOKEN`, `ANTHROPIC_BASE_URL`
without a path; `OPENAI_API_KEY`, `OPENAI_BASE_URL` ending in `/v1`), the base
URL also into `~/.codex/config.toml` and `~/.config/opencode/opencode.json`,
then log in again; or run `setup-ai.sh ENV_FILE` with `OHM_AI_KEY`,
`OHM_AI_BASE` and `OHM_AI_BASE_V1` in ENV_FILE.

Internal disks (never a public one) get the relay ready to use:
`hongrong/pure/inject-ai-env.sh RAW.img ENV_FILE` writes ENV_FILE into a copy
of the disk as `~/.config/ohmarchy/ai.env` and enables the user unit
`ohmarchy-ai-import.service`, which runs `setup-ai.sh` with it at the next
login and deletes it. On ohdev the env file is `/data/local/secrets/ai.env`
(root, 600); the relay URL that the guest reaches is the public one.

A disk with the env files injected carries the key and the proxy's
credentials in plain text: it stays on the machine it was made for and is
never copied to another one. A disk to hand out has the mechanism only (the
units, `setup-ai.sh`, `vless2singbox.py`); each machine injects its own env
files when it is set up.

Recording a demo: Claude Code shows a server notice once per account, at the
first tool call, and the notice names the relay's host. Before recording, run
one prompt that calls a tool (for example `run ls`) in a session that is not
recorded, dismiss the notice, and start a new session; check every frame of
the recording for the host name (OCR) and record again if one frame shows it.

Pitfall: Omarchy's launchers in `~/.local/bin` (claude, codex, opencode) run
`mise use` at every start, which looks for a newer version online (npm,
GitHub). Behind a slow network that hung for minutes and the agents seemed not
to answer, although the relay answered in 4 s; mise's own downloads through
the proxy were cut off and left empty install directories. The demo disk
(`hongrong/pure/guest/demo-setup.sh agents`) installs the three agents with npm
from npmmirror instead (system Node.js, `--allow-scripts` for the native
binaries of claude and opencode), replacing the launchers; checked on
2026-10-29 in the 鸿融 guest: `claude --version` 0.02 s, `claude -p` 9 s, codex
10 s, opencode 8 s, and interactive `claude` opens at its prompt (first-run
screens pre-answered by setup-ai.sh). On the native desktop the launchers run
the installed version with `MISE_OFFLINE=1`. The same script sets mainland
mirrors for npm, rustup, Go, pip and mise's Node.js
(`~/.config/environment.d/50-mirrors.conf`, as route D).

### Proxy (internal disks)

Internal disks (never a public one) also get a proxy for sites that the
mainland network does not reach. `hongrong/pure/inject-proxy-env.sh RAW.img
ENV_FILE [DIRECT_FILE]` writes the proxy's VLESS URL (`PROXY_VLESS_URL`;
on ohdev `/data/local/secrets/proxy.env`) into a copy of the disk and enables
`ohmarchy-proxy-setup.service`: once sing-box is installed, it writes
`/etc/sing-box/config.json` with `hongrong/pure/guest/vless2singbox.py`,
deletes the env file and enables sing-box. The guest gets a tun device
(transparent for every program) and a mixed proxy on 127.0.0.1:7890; private
addresses, the mainland mirrors and the hosts in DIRECT_FILE (the AI relay's)
go direct, everything else through the server. `sudo systemctl stop
sing-box` goes back to direct. Checked on 2026-10-29: google, youtube and
github 200, the exit in the US, TUNA direct in 0.7 s; GitHub downloads through
the proxy ran at 40 KB/s, so VSCodium comes from TUNA's GitHub release mirror.

The native desktop shares the HarmonyOS host's network, whose routes must not
change: there `SINGBOX_TUN=0` leaves out the tun device and the auto-detected
interface (the HongMeng kernel gave "missing default interface"), and
`~/.config/environment.d/60-proxy.conf` points `http_proxy`, `https_proxy` and
`all_proxy` at 127.0.0.1:7890.

## Toward Omarchy's own kernel

Goal: boot Omarchy's `linux-aarch64` with a small, documented patch set on top,
instead of deepin's kernel, and hand the hypervisor-side problems to Huawei.

### Status

**7.2.12 pure-Omarchy disk: cold boot + 3 warm reboots pass** (2026-10-24).
Arch Linux ARM's `linux-aarch64` 7.2.12-1.1 with the two patches below,
installed as a package on a disk with Omarchy alone (no deepin), booted with
`arm64.hmv_idreg_quirk` in a 鸿融-style VM: every boot brings up six vCPUs and
reaches systemd `running`; see [Omarchy alone, without
deepin](#omarchy-alone-without-deepin) and the serial log
[logs/hongrong-pure-7.2.12-serial-20261024.log](logs/hongrong-pure-7.2.12-serial-20261024.log).
Earlier the same day, 7.2.11 (rebuilt with ALARM's config) reached the
Omarchy desktop in 鸿融 on the deepin-based disk, with virgl, vsock and the
network. Still to do on the pure disk: network, desktop on screen, a long run.

### What failed, and why

Every kernel from v6.9 on hung in early boot: the EFI stub exits boot services,
then nothing on screen, and the host never sees PSCI `CPU_ON` for vCPU 1. The
cause is HarmonyOS's hypervisor (HMV) hanging the vCPU on reads of ID
registers Linux started reading after v6.8, `ID_AA64PFR2_EL1` for certain:

- v6.9 reads `ID_AA64ISAR3_EL1`, `ID_AA64PFR2_EL1` and `ID_AA64FPFR0_EL1` in
  `__cpuinfo_store_cpu()` (bisected to merge `0c5ade742e91`, branch
  for-next/dpisa).
- v6.17 checks `ID_AA64PFR2_EL1.GCIE` for the GICv5 boot capability through a
  live read in `__read_sysreg_by_encoding()`; the guest log stops right after
  `CPU features: detected: GICv3 CPU interface`.

The report for Huawei, with the bisect, the register list and a reproduction,
is [hmv-idreg-report.md](hmv-idreg-report.md).

Debugging a guest that hangs before any output: the PL011 serial goes to
`/dev/null` and 鸿融 hides the EFI framebuffer, but guest RAM is the
`memfd:stratovirt_anon_mem` mappings of the StratoVirt process, so
`dd if=/proc/<pid>/mem ... | strings` on the host recovers the kernel log.

### Omarchy alone, without deepin

`hongrong/pure/build-disk.sh` builds a disk with nothing but Arch Linux ARM
and Omarchy: GPT with a 512 MiB ESP (a standalone GRUB at
`EFI/BOOT/BOOTAA64.EFI`, so no UEFI boot entry is needed) and an ext4 root,
`linux-aarch64` with the patches installed with pacman (its modules belong to
the package, so `linux-modules-cleanup` leaves them alone), Omarchy 4.0.6 via
`20-install-omarchy.sh`, and the kernel command line
`arm64.hmv_idreg_quirk console=tty0 console=ttyAMA0,115200`. It runs in the
Arch environment on the HarmonyOS host itself (see the script's comments for
what the HongMeng kernel needs: no devtmpfs, no pacman sandbox, a tmpfs /sys
with the VM's DMI for Omarchy's hardware steps).

Tested 2026-10-24 with `linux-aarch64` 7.2.12-1.1, in a VM started like 鸿融's
(`hongrong/pure/testvm.sh`: same StratoVirt binary, HMV acceleration, UEFI
firmware and virtio devices, serial console on a socket), with 鸿融's own VM
shut down:

| Boot | Kernel start | `systemctl is-system-running` |
|---|---|---|
| cold | 19:16:37 | running (19:18:35) |
| warm reboot 1 | 19:18:47 | running |
| warm reboot 2 | 19:20:57 | running |
| warm reboot 3 | 19:23:06 | running |

All six vCPUs come up every time; `poweroff` ends the VM. Not yet checked on
this disk: the network (鸿融 removes its bridge when its VM stops, so a VM
started by hand needs its own tap), the desktop on screen, and a long run.

Notes for running a VM outside 鸿融: root (SELinux domain `su`) can open
`/dev/hmv` and start StratoVirt directly; StratoVirt's QMP accepts one JSON
command per write; `-serial socket,path=...,server,nowait` gives a console to
log in through (`toybox nc -U`).

### Patches for `linux-aarch64`

- `hongrong/kernel/patches/0001-irqchip-gic-v3-its-Don-t-clamp-nvecs-to-zero-when-id_bits-is-32.patch`:
  upstream `5a9d62555e71` (mainline, Cc stable, not yet in 7.2.11). The
  host's ITS reports 32 event ID bits; without the fix MSI allocation fails,
  every device falls back to INTx, vsock is dead and the guest tools never
  connect. Drop it once Arch's kernel carries it.
- `hongrong/kernel/patches/0002-arm64-arm64.hmv_idreg_quirk-to-read-new-ID-registers-as-zero.patch`:
  with `arm64.hmv_idreg_quirk` on the command line, every ID register v6.8 did
  not read at boot reads as zero without being accessed (in `cpuinfo` and in
  `__read_sysreg_by_encoding()`), and MPAM is hidden. Without the parameter
  nothing changes. Drop it once HMV reads unknown ID registers as zero.

### Pitfall: deepin's modules disappear after booting Arch's kernel

Arch's `kernel-modules-hook` runs `linux-modules-cleanup.service` at every
boot: each `/usr/lib/modules/<version>` that is neither the running kernel nor
owned by a package is moved to `/usr/lib/modules/.old/` and deleted. deepin's
6.6 modules were copied in by hand, so the first boot of 7.2 removed them, and
the next boot of deepin's kernel stopped in systemd (no `nls_cp437`, the ESP
mount fails). While both kernels are in use, keep deepin's modules out of its
reach (`systemctl mask linux-modules-cleanup.service`), or move them back from
`.old/`.

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
- `tools/kbuild/alarm-build-native.sh`: ALARM's `linux-aarch64` `Image` (its
  tarball, stable patch, patches and config) with ours on top, built in the
  Arch environment on the HarmonyOS host (20 cores, about 7 minutes).
- `tools/kbuild/release-zero-build.sh`: upstream release `defconfig` Images
  with the new ID register reads zeroed, for release-level bisects.
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
