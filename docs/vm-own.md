# Route I: our own Omarchy VM on the HarmonyOS hypervisor

Goal: Omarchy in a VM that we start ourselves with the system's StratoVirt on
`/dev/hmv` (root on the host, no VM app), with its real 7.2 kernel, Docker,
GPU 3D through virgl, and a 120 Hz picture in route D's HarmonyOS display app.

Done when: Hyprland reaches the desktop with at least 110 frames/s on screen,
glmark2 scores, `docker run hello-world` and a compose file run, the network
works, a cold boot plus three warm reboots and a 1 h soak pass; otherwise the
layer that stops it, with evidence.

Split (supervisor, 2026-10-24): this document's VM itself and its start-up
(route I main line, the 铠大师 line's session); "Remote virgl" (GL from a VM to
a renderer in our app) and the app side are agent-53's (route D), and the two
meet where the picture goes into route D's app.

## Status

Offline preparation, 2026-10-24:

- Base: agent-2a's `hongrong/pure/testvm.sh` (headless StratoVirt on HMV with
  鸿融's UEFI, virtio-blk/net, vsock, tap + NAT) and its verified
  `omarchy-pure.img` (linux-aarch64 7.2.12-1.1, cold boot + 3 warm reboots).
- The GPU part to add is 鸿融's own (below).
- 120 Hz: agent-2a's EDID (`hongrong/edid/omarchy-120.bin`: 2160×1440 at
  119.983 Hz first, 59.955 Hz second, no preferred timing since e9d1672; see
  "Why 120 Hz was dropped"), copied to the disk as `ohmarchy-120.bin`, loaded with
  `drm.edid_firmware=Virtual-1:edid/ohmarchy-120.bin`
  (`CONFIG_DRM_LOAD_EDID_FIRMWARE=y` in 7.2.12). The test boot also has
  `drm.debug=0x7`.
- Docker prerequisites are in the 7.2.12 config: overlayfs, bridge, veth,
  NAT/MASQUERADE, addrtype match (modules), cgroups and memcg (built in).

## 鸿融's GPU and display, for reference

From 鸿融's last `VmConfig` in `/data/log/hwf_service/vmlog*` (VM `3a373868`):

```
-chardev socket,id=vhost-user-gpu,path=…/vm_manager/<appid>/com.huawei.medivh/uds/gpu.sock
-device vhost-user-gpu-pci,id=vhost-user-gpu-id,bus=pcie.0,addr=0x4.0x0,xres=2160,yres=1440,chardev=vhost-user-gpu,virgl=true
-display ohui,iothread=ohui-iothread  (sock_path …/hwf_service/<appid>/com.huawei.medivh/uds, ui_path /dev/shm/hwf)
```

with the backend started by vm_manager as
`vhost-device-gpu --socket-path …/uds/gpu.sock --gpu-mode virglrenderer --use-gles false`
(rust-vmm vhost-device-gpu; options: `--capset virgl,virgl2`, `--use-egl`,
`--use-gles`, `--use-surfaceless`). Its EDID comes from the backend (60 Hz);
StratoVirt's `vhost-user-gpu-pci` has no EDID option of its own.

## Remote virgl: a VM's GPU work rendered and shown by route D's display app

Goal: keep a real Linux kernel in a VM (鸿融's, or one of our own), and show its
desktop through route D's display app at 120 Hz, without root in the VM's path.
Route D already has the pieces: the app runs the renderer (virglrenderer's vtest
on the Maleoon GPU) and presents Hyprland's frames straight into its window when
Hyprland signals one (a blit into a 7x3 marker texture, seen in the command stream).

How a VM reaches it (code in place since `dc01445`, off by default, not yet run):

- In the VM, Mesa's virpipe speaks vtest to a Unix socket (`VTEST_SOCKET_NAME`,
  default `/tmp/.virgl_test`); `socat UNIX-LISTEN:/tmp/.virgl_test,fork
  TCP:172.16.100.1:PORT` carries it to the host.
- On the host, `vtest-broker --tcp 172.16.100.1:PORT` (set
  `OHMARCHY_VTEST_TCP=172.16.100.1:PORT` for `omarchy desktop start`) accepts it,
  only from 172.16.100.0/24 (`--tcp-allow`), and hands the connection to the
  display app over `@ohmarchy-vtest` like a local one. The app itself never opens
  a network socket, so the app sandbox's network rules do not matter.
