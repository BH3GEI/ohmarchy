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
- 120 Hz: `tools/ownvm/mkedid.py` writes an EDID with 2160×1440 @ 120 Hz
  (CVT-RB2, 409.9 MHz), 1920×1280 @ 120 Hz and 2160×1440 @ 60 Hz, to load in the
  guest with `drm.edid_firmware=Virtual-1:edid/ohmarchy-120.bin`
  (`CONFIG_DRM_LOAD_EDID_FIRMWARE=y` in 7.2.12).
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
