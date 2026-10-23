# Route D desktop: Omarchy's Hyprland, native, in a HarmonyOS window

Route D ([native-chroot.md](native-chroot.md)) runs Arch Linux ARM and Omarchy's
packages in a chroot on the HongMeng kernel. This adds the desktop: Omarchy's own
Hyprland session, rendered by a patched Hyprland in that chroot and shown by a
HarmonyOS app, with no VM in between.

```
HarmonyOS app (native/app)                      Arch chroot (route D)
  XComponent window <- presents GPU frames --+   Hyprland (patched) + Omarchy shell, apps
  in-process GPU renderer: vtest +            |    |  GL: Mesa virpipe -> /tmp/.virgl_test
    the system's libvirglrenderer (zink)  <---+----+  (vtest-broker passes the connection)
    -> Maleoon GPU                            |
  touch/mouse/keys -- evdev events -->  @ohmarchy-display (aquamarine's export devices)
```

## Status

Verified on an HM740 (Kirin X90, HongMeng kernel 1.11.13.0, HarmonyOS 7.0):

- Omarchy 4.0.6's Hyprland session runs: Quickshell bar and notifications,
  wallpaper, keybindings, the Omarchy menu, Xwayland. Input from the app's window
  (mouse, touch, keyboard) reaches Hyprland.
- Hyprland renders on the Maleoon GPU and its frames go into the app's window
  without a copy. The renderer runs inside the app: upstream vtest
  (`native/app/vtest-inapp.patch`) on the system's own `libvirglrenderer` (the one
  the 鸿融 VM's GPU runs on: zink over the Maleoon Vulkan driver), bundled in the
  HAP. Mesa's virpipe driver in the chroot connects to `/tmp/.virgl_test`, where
  `native/vtest/vtest-broker` (root, on the host) accepts and passes the connection
  to the app. After each frame Hyprland blits one pixel of it into a 7x3 marker
  texture and flushes (`HYPRLAND_READBACK_PRESENT`); the app sees that blit in the
  command stream and presents the frame with the library's own
  `virgl_renderer_ohos_present`, the call the VM uses for its scanout. Hyprland
  never waits for the GPU (0.3-0.6 ms per frame), presents do not wait for vsync
  (swap interval 0), and the renderer presents only when no client is waiting for
  it (a present blocks its thread for about 1.3 ms).
- GPU apps: `ohmarchy-gpu APP` runs an app on virpipe. When it reads its frame back
  for wl_shm, the app's renderer copies it on the GPU (raw copy) into a snapshot and writes only
  a tag into the buffer; when Hyprland uploads tagged data, the renderer copies the
  snapshot into Hyprland's texture instead (Hyprland swaps red and blue when
  sampling such a texture: the copy keeps the client's RGBA order, wl_shm data is BGRA). `libohzc.so` (preloaded by the wrapper)
  keeps Mesa from copying the untouched rest of the frame on the CPU.
- Input goes back over the abstract socket `@ohmarchy-display` into a pointer and a
  keyboard that aquamarine's headless backend registers (evdev codes; Hyprland
  applies the keymap), so no VNC server runs.
