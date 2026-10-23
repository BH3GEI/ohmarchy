# Route D desktop: Omarchy's Hyprland, native, in a HarmonyOS window

Route D ([native-chroot.md](native-chroot.md)) runs Arch Linux ARM and Omarchy's
packages in a chroot on the HongMeng kernel. This adds the desktop: Omarchy's own
Hyprland session, rendered by a patched Hyprland in that chroot and shown by a
HarmonyOS app, with no VM in between.

```
HarmonyOS app (native/app)            Arch chroot (route D)
  XComponent window  <-- dmabuf fds --  Hyprland (patched) + Omarchy shell, apps
  touch/mouse/keys   -- RFB input -->   wayvnc (input only)
                                          |  GL: Mesa virpipe
HarmonyOS host                            v
  virgl_test_server (native/vtest) <-- /tmp/.virgl_test
    system libvirglrenderer (zink) --> Maleoon GPU
```

## Status

Verified on an HM740 (Kirin X90, HongMeng kernel 1.11.13.0, HarmonyOS 7.0):

- Omarchy 4.0.6's Hyprland session runs: Quickshell bar and notifications,
  wallpaper, keybindings, the Omarchy menu, Xwayland. Input from the app's window
  (mouse, touch, keyboard) reaches Hyprland.
- Hyprland renders on the Maleoon GPU: Mesa's virpipe driver talks to a vtest
  server on the host, which uses the system's own virglrenderer (the one the 鸿融
  VM's GPU runs on: zink over the Maleoon Vulkan driver). Without the server it
  falls back to llvmpipe on the CPU.
- The app shows Hyprland's output buffers directly: aquamarine exports them as
  dmabufs over an abstract unix socket and the app maps them; no screen capture.
- Animated frame rates on the GPU path (workspace switches): about 27 frames/s at
  the panel's 2880x1920 (scale 1.5), about 46 at 1920x1280 (scale 1). The limit is
  reading each frame back from the GPU through vtest (about 35 and 17 ms).
- Clients (terminals, Quickshell, browsers) render on llvmpipe. The host's
  virglrenderer rejects some of Mesa 26's virgl commands from Qt Quick clients, so
  virpipe is used for Hyprland only.

Open:

- No zero-copy present yet: the frame goes GPU -> vtest -> CPU buffer -> app ->
  HarmonyOS window. The system virglrenderer can present to a native window
  (`virgl_renderer_ohos_present`), which would remove the read-back.
- `debug:overlay` deadlocks Hyprland here (its text rendering waits on the async
  resource gatherer); don't enable it.
- Input still goes through wayvnc's RFB (the app asks it for no frames).

## Install

1. Route D's image, session and Omarchy setup (`10`..`30` in `native/`).
2. On a machine with GitHub access: `native/desktop/fetch-sources.sh`, then copy
   `native/` to the host as before.
3. In the session: `sh arch.sh run 40-install-desktop.sh builder` (builds the
   patched aquamarine and Hyprland with clang into `/opt/ohmarchy`, about 10
   minutes on the X90).
4. GPU (optional): on the machine with DevEco Studio, `native/vtest/build-vtest.sh`;
   copy `build/virgl_test_server` to `<base>/bin/` on the host.
5. The app: `native/app/build.sh` (DevEco Studio's command-line tools; see below).

## Use

```sh
omarchy desktop start      # vtest server (if present), Hyprland, Omarchy shell, wayvnc
omarchy desktop status
omarchy desktop stop
```

Then open "Omarchy (native)" on the HarmonyOS desktop. It opens as a window
(maximize it from the title bar) and says what it is waiting for until the first
frame arrives.

Display size: `OHMARCHY_DISPLAY_MODE` and `OHMARCHY_DISPLAY_SCALE` in the desktop's
environment (default `2880x1920@60` and `1.5`; `1920x1280@60` and `1` is faster,
the app scales it to the window). `HYPRLAND_READBACK_TIMING=1` prints read-back
time and frame rate to `/run/user/<uid>/ohmarchy-desktop.log`.

## The app (native/app)

ArkTS page with a SURFACE XComponent and a C++ module (`ohdisp.cpp`):

- Frames: connects to the abstract socket `@ohmarchy-display`; each message names
  an output buffer, its geometry, format and damage, with the dmabuf fd the first
  time. The app maps it and copies it into the XComponent's native window buffer.
  SELinux allows this as is: apps (`normal_hap_attr`) may connect to unix sockets of
  the root shell's `su` domain and use its fds.
- Input: RFB to wayvnc on 127.0.0.1:5900 (pointer, wheel via axis events, keys
  mapped to X keysyms). Without the export socket it also takes frames from RFB.
- Signing: this research build accepts the OpenHarmony test keys from the SDK, so
  `sign/sign.sh` signs with them and a debug profile bound to the device's UDID
  (`bm get --udid`); no developer account is involved. A production HarmonyOS build
  will want a debug certificate from AppGallery Connect instead.

## HongMeng notes

| Issue | Fix |
|---|---|
| No DRM device, so aquamarine has no allocator and Hyprland no EGL device | dma-heap allocator (`/dev/system_heap2`, mode 666, as `/dev/dma_heap/system` in the chroot); EGL on `EGL_PLATFORM_SURFACELESS_MESA` |
| virpipe has no `EGL_EXT_image_dma_buf_import` | Hyprland renders into GL storage and reads the damaged region back into the buffer |
| No linux-dmabuf protocol then; image-copy-capture dereferenced it | offer shm only when it is absent |
| `uname` reports `HarmonyOS` / `HongMeng Kernel 1.11.13.0`; cmake has no such platform | preloaded `uname` shim reporting `Linux` / `6.6.0-hongmeng` |
| g++ 16.1 crashes (ICE, even at `-O0`) on aquamarine and Hyprland | build with clang |
| ALARM's root ships libglvnd without GL headers | reinstall libglvnd |
| `omarchy-launch-shell` logs through `systemd-cat` | `systemd-cat` shim that runs the command |
| Omarchy's first run fails its systemd step and repeats its notifications at every login | `ohmarchy-desktop` marks it done once it has run |
| vtest server lives in the session's mount namespace, outside its pid namespace, and would keep the image mounted | `arch.sh stop` stops it first |
| `start-hyprland` restarts Hyprland when it is killed | stop the watchdog first |
