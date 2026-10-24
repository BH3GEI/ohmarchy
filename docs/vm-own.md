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