- Frame rates, panel at 120 Hz (the app asks for it), output `@120`:

  | Output (scale) | Workspace animations | es2gears, GPU (`ohmarchy-gpu`) | es2gears, llvmpipe |
  |---|---|---|---|
  | 1920x1280 (1) | 92-120 frames/s | 99-115 | 71-80 |
  | 2160x1440 (1), the 鸿融 VM's size | 112 shown on screen (95% of frames on consecutive vsyncs) | 114-118, average 116; 118 shown on screen | 62-65 |
  | 2880x1920 (1.5), the panel | 73-107 | | 39 |

  Side by side with the 鸿融 VM (鸿融 1.1.1.103, the Omarchy VM disk imported), same
  outputs, three runs each, all counted by HarmonyOS's own compositor
  (`hidumper -s RenderService -a "composer fps"`: the frames that reach the screen):

  | | Native | 鸿融 VM |
  |---|---|---|
  | 1920x1280, es2gears, rate it reports | 114-120 | 114-120 |
  | 1920x1280, es2gears, shown on screen | 117-120 fps | 60 fps |
  | 1920x1280, workspace animations, shown | 115-116 fps | 60 fps |
  | 2160x1440, es2gears, rate it reports | 112-117 | 111-120 |
  | 2160x1440, es2gears, shown on screen | 117-118 fps | 60 fps |
  | 2160x1440, workspace animations, shown | 109-115 fps | 59-60 fps |

  The VM's display path runs at 60 Hz (its virtual monitor offers only 60 Hz modes,
  e.g. `1920x1280@60.00Hz 2160x1440@60.00Hz`): half of what its GPU renders never
  reaches the screen. Natively the per-window count (`ohdispSurface fps`) agrees
  with the compositor's (118 and 112 fps). Natively the app asks the panel for 120 Hz and presents directly.

  "Shown on screen" is HarmonyOS's own count for the app's window
  (`hidumper -s RenderService -a "ohdispSurface fps"`). Without vsync
  (`vblank_mode=0`) es2gears on the GPU runs at about 170 frames/s.
  Before this path (frames read back to the CPU through vtest and copied into the
  window): 46 and 27 frames/s for animations at 1920x1280 and 2880x1920, 35-40 and
  16-21 for es2gears. llvmpipe clients are bound by their own CPU rendering and by
  Hyprland uploading their shm buffers.
- With `OHMARCHY_GPU=host` (or no `bin/vtest-broker`), `bin/virgl_test_server`
  renders on the host and Hyprland reads every frame back for the app (the earlier
  path). Without either it falls back to llvmpipe on the CPU.
- Clients (terminals, Quickshell, browsers) render on llvmpipe. The system
  virglrenderer rejects some of Mesa 26's virgl commands from Qt Quick clients, so
  virpipe is used for Hyprland only.

Open:

- GPU apps need `ohmarchy-gpu`; by default clients stay on llvmpipe. Read-backs of
  a whole window by a GPU app (screenshots of itself) get the tag, not pixels.
- Hyprland's GPU connection lives in the app: closing the app ends it, Hyprland
  aborts and `start-hyprland` brings it back in safe mode (waiting for the app).
  Restart the desktop after reopening the app (`omarchy desktop stop; omarchy
  desktop start`) until a launcher does this.
- `debug:overlay` deadlocks Hyprland here (its text rendering waits on the async
  resource gatherer); don't enable it.
- Screen capture (grim, screenshots) of Hyprland's output reads the CPU copy of
  the frame, which the app no longer needs and Hyprland no longer fills.

Apps and features, what works and what doesn't: [native-compat.md](native-compat.md).

## Install

1. Route D's image, session and Omarchy setup (`10`..`30` in `native/`).
2. On a machine with GitHub access: `native/desktop/fetch-sources.sh`, then copy
   `native/` to the host as before.
3. In the session: `sh arch.sh run 40-install-desktop.sh builder` (builds the
   patched aquamarine and Hyprland with clang into `/opt/ohmarchy`, about 10
   minutes on the X90).
4. GPU: on the machine with DevEco Studio, `native/vtest/build-vtest.sh`; copy
   `build/vtest-broker` (and `build/virgl_test_server` for the host path) to
   `<base>/bin/` on the host.
