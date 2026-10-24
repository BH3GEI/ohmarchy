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
Input: the app sends input over `@ohmarchy-display`, which only reaches the host;
a VM desktop needs that bridged too (not done).

To measure (needs the screen and a running VM): es2gears and glmark2 in the VM
through this path; frame rate on screen (HarmonyOS compositor), CPU on both
sides, and latency. A first check without a VM is possible from route D's own
session (it shares the host's network: a client there connecting to
172.16.100.1 comes from the allowed network).
