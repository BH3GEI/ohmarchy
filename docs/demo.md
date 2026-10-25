# Demo scripts

One section per line. Each step says where to click, what should appear, and
how long it takes. Coordinates are in `tools/ohdev/ohui shot` space (1440 px
wide) and come from screenshots of a HUAWEI MateBook 14 with 鸿融 1.1.1.103;
they shift when windows move, so take a screenshot first and adjust if needed.
Driving the demo remotely uses `tools/ohdev/ohui`; presenting by hand uses
the same clicks.

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