5. The app: `native/app/build.sh` (DevEco Studio's command-line tools; see below).
   The first build runs `gpu-prep.sh`, which copies the device's
   `libvirglrenderer.so.1` and `libepoxy.so.0` into the HAP and fetches vtest.

## Use

```sh
omarchy desktop start      # vtest-broker (or server), Hyprland, Omarchy shell
omarchy desktop status
omarchy desktop stop
```

Then open "Omarchy (native)" on the HarmonyOS desktop (with the broker, Hyprland
waits for it). It opens as a window (maximize it from the title bar) and says what
it is waiting for until the first frame arrives.

Display size: `OHMARCHY_DISPLAY_MODE` and `OHMARCHY_DISPLAY_SCALE` in the desktop's
environment (default `1920x1280@120` and `1`; `2880x1920@120` and `1.5` is the
panel's resolution, sharper and slower).
`HYPRLAND_READBACK_TIMING=1` and `HYPRLAND_FRAME_TIMING=1` print read-back and
frame times to `/run/user/<uid>/ohmarchy-desktop.log`.

## Input methods

fcitx5 with pinyin (Omarchy's input method; its systemd unit does not run here, so
`ohdisplay.lua` starts it and applies Omarchy's `environment.d`). Ctrl+Space switches
between US and pinyin; typed keys reach it as evdev codes from the app, and the
candidates show inside the Linux desktop. Verified: "nihao" + space gives 你好 in foot.

Alternative, `OHMARCHY_IME=harmony`: `ohime` (native/desktop/ohime.c) runs instead of
fcitx5 as the compositor's input method (`zwp_input_method_v2`), and Ctrl+Space in the
app attaches the HarmonyOS IME, whose text the app sends to ohime over `@ohmarchy-ime`
for the focused text-input-v3 client. Built and running; not yet verified on screen.

## The app (native/app)

ArkTS page with a SURFACE XComponent and a C++ module (`ohdisp.cpp`):

- Frames, GPU path: when `vtest-broker` answers on `@ohmarchy-vtest`, the app owns
  no pixels itself. `gpu.cpp` sets `NEED_OPENGL=1` (the system EGL then loads Mesa,
  zink on the Maleoon Vulkan driver, instead of the vendor GLES), runs vtest on a
  thread with clients from the broker, and presents the frame Hyprland marks.
  The library asks `libhwf_kits.z.so` for the window (in the VM, the 鸿融 app sends
  it over IPC); the app's own `hwf_kits.c` of that name returns the XComponent's.
  Two quirks of the library: binding the scanout to a new resource of another size
  starts a 1 s black "resize debounce" that only a timer-driven call ends (scanout
  id with bit 31 set, which the app passes on every present), and the window must
  not have had a CPU-written buffer (format and Vulkan swapchain clash). Its log:
  `/data/app/el2/100/base/com.ohmarchy.display/files/vtest.log`.
- Frames, CPU path: otherwise it connects to `@ohmarchy-display`; each message
  names an output buffer, its geometry, format and damage, with the dmabuf fd the
  first time. The app maps it and copies it into the XComponent's window buffer.
  SELinux allows this as is: apps (`normal_hap_attr`) may connect to unix sockets
  of the root shell's `su` domain and use its fds.
- Input: 16-byte messages on the same socket (pointer position in output pixels,
  evdev buttons, scroll steps, evdev key codes). Without the export socket it
  falls back to RFB on 127.0.0.1:5900 for frames and input (X keysyms).
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
| The panel idles at 60 Hz | the app votes 120 Hz for its XComponent (`OH_NativeXComponent_SetExpectedFrameRateRange`) |
| Custom modes on non-DRM outputs get refresh 0 unless given exactly (`@60` stays 60 Hz) | output mode `@120` |
| vtest server or broker lives in the session's mount namespace, outside its pid namespace, and would keep the image mounted | `arch.sh stop` stops it first |
| `start-hyprland` restarts Hyprland when it is killed | stop the watchdog first |
| `/etc/machine-id` empty: libdbus aborts, which took the Omarchy shell down once Qt loaded its fcitx plugin | write one with `dbus-uuidgen` |
| Omarchy's Lua config: `hyprctl dispatch`/`keyword` do not parse | `hyprctl eval 'hl.exec_cmd("...")'` |