- The app's vtest sees a TCP socket and negotiates protocol version 0: versions 2
  and 3 send resources as shared-memory fds, which cannot cross TCP; version 0
  copies transfers through the socket (`TRANSFER_GET`/`PUT` with the data). Such a
  client gets a plain context, exempt from the multi-client mode's version-3 rule.
  Local clients keep version 3 and shm: the 120 Hz path is unchanged.
- Presenting does not depend on the protocol version: the marker blit is a draw
  command.

What it costs: every texture upload and read-back crosses TCP as a copy (a full
1920x1280 frame is 9.8 MB); draw commands are small. A compositor that only
composites (its clients rendering on the GPU too, through the same path) mostly
sends commands; CPU-rendered clients (wl_shm) upload their damage each frame.

What the VM's desktop needs, for the app to show it at 120 Hz: route D's patched
Hyprland (headless output, present marker) instead of its normal DRM one, with
`GALLIUM_DRIVER=virpipe`; the VM's Arch has the same Hyprland 0.56.2 and
aquamarine 0.15.1 as route D's session, so `/opt/ohmarchy` from it can be used.
Input (design, not built): the app sends input over `@ohmarchy-display`, the
socket the patched aquamarine listens on; 16-byte packets (pointer, button, axis,
key) from the app, frame headers back. On the in-app GPU path the app does not use
the exported frames (the renderer has the window), so the frame headers' dmabuf
fds, which cannot cross TCP, can be dropped. A plain byte relay is enough:

- in the guest, `socat TCP-LISTEN:7791,bind=172.16.100.2,fork
  ABSTRACT-CONNECT:ohmarchy-display` next to the patched Hyprland;
- on the host, a relay like `ohmarchy-audio-relay` that serves an abstract socket
  only to the display app's uid and connects to the guest's port;
