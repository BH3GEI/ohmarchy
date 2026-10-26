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

## The three stages

The plan for this route had three stages; all three are done and were accepted
(2026-10-24). What each one asked for, and what shows it:

| Stage | Asked for | Done | Evidence |
|---|---|---|---|
| 0. The pipe | a minimal HarmonyOS app showing the session's desktop and sending input back | `native/app`: the app shows the compositor's frames (dmabufs over `@ohmarchy-display`) and sends pointer, touch, keys and IME text back over the same socket | [cf9b3d1](https://github.com/BH3GEI/ohmarchy/commit/cf9b3d1), [256d741](https://github.com/BH3GEI/ohmarchy/commit/256d741), [b10a7c0](https://github.com/BH3GEI/ohmarchy/commit/b10a7c0) |
| 1. Hyprland | an aquamarine backend, Omarchy's desktop in it | aquamarine 0.15.1 with a dma-heap allocator and headless frame export, Hyprland 0.56.2 patched for EGL surfaceless; Omarchy 4.0.6's session runs in the app (bar, menu, apps, Xwayland, Chinese input); 74 of 78 apps open in 3 s | [cf9b3d1](https://github.com/BH3GEI/ohmarchy/commit/cf9b3d1), [509f5c0](https://github.com/BH3GEI/ohmarchy/commit/509f5c0), [73ce712](https://github.com/BH3GEI/ohmarchy/commit/73ce712) |
| 2. GPU | vtest + virglrenderer, as smooth as the VM or better | the renderer runs in the app (vtest on the system virglrenderer, Maleoon GPU) and presents Hyprland's frames into the window without a copy at 120 Hz: es2gears 117-120 fps on screen against 60 in the 鸿融 VM, workspace switch 119 fps | [06d44d0](https://github.com/BH3GEI/ohmarchy/commit/06d44d0), [403f900](https://github.com/BH3GEI/ohmarchy/commit/403f900), [2a4852d](https://github.com/BH3GEI/ohmarchy/commit/2a4852d) |

Past the three stages, the "commercially usable" acceptance (A to G) is in
[acceptance.md](acceptance.md): most items pass, including the 24 h soak
(2026-10-24 17:52 to 10-25 17:53 CST, no memory growth). Still open are the
checks that need someone at the machine and the remote virgl trial (a VM's GPU
work shown by this app, [vm-own.md](vm-own.md)). Web apps now open in Firefox,
sandboxed, instead of Chromium without a sandbox.

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

  The VM's virtual display advertises only 60 Hz: its EDID (read in the guest from
  `/sys/class/drm/card0-Virtual-1/edid`) lists 1920x1280 at 59.998 Hz, 2160x1440 at
  59.9999 Hz and so on, nothing faster. Its GPU renders twice that; half never
  reaches the screen. Natively the per-window count (`ohdispSurface fps`) agrees
  with the compositor's (118 and 112 fps).

  A third, independent source, three 8 s `hitrace -t 8 graphic` captures per side
  during es2gears at 1920x1280 (window in front):

  | Per second | Native | 鸿融 VM |
  |---|---|---|
  | Screen compositions (`RSMainThread::DoComposition`) | 117.6, 116.4, 117.8 | 41.1, 40.6, 37.6 |
  | Frames to the display hardware (`HwcPresentDisplay`) | 120.8, 119.3, 120.9 | 40.1, 37.3 |
  | Buffers the window received (`NativeWindowFlushBuffer`) | 117.8, 116.3, 117.8 | 123, 120, 112 | Natively the app asks the panel for 120 Hz and presents directly.

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

### Developer tools and coding agents

Mirrors: rustup from TUNA, `GOPROXY=goproxy.cn`, npm from npmmirror, pip from
TUNA (`native/desktop/environment.d/50-mirrors.conf`; proxy.golang.org does not
answer from here). Coding agents: Omarchy's launchers in `~/.local/bin`
install opencode, Codex and Claude Code through mise on first use;
`native/desktop/ai/setup.sh` (root on the host) configures them for Yao's API
relay with the script every route uses (`hongrong/pure/guest/setup-ai.sh`),
reading the relay's address and key from `/data/local/secrets/ai.env`; they end up
only in the user's `~/.config/environment.d/ai.conf` (mode 600) and the agents'
configs in the home directory. All three are pinned to `kimi/kimi-for-coding`
(the relay knows only its own model IDs; `ark/ark-code-latest` is the
alternative) and answered a test prompt on 2026-10-26: opencode 2.1.4, Codex
0.163.0 (Responses API), Claude Code 2.1.310 (Anthropic API).

### Starting by itself (no root shell)

At boot, init runs `native/boot/ohmarchy-desktop.cfg` → `boot-start.sh` →
`omarchy desktop start`: the Arch session, the GPU broker, Hyprland, the sound
relay and the docker gate for route I. A user then only clicks "Omarchy
(native)": the app's connection to the broker (only its uid, SO_PEERCRED)
restarts the desktop for it. `docker` in the desktop starts route I's VM on
demand and the VM stops after 3 idle minutes ([vm-own.md](vm-own.md)).

Checked without a reboot on 2026-10-26 (`tests/demo/autostart.sh`; screenshots: [stopped](img/autostart/00-stopped.jpeg),
[after the hook](img/autostart/01-after-boot-hook.jpeg), [app open](img/autostart/02-app-open.jpeg),
[docker](img/autostart/03-docker-cold.jpeg), [after the idle stop](img/autostart/04-after-idle-stop.jpeg)): desktop, docker gate, VM and the
display app stopped; the boot hook run as init runs it (clean environment, cwd
`/`, detached): Hyprland, sound relay and gate up 21 s later (the hook waits
20 s first); the app opened: the fresh desktop in its window; `docker run --rm
hello-world` in a desktop terminal: VM started by the gate, "Hello from Docker!"
in the terminal (guest up 5 s after StratoVirt started); 160 s after the docker
step the gate powered the VM off. Not covered: the Arch session and the GPU
broker were left running (other work shares the session; `boot-start.sh` only
starts what is missing), and init loading the cfg at a real boot. The reboot
test waits for the D line.

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

## Keyboard shortcuts and touchpad

- **Use right Alt for Super.** HarmonyOS keeps the Windows (Super) key: it opens its
  start menu on the key's release, which takes the focus, and it keeps many Super
  chords for itself (Settings → 键盘 → 键盘快捷键 lists them; there is no switch to
  turn them off, and no API lets an app keep them; immersive full screen doesn't
  help either, checked 2026-10-26). So the app sends right Alt to the desktop as
  Super (evdev 125); left Alt stays Alt. The file `files/super-key` in the app's
  data directory chooses the stand-in: `ralt` (default), `capslock`, or `off`
  (only the Windows key).
- The Windows key itself still works as Super, with the start menu opening as
  well. Without its release Hyprland kept Super pressed and read every later key as
  a Super chord; the app releases every key still pressed when its window loses
  the focus (1744727).
- Omarchy shortcuts that HarmonyOS takes when pressed with the Windows key (so only
  right Alt gives them on HarmonyOS):

  | Omarchy | does | HarmonyOS uses ○ (Windows key) + it for |
  |---|---|---|
  | Super+Space | Omarchy menu | switch input method |
  | Super+Tab | next workspace | task center |
  | Super+Up / Super+Down | focus above / below | maximize / minimize window |
  | Super+F | full screen | open the file manager |
  | Super+L | toggle workspace layout | lock screen |
  | Super+S | toggle scratchpad | 小艺 search |
  | Super+C / Super+V | universal copy / paste | control center / clipboard history |
  | Super+P | pseudo window | projection |
  | Super+Backspace | toggle window transparency | back |
  | Super+/ | monitor scaling up | shortcut help panel |
  | Super+Shift+S | Google Maps | screenshot |

- Touchpad: two-finger scrolling is smooth on both axes with a stop at the end
  (f82c550). Three-finger left/right swipes switch workspaces: the page's
  PanGesture(fingers 3) goes to Hyprland as swipe events (export input 7/8/9) and
  `ohdisplay.lua` turns on Omarchy's workspace gesture (40f9b2a). Built and installed;
  not yet tried with a real touchpad (injected input has no touchpad).
- Every key, axis, touch and swipe event is logged to hilog (tag `ohdisp`) for the
  first 300 events, or all while `files/inputlog` exists in the app's data directory
  (`/data/app/el2/100/base/com.ohmarchy.display/files/inputlog`).

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
| Host GPU server (`OHMARCHY_GPU=host`): each desktop restart left a `virgl_test_server` child behind (~80 MB), its connection still ESTAB with no peer | `omarchy desktop stop` ends the server's children; the desktop's clients are gone by then |
| Reading `/proc/PID/cmdline` of a process that exits during the read (`tr '\0' ' ' < /proc/PID/cmdline` in a script) can spin forever: one such `tr` ran at 100 % of a core for 16 h | read it with a timeout, or check the process still exists first; kill strays |
| `clone(CLONE_FS)` does not share the root and cwd: a child's `chroot`/`chdir` does not reach the parent | Chromium's setuid sandbox cannot jail its zygote (it fails a check and dies); Chromium runs with `--no-sandbox` | Firefox (seccomp-bpf sandbox works) for the browser and web apps |
| Omarchy's Lua config: `hyprctl dispatch`/`keyword` do not parse | `hyprctl eval 'hl.exec_cmd("...")'` |
