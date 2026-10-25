# Demo scripts

One section per line. Each step says where to click, what should appear, and
how long it takes. Coordinates are in `tools/ohdev/ohui shot` space (1440 px
wide) and come from screenshots of a HUAWEI MateBook 14 with 鸿融 1.1.1.103;
they shift when windows move, so take a screenshot first and adjust if needed.
Driving the demo remotely uses `tools/ohdev/ohui`; presenting by hand uses
the same clicks.

## B: Omarchy in OSEasy

What it shows: Omarchy (Arch Linux ARM + Hyprland) installed from scratch into
the third-party OSEasy VM app (`com.oseasy1.ohvm` 3.1.1.7), cold-booting to the
Hyprland desktop with 3D acceleration (Mesa SVGA3D → host DXVK → Vulkan), running
es2gears and apps. It starts from *no VM*, because OSEasy forgets a non-Windows
VM once it is powered off (a known OSEasy limitation, not our bug).

Artifact: the published installer ISO with the 5 ms command-buffer fix and the
page-flip watchdog (driver commit [`61e5998`](https://github.com/BH3GEI/ohmarchy/commit/61e5998)).
Build it with `oseasy/probe/build.sh` using `PROBE_DEFAULT=4` (install mode is the
default boot entry); the ISO's embedded GRUB then reads `set default=4`. Copy it to
the device's `Download/oseasy-probe.iso`. The host-side disk image
(`omarchy-pure.img.zst`) and `waitpush.sh` must be in `/data/local/oseasy/` (the
installer pulls the disk over the VM network on tcp/5003).

Automated end to end by [`tests/demo/b.sh`](../tests/demo/b.sh); the manual clicks
below are the same flow.

### Before the demo (not shown, about 1 min)

- OSEasy installed, no VM present (or delete any existing one). 鸿融's VM off
  (`vm.lock` free; HMV runs one VM at a time).
- `Download/oseasy-probe.iso` is the watchdog build; `omarchy-pure.img.zst`,
  `push-disk.sh` and `waitpush.sh` are in `/data/local/oseasy/`.

### B1: create and install (about 2 min 30 s)

1. Open OSEasy; it shows "创建您的第一个虚拟机". Arm the disk push on the host:
   `wc -l < /data/log/hwf_service/vmlog > /data/local/oseasy/vmlog.s2;
   nohup sh /data/local/oseasy/waitpush.sh &`.
2. Click **立即创建** (1053,449). A dialog "检测到文件目录存在ISO" offers 导入 — it
   auto-picks the wrong Windows ISO, so click **取消** (735,419).
3. Click **点击选择 ISO** (1118,398). In the picker, click `oseasy-probe.iso`
   (460,320), then **打开** (1185,775). (The picker is a different app, so a plain
   tap, not the bundle-checked safetap.)
4. OSEasy flags it "镜像不符合要求 / 系统架构: 未知" — expected for a non-Windows ISO.
   Click **下一步** (1278,659) → **继续安装** (735,430) → **仍要安装** (735,430).
5. On the config page (name Windows 11, 6 cores / 8 GB / 256 GB), click
   **开始安装** (1278,659). The VM console opens; collapse the intro with
   **收起介绍** (720,738).
6. The VM boots the installer (GRUB default 4 = install), which pulls the disk over
   tcp/5003 and adds the `vmwgfx-oseasy` driver. Wait for `install: INSTALL_DONE`
   in the host's `/data/log/hwf_service/vmlog` — about **133 s** (unavoidable: a
   64 GiB raw write at ~750 MB/s plus mkinitcpio).

### B2: boot to the desktop (about 10 s)

7. Reboot the VM into the installed system (host-side, over the installer's telnet:
   `oseasy/… rb.sh`, a sysrq reboot). Omarchy's Hyprland desktop appears about
   **7 s** after the reset. `ssh ohvm-arch` reaches the guest.

### B3: show it working (about 1 min)

8. **es2gears** — in the guest: `guest-bench.sh gears` (or just launch
   `es2gears_wayland`). On the workstation run
   [`oseasy/measure-fps.sh`](../oseasy/measure-fps.sh): the VM's `dxvk-submit`
   flushes **120 frames/s**; the panel composes 60/s.
9. **Workspace switching** — `guest-bench.sh workspaces 10` while `measure-fps.sh`
   runs: still 60/s on screen, smooth.
10. **foot** — launch `foot`; the window appears in about **0.1 s**.
11. **chromium** — launch `chromium`; first window in about **0.8–1.2 s**.

Total, hands-on parts: about 1 min 30 s of clicks plus the 133 s install and 10 s
boot — roughly **4 minutes**.

## C: Omarchy in 鸿融

What it shows: Omarchy (Arch Linux ARM + Hyprland) running as 鸿融's own VM
on the HarmonyOS PC, on a linux-aarch64 7.2.12 kernel with the 鸿融 patches
(`arm64.hmv_idreg_quirk`), with virgl GPU acceleration.

Two versions. **C1** applies if the Developer image imports through 鸿融's UI
(the os_type 1 image, see [hongrong-whole-os.md](hongrong-whole-os.md#developer-image));
otherwise use **C2**, which needs nothing new.

Never written into any file, including this one: the VM login password. It
lives in an environment variable on the presenting machine only (`PW` below).

### Before the demo (not shown, about 20 min)

- Take `/data/local/vm.lock` and `/data/local/screen.lock`; nobody else runs
  VMs or touches the screen during the demo.
- Close or minimize other windows so 鸿融 is in front. Clear notifications.
- C1 only: 鸿融 1.1.1.103 holds one VM, so Yao's main VM has to go first. Back
  it up and verify sha256, delete it in 鸿融 (更多 → 删除), and have the Developer
  image `omarchy-dev-7.2.12-os1.qcow2` in the file manager's 下载 folder.
  After the demo, restore the main VM with `hrswap.sh restore-main IMGDIR BACKUPDIR`
  (see hongrong-whole-os.md).
- C2 only: the main VM shows 已关机 in 鸿融.

### C1: import the Developer image (about 6 min)

| # | Action | Expected | Time |
|---|---|---|---|
| 1 | Open 鸿融 from the dock (orange-yellow icon). | Empty VM page with 创建虚拟机. | 5 s |
| 2 | 创建虚拟机 → choose a local image. | The file picker (选择文件) opens on 个人 › 下载. | 10 s |
| 3 | Click `omarchy-dev-7.2.12-os1.qcow2` in the list, then 打开 (1185, 775). | 镜像文件 page shows the file name. | 10 s |
| 4 | 开始安装 (1137, 742). | "正在安装 Linux 系统，请稍候…" progress. 鸿融 hashes the file (about 20 s for 9.6 GB), then copies it. | about 1 min |
| 5 | The VM starts by itself after import (it did with the 鸿融-made image). If not: 开机 (836, 393). | Full-screen VM window, then the 增强服务 guide dialog; close it with 知道了 (719, 685). | 1–1.5 min to SDDM |
| 6 | Log in: click the password field, then `ohui type "$PW"` followed by a newline (or type by hand). | Hyprland desktop (Omarchy theme, top bar). | 10 s |
| 7 | GPU: open a terminal (Super+Return) and run `glmark2-es2-wayland --fullscreen`; or from the presenting machine over ssh: `hongrong/pure/guest/gfx.sh glmark2`. | Fullscreen glmark2 scenes; score at the end. Reference: **596**, renderer `virgl (zink Vulkan 1.2 (Maleoon 916))`. | about 2.5 min |
| 8 | 120 Hz: in the terminal, `hyprctl monitors` shows `2160x1440@120`. On the host, start the 120 Hz vote window: `aa start -b com.ohmarchy.vote120 -a EntryAbility --pi w 64 --pi h 32`, then read the on-screen rate with `hidumper -s RenderService -a "composer fps"`. | Mode line at 120 Hz. On-screen rate: to be filled in after this round's measurement. | 1 min |
| 9 | Optional: `uname -r` → `7.2.12-1.1-aarch64-ARCH`; `cat /proc/cmdline` shows `arm64.hmv_idreg_quirk`. | | 20 s |

Talking points: one qcow2 file, imported with 鸿融's own button; no root on
the host, no deepin. The kernel is Arch's own `linux-aarch64` with two small
patches. The import used to fail on a single header byte (os_type).

### C2: Yao's main VM (about 4 min)

This is the existing deepin + Arch disk; it boots Omarchy on deepin's
6.6.143 kernel, not on the patched 7.2.12, so it shows the desktop, not the
kernel work.

| # | Action | Expected | Time |
|---|---|---|---|
| 1 | Open 鸿融 from the dock. | VM page: Linux, 当前状态 已关机. | 5 s |
| 2 | 开机 (836, 393). | Full-screen VM window; 增强服务 guide dialog after about 1 min; 知道了 (719, 685). | 1–1.5 min |
| 3 | Omarchy login screen (lock icon and password field). Log in with uitest: click the field (737, 565), then `ohui type "$PW"` plus a newline. The password comes from the environment, never from a file. | Hyprland desktop. Checked 2026-10-26: no login loop, SDDM greeter on seat0. | 15 s |
| 4 | Hyprland: Super+Return for a terminal, tile a second one, show workspace switching (Super+1/2). | Tiled windows, Omarchy theme. | 1 min |
| 5 | One or two apps: a browser (Super+Shift+B) on a web page, and `fastfetch` in the terminal (kernel, Hyprland, GPU). | | 1 min |
| 6 | Shut down: Super+Esc → power off from Omarchy's menu, or 鸿融's own stop control. | 鸿融 shows 已关机. | 20 s |

Not yet rehearsed: the Super-key shortcuts through `ohui key` (keycodes are
checked in the rehearsal), and the import entry's exact click positions in
C1 steps 1–2.

## D: Omarchy natively on HarmonyOS

What it shows: Arch Linux ARM and Omarchy's Hyprland desktop running as
ordinary processes on the HongMeng kernel, with no VM. The desktop appears in
a HarmonyOS app window ("Omarchy (native)") at 120 Hz, drawn by the device's
GPU through virgl inside the app ([native-desktop.md](native-desktop.md)).

Automated, from the presenting machine, with a screenshot after every step
and the elapsed time: `tests/demo/d.sh` (screenshots in
`tests/results/demo-<time>/`; `tests/demo/d.sh clean` closes the demo's
windows afterwards). It needs the screen: `/data/local/screen.lock` free, or
held by the native-desktop line with `HOLD_LOCK=1`.

### Before the demo (not shown, about 1 min)

- ohdev has just booted and is unlocked; HarmonyOS's own desktop is in front.
  Take `/data/local/screen.lock` for the duration.
- For the Docker step (8): start route I's VM, **on the host as root**:
  `sh /data/local/kaidashi/bin/ohmarchy-vm start` (or `tests/demo/d.sh prep`).
  It takes `/data/local/vm.lock`, and the 鸿融 VM has to be shut down. Wait
  until `ohmarchy-vm status` shows a `dockerd:` version. Without the VM, `d.sh`
  skips step 8 and says so.

### Steps (under 2 min)

| # | Action | Expected | Time |
|---|---|---|---|
| 1 | On the host as root (`ssh ohdev`): `omarchy desktop start` (`/data/local/archtest/bin/omarchy`). Once the boot service (`native/boot/`) is verified by a reboot, this is already done at boot. | Returns after about 3 s; Hyprland and the GPU broker run, waiting for the app (`omarchy desktop status`). Nothing new on screen yet. | 3 s |
| 2 | Click "Omarchy (native)" in the HarmonyOS dock (or `aa start -a EntryAbility -b com.ohmarchy.display`). | A window that says what it waits for, then the Hyprland desktop: Omarchy wallpaper and top bar. Maximize it from the title bar. | 10 s |
| 3 | Super+Return, then type `fastfetch` and Enter. | A foot terminal, tiled; fastfetch shows Arch Linux ARM, the HongMeng kernel, Hyprland, the Omarchy theme. | 10 s |
| 4 | Super+2, Super+1, a few times. | Workspaces slide back and forth smoothly. Measured rate (HarmonyOS's compositor, `tests/perf/workspace.sh`): 119 fps, `d.sh` prints it in the step-4 screenshot name. | 10 s |
| 5 | Super+Shift+B. | Firefox opens on workspace 1, tiled next to the terminal. Open any page, e.g. omarchy.org. | 15 s |
| 6 | Super+Space (Omarchy menu), then Escape; Super+Shift+F. | The Omarchy menu; then Files (Nautilus) on the home directory. | 15 s |
| 7 | In the terminal: `docker run --rm hello-world`. | "Hello from Docker!": the container runs in route I's VM; the CLI here talks to it over ssh (context `ohmarchy`). The first run pulls the image. | 10 s |

About 75 s of actions plus talking. Talking points: no hypervisor for the
desktop itself, so it starts in about 8 s cold and idles at 0.5% CPU; the
HongMeng kernel runs Arch's own binaries; keyboard, mouse, sound and the
HarmonyOS IME pass through the app; Docker is the one thing that needs a
Linux kernel, so it borrows route I's small VM.

Afterwards: `tests/demo/d.sh clean` (or close the windows with Super+W), and
`sh /data/local/kaidashi/bin/ohmarchy-vm stop` on the host if the VM was
started for the demo. Release the screen lock.

Not yet rehearsed: the click on the dock icon (`d.sh` uses `aa start`), the
Super-key shortcuts through `ohui key` (`d.sh` starts the same commands
through Hyprland instead), and the timings above.

## I: Docker on the native desktop

What it shows: the native desktop (route D) runs on the HongMeng kernel, which
can't run containers, yet `docker` and `docker compose` work in its terminal.
The CLI talks to dockerd in route I's VM, a headless Omarchy under StratoVirt
(`ohmarchy-vm`, [vm-own.md](vm-own.md)). The VM shares the desktop user's home
at the same path, so bind mounts work as on any Linux, and the files
containers write are ordinary files of the desktop user (0644, not root's).

Automated, from the presenting machine, with PASS/FAIL lines and the startup
time: `tests/demo/i.sh` (it takes and releases vm.lock itself;
`DEMO_LENT_LOCK=1` when another session lent its lock).

### Before the demo (not shown, 1 min)

- `/data/local/vm.lock` is free or lent to you, the 鸿融 main VM is shut down
  (route I refuses to start next to another StratoVirt), and route D's
  desktop is open with a terminal.

### Steps (about 3 min)

| # | Action | Expected | Time |
|---|---|---|---|
| 1 | Start the VM, **on the host as root** (`ssh ohdev`): `sh /data/local/kaidashi/bin/ohmarchy-vm start`. D's terminal can't do this, see the note below. | `home share: virtiofsd pid …, uid 60000`, `started pid …`, `guest up after 5s`. | VM up in about 5 s; dockerd: filled in by the rehearsal (`i.sh` prints "dockerd answering N s after start") |
| 2 | In D's terminal: `docker run --rm hello-world` | "Hello from Docker!" (the first run pulls the image through the VM's registry mirrors). | a few s |
| 3 | In D's terminal, a compose service with a bind mount: `mkdir -p ~/demo-i/www && cd ~/demo-i`, then a `compose.yaml` with one `busybox` service: `ports: ["8080:8080"]`, `volumes: ["./www:/www"]`, `command: sh -c "echo hello-from-compose > /www/index.html; exec httpd -f -p 8080 -h /www"`. Then `docker compose up -d` and `curl http://172.16.100.2:8080/`. | `hello-from-compose`: the container wrote the page into `~/demo-i/www` on the desktop and serves it from there. | 10–20 s |
| 4 | `ls -l www/index.html` | `-rw-r--r-- 1 builder builder … index.html`: 0644 and the desktop user's, although the container wrote it as root. | 5 s |
| 5 | `docker compose down; cd; rm -rf ~/demo-i`, then on the host as root `sh /data/local/kaidashi/bin/ohmarchy-vm stop`. | `stopped`: the VM powered off from the inside; the lock, tap and routing rules are gone. | 10 s |

Talking points: Docker for a desktop whose kernel has no namespaces or
cgroups, at the cost of one small VM that idles at about 1.2 GiB host memory
(the balloon gives more back on demand). The home share runs as the desktop
user with no capabilities, so the VM can't reach anything else on the host.
Files keep normal modes since the switch to upstream virtiofsd 1.14.0 (with
HarmonyOS's own virtiofsd they were always 0660).

Note, starting from D's terminal: `ohmarchy-vm` needs root on the host (the
hypervisor, tap, routing, the share's bind mount), and D's terminal is the
unprivileged desktop user. So for now step 1 and the stop run on the host.
Doing them from D would need a small root helper on the host that accepts
only `start`, `stop`, `status` from the desktop user. That opens a way from
the desktop into host root, so it isn't built (supervisor, 2026-10-26: not
worth it for one command in a demo). If the VM should later start with the
desktop, build it like D's existing broker: SO_PEERCRED, accept uid 60000
only, and only the three fixed commands.