- the app takes the socket name to connect to from a setting instead of the fixed
  `ohmarchy-display` (route D's own desktop keeps that name).

What the first VM test measures, and what not: es2gears in the guest's normal
session with `GALLIUM_DRIVER=virpipe` renders on the host through this path, but
its frames go back to the guest (copied over TCP) and its own Hyprland shows them
in 鸿融's window at 60 Hz. That checks the transport and its cost; the 120 Hz
picture in route D's app needs the patched Hyprland in the guest.

To measure (needs the screen and a running VM): es2gears and glmark2 in the VM
through this path; frame rate on screen (HarmonyOS compositor), CPU on both
sides, and latency. A first check without a VM is possible from route D's own
session (it shares the host's network: a client there connecting to
172.16.100.1 comes from the allowed network).

## Where the virgl picture goes (offline, 2026-10-24)

- `vhost-device-gpu` links only `libvirglrenderer.so.1` (the system's, 588 KB).
  That virglrenderer is patched for OpenHarmony: `virgl_renderer_ohos_set_scanout`
  / `virgl_renderer_ohos_present` render a scanout into an EGL window surface
  and `eglSwapBuffers` it ("scanout %d surface created at %dx%d", a 1 s black
  buffer on resize). It gets the window by `dlopen("libhwf_kits.z.so")` and
  `dlsym("GetNativeWindow")` (plus `ReleaseNativeWindow`,
  `OH_NativeWindow_NativeWindowHandleOpt`).
- `libhwf_kits.z.so`'s `GetNativeWindow(id)` is
  `OHOS::HmosWindowsFusion::WindowsClient::GetNativeWindow(unsigned)` from
  `libhwf_agent.z.so`: it asks the system's WindowsFusion service for the window
  of the VM view that the VM app (鸿融) created ("stratovirt get nativewindow").
- So a VM we start as root renders on the GPU through the same backend, but
  there is no VM view to present into. Two ways to put the picture into route
  D's app, both to agree with agent-53:
  1. a substitute `libhwf_kits.z.so` (found first through
     `TESTVM_GPU_LIBPATH`) whose `GetNativeWindow` returns a native window made
     from the surface of route D's XComponent (shared by surface id), leaving
     vhost-device-gpu and virglrenderer untouched;
  2. route D's side serves vhost-user-gpu itself.
- Refresh: the EGL swap paces with that window's consumer; route D's app
  already asks the panel for 120 Hz.

`hongrong/pure/testvm.sh` (shared with agent-2a) now takes `TESTVM_GPU=1`
(vhost-device-gpu + `vhost-user-gpu-pci,virgl=true`), `TESTVM_GPU_LIBPATH`,
`TESTVM_DISPLAY=ohui`, and gives the NIC 鸿融's rx/tx iothreads, the likely
fix for "the guest sends but never receives" seen both in that script and in
铠大师's install session ([vm-kaidashi.md](vm-kaidashi.md)).

## Disk (offline, 2026-10-24)

`tools/ownvm/prep-disk.sh` makes `/data/local/kaidashi/ownvm/omarchy-own.img`:
a sparse copy of agent-2a's `omarchy-pure.img` (sha256 `d2c7150e…`, 64 GiB,
9.0 GiB of data; the source is only read), then edits its root with
`debugfs -w` because the host cannot mount it (HongMeng's ext4 driver:
"has unsupported incompat features(22c2)"). Added: `/boot/ohmarchy-edid.cpio`
(the EDID as an extra initrd, so the initramfs needs no rebuild), the EDID in
`/usr/lib/firmware/edid/`, an `/etc/mkinitcpio.conf.d/ohmarchy-edid.conf`
for later rebuilds, and in both GRUB entries
`drm.edid_firmware=Virtual-1:edid/ohmarchy-120.bin` plus the extra initrd.
`e2fsck -fn` is clean. Docker goes in from inside the running guest.

## Option A test tool

`tools/ownvm/swtest.c` (NDK build, runs as root on the host): creates a native
window from route D's app's XComponent surface id
(`OH_NativeWindow_CreateNativeWindowFromSurfaceId`) and flushes CPU-filled
buffers into it; if pictures appear, a substitute `libhwf_kits.z.so` can hand
that window to vhost-device-gpu. Needs the app open (screen.lock).

Result (2026-10-24 08:22 PDT, run by the native-desktop line with route D's
app open in GPU mode): surface id `8216272437645` from hilog
("xcomponent surface id"); as root, `swtest 8216272437645 5` →
`CreateNativeWindowFromSurfaceId = 40001000, window 0`. The surface-id table is
per process, so another process (root included) cannot get a window for the
app's surface. **Option A is closed**, and with it `hwf_kits_remote.c`. Still
open: option B (the app itself becomes the vhost-user-gpu backend) and the
vtest channel (above; the guest's TCP connection reaches the app, which drops it
at the start, being debugged on the native-desktop line). Guest side of vtest
needs `LIBGL_ALWAYS_SOFTWARE=1 GALLIUM_DRIVER=virpipe`, else Mesa takes the
DRM device's driver.

## Why 120 Hz was dropped (offline, 2026-10-24)

In 鸿融 (253ec06) the kernel read agent-2a's EDID but kept only its 59.955 Hz
timing. The EDID is valid (checksum, range 59–121 Hz, max clock 430 MHz ≥
424.5 MHz). What drops the mode is virtio-gpu's `mode_valid`
([virtgpu_display.c](https://github.com/torvalds/linux/blob/master/drivers/gpu/drm/virtio/virtgpu_display.c)):

```c
if (!(mode->type & DRM_MODE_TYPE_PREFERRED))
        return MODE_OK;
if (mode->hdisplay == XRES_DEF && mode->vdisplay == YRES_DEF)
        return MODE_OK;
if (mode->hdisplay <= width  && mode->hdisplay >= width - 16 &&
    mode->vdisplay <= height && mode->vdisplay >= height - 16)
        return MODE_OK;
DRM_DEBUG("del mode: %dx%d\n", mode->hdisplay, mode->vdisplay);
return MODE_BAD;
```

`width`/`height` are the host's scanout size from GET_DISPLAY_INFO. Only the
*preferred* mode is checked, and
[drm_edid.c](https://github.com/torvalds/linux/blob/master/drivers/gpu/drm/drm_edid.c)
`add_detailed_modes` marks the first detailed timing preferred when an EDID 1.3
has feature bit 0x02 (the file has features `0x0a`). The 120 Hz timing is the
first one, so whenever the host scanout is not 2144–2160 × 1424–1440 (a
different window size, or 0×0 while the output is disabled) it is deleted and
the second, non-preferred 59.955 Hz timing survives, which matches 鸿融's
59.955 Hz exactly.

Fix without a kernel change: clear bit 0x02 (features `0x08`; agent-2a's
`mkedid.py` does this by default since e9d1672, `--preferred` sets it). No mode is preferred, every mode passes, and `drm_mode_sort`
([drm_modes.c](https://github.com/torvalds/linux/blob/master/drivers/gpu/drm/drm_modes.c))
orders same-size modes by refresh, so 119.983 Hz comes first. Confirmed in 鸿融 by agent-2a (08:50 PDT, real app VM, vhost-user-gpu virgl,
7.2.12, `drm.debug=0x5`): with the no-preferred EDID both timings survive,
`Probed mode: 2160x1440: 120 424500 2160 2208 2240 2320 1440 1443 1453 1525`
first, and the active CRTC (`debugfs dri/0/state`, SDDM's Hyprland) is
`"2160x1440": 120`. On-screen fps of the 鸿融 window is not measured yet.
`output 0: WxH+0+0` (the host size) and `del mode:` are in the DRIVER
category, so they need `drm.debug` with 0x2 (0x7 on route I's disk); `/sys/class/drm/card0-Virtual-1/modes` lists names only, so
the refresh is read with `modetest -c` or `hyprctl monitors`.

### Remote virgl: what the trials showed (2026-10-24 23:20-23:47)

1. Transport works. 鸿融's guest (agent-2a's Omarchy image, Mesa 26.2.5) reached
   the broker over TCP (`TCP client 172.16.100.2 queued`), and the broker handed the
   connection on. In the guest, virpipe needs `LIBGL_ALWAYS_SOFTWARE=1
   GALLIUM_DRIVER=virpipe VTEST_SOCKET_NAME=...`: with a DRM device Mesa picks the
   hardware driver and ignores `GALLIUM_DRIVER`. From the host or route D's
   session, a connection to 172.16.100.1 leaves with the Wi-Fi address as source
   (policy routing), so the allow-list refuses it; local tests use
   `OHMARCHY_VTEST_TCP=127.0.0.1:PORT OHMARCHY_VTEST_TCP_ALLOW=127.0.0.0/8`.
2. The app cannot use a TCP socket the root broker accepted: its vtest failed on the
   first read and the connection was reset. Fixed (`47696d6`): the broker bridges
   each TCP client to a socketpair through a forked pump and passes the Unix end,
   marked; the app only ever sees Unix sockets.
3. Then the real limit: `virgl_renderer_resource_create failed (-22)`. With protocol
   version 0 the client picks its own resource ids; the app's renderer is shared
   with Hyprland (multi-client mode) and those ids collide with Hyprland's. That
   is why multi-client mode wants version 3 (ids allocated by the server), and
   version 3 sends resources as shm fds, which cannot cross TCP.

So a VM's GL client cannot simply join the app's renderer. Ways on, none done:

- a vtest-aware proxy pair: in the guest, a proxy speaking version 3 to Mesa and
  making the shm itself; on the host, the broker's pump receiving the server's
  shm fds (it is a Unix socket there) and keeping both copies in step on
  transfers. Version 3 throughout, ids from the server. Most work, keeps one
  renderer and the 120 Hz present path;
- a second renderer for remote clients: a separate process cannot draw into the
  app's window (route I option A showed that), so only inside the app, and
  virglrenderer is one per process.

Reference, same session: the guest's own virtio-gpu (virgl, zink on the Maleoon)
gives glmark2 933 at 640x480 and es2gears at its display's 60 Hz.

Not the main route yet: the transport and security parts are in place, the
protocol limit needs the proxy pair.

## First run (2026-10-24 09:07–09:40 PDT, vm.lock, headless)

`tools/ownvm/ownvm.sh` on `omarchy-own.img` (agent-2a's `omarchy-pure.img`
plus the no-preferred 120 Hz EDID), StratoVirt on HMV, 6 vCPUs, 8 GiB,
vhost-device-gpu (virglrenderer) + `vhost-user-gpu-pci,virgl=true`, NIC with
rx/tx iothreads, no display. Linux 7.2.12-1.1 with `arm64.hmv_idreg_quirk`.

| Check | Result |
|---|---|
| Network | ping, ssh, DNS, HTTPS (`archlinux.org` 200 in 1.7 s), `pacman -S` all work |
| Host scanout | `output 0: 2160x1440+0+0` |
| 120 Hz | probed modes `"2160x1440": 120 424500 …` first, then 60; active CRTC (`dri/0/state`) `"2160x1440": 120 424500 2160 2208 2240 2320 1440 1443 1453 1525` |
| GPU | `virgl (zink Vulkan 1.2(Maleoon 916 (ARM_PROPRIETARY)))`: 3D on the host GPU, through Zink |
| Docker | 29.9.2, overlayfs, cgroup v2, systemd driver; `hello-world` and a compose project (nginx + a client container: `Welcome to nginx!`, exit 0) through registry mirrors (`docker.m.daocloud.io`, `docker.1ms.run` in `/etc/docker/daemon.json`); Docker Hub direct times out |
| Open | published port 8080 not reachable from the guest itself (`curl 127.0.0.1:8080` → 000); not looked into |
| Not done | anything on screen: option A is closed, vtest needs a shm proxy |

What it took:

- **Host routing.** With 鸿融's bridge gone the guest's subnet sits on the tap,
  but the host's policy routing sends `172.16.100.2` out `wlan0` (rule 16000,
  `fwmark 0/0xffff iif lo` → table 2009, before main), and forwarded guest
  packets look up main, which has no default route. Two rules fix both
  directions (now in `testvm.sh start`, removed by `net-down`):
  `ip rule add to 172.16.100.0/24 lookup main pref 10500` and
  `ip rule add iif hmvtest0 lookup 2009 pref 10501`. With those and the NIC
  iothreads the guest receives and the host reaches it. The tap counters
  already showed traffic in both directions before the rules, so whether the
  iothreads alone were needed is not separated by this run.
- **Guest access.** ohdev's sshd does not forward (`unsupported channel type`),
  so the guest is reached by ssh from the host with a host-only key
  (`ownvm.sh g`). ohdev's sshd also mangles quoting in a command argument, so
  everything goes through `sh -s` on stdin.
- **sudo.** The password comes from an environment variable, never a file;
  sudo's timestamp then covers the rest of that ssh session. A rule written
  offline with debugfs was lost: the guest had been killed (QMP powerdown does
  not stop it), and the journal replayed on the next boot. Power the guest off
  from inside (`sudo systemctl poweroff`).

## Route I as D's background Linux (decided 2026-10-24 09:50 PDT)

The supervisor's decision after the first run: no on-screen picture for this
VM (no shm proxy, no vhost-user-gpu backend in the app). Root users already
have D's native 120 Hz desktop; what D lacks is Docker and a full kernel. So
route I is a headless VM that D's desktop uses in the background.

**Service.** `tools/ownvm/ohmarchy-vm` (installed in `/data/local/kaidashi/bin`):
`start` (idempotent; returns when the guest's ssh answers, about a minute),
`stop` (power-off from inside the guest via a sudo rule limited to
`systemctl poweroff|reboot`, QMP and kill as fallbacks), `status` (VM,
guest, dockerd, guest memory, `query-balloon`, host RSS), `ssh`, `balloon MiB`,
`net-up`/`net-down`. Settings: `OVM_CPUS` (6), `OVM_MEM` (8192 MiB), `OVM_GPU=1`
(virgl, off by default for a Docker backend), or `$OVM_DIR/config`.
Differences from `testvm.sh`: its own tap `ohmvm0` and run directory
(`ownvm/svc`), the host routing rules added and removed by the script
(idempotent, `net-down` deletes every copy of pref 10500/10501),
`virtio-balloon-pci,deflate-on-oom=true,free-page-reporting=true`, and
the guest's host key pinned (`tools/ownvm/known_hosts`, `SHA256:4zK0cQ3DUJ7/aUSTr22zV/GdwiYBRIAua9y7MihSuLE`).
While other HMV users share the host it takes `vm.lock` (owner
`ohmarchy-vm`) and refuses to start next to any other StratoVirt (鸿融 uses
the same subnet).

The routing rules change host routing for everyone: with them a host process
reaching `172.16.100.1` gets source `172.16.100.1` instead of
`7.247.135.16`, which matters to route D's `vtest-broker` allowlist (harmless
there: it accepts only on `172.16.100.1` and remote virgl is off by default).
HarmonyOS's rules are `uidrange 0-65534`; apps (uid ≈ 20020165) use other
per-app rules, untested and not needed (only root processes reach the VM).

**Start at boot (optional, not installed).** `tools/ownvm/ohmarchy-vm.cfg`
is an init service in the format of route D's `native/boot/ohmarchy-desktop.cfg`
(after `bootevent.boot.completed`, `once`). It runs `ohmarchy-vm-boot.sh`,
which waits for D's session (its ssh client) and starts the VM. Install by
copying the cfg into `/mnt/overlay/usr/upper/etc/init/`. Not installed while
鸿融 and the other routes share HMV, and only a reboot can verify it.

**Guest.** `tools/ownvm/guest-provision.sh`, run once as root in the guest:
the narrow sudo rule (and removal of the broad `zz-ownvm-test` used in the
first run), Docker + compose enabled, yao in the docker group, registry
mirrors, `virtio_balloon` loaded at boot. The guest kernel has what Docker and
the balloon need (from the image's `build/.config` and module tree):
`CONFIG_PAGE_REPORTING=y`, `VIRTIO_BALLOON=m`, `NF_TABLES`, `NFT_COMPAT`,
`IP_NF_NAT`, `NETFILTER_XT_MATCH_ADDRTYPE`, `XT_TARGET_MASQUERADE`,
`BRIDGE`, `BRIDGE_NETFILTER`, `VETH` (all modules present). StratoVirt's help
text lists `virtio-balloon-pci,…,deflate-on-oom=…,free-page-reporting=…`.

**D's side** (native-desktop line, in `native/40-install-desktop.sh`): D's
terminal runs in the archtest session as `builder` (uid 60000), with Omarchy's
docker 29.9.2 and docker-compose 5.6.1 clients; context `ohmarchy` =
`ssh://yao@172.16.100.2` as the default, builder's key in yao's
`authorized_keys` on the disk, the guest host key in builder's `known_hosts`.
dockerd is not exposed on TCP.

**Run as a service (2026-10-24 09:52–09:55 PDT, vm.lock):**

| Item | Result |
|---|---|
| `ohmarchy-vm start` | guest ssh up 5 s after StratoVirt started (cold boot); rules 10500/10501 and the lock added |
| Provision | narrow sudo rule (`sudo -n systemctl --version` refused), Docker active, `virtio_balloon` bound, page reporting order 9 |
| D → VM Docker | from D's terminal (archtest, `builder`, context `ohmarchy` over ssh), run by the native-desktop line: `hello-world` PASS (1.2 s), compose PASS |
| Port 8080 | `docker run -p 8080:80 nginx:alpine`: 200 from the guest (127.0.0.1, 172.16.100.2, localhost) and from the host. The first run's `000` was a race, not the port mapping: nginx listens a moment after compose reports "Started", and the first request is reset; `guest-setup.sh` now retries |
| Balloon (free page reporting) | host RSS of StratoVirt: 1151 MiB idle → 4109 MiB with 3000 MiB written to `/dev/shm` in the guest → **1161 MiB within ~6 s** after deleting it. Idle: ~1.17 GiB host RSS for an 8 GiB guest |
| `ohmarchy-vm stop` | power-off from inside the guest in ~10 s; rules, tap and lock removed |

StratoVirt's `query-balloon` answers `GenericError "No error information (os
error 0)"`, so `status` shows host RSS instead; the reclaim itself works.

Lesson for scripts that ssh into the guest inside `ssh ohdev sh -s`: give the
inner ssh `< /dev/null`, or it reads the rest of the outer script from stdin
and the outer shell stops early (it cost several truncated runs).
