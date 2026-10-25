# Route D desktop: compatibility

What opens and what works in the native Omarchy desktop
([native-desktop.md](native-desktop.md)) on a HarmonyOS PC.

Last checked: 2026-10-23. HM740 (Kirin X90, 20 threads), HongMeng kernel
1.11.13.0, Omarchy 4.0.6, desktop at 1920x1280.

✅ works · ⚠️ works with a caveat · ❌ doesn't work

Times are from launch to the window being mapped (`hyprctl -j clients`), with
the desktop idle. Apps were launched through Hyprland's exec, as a keybinding
or the menu does it. "By inspection" means the script was read but not run.

The root causes behind most ❌ rows:

- **No systemd.** systemd can't be pid 1 (cgroup v1, no namespaces). A system
  D-Bus runs with the desktop, but only udisks2, polkit and upower can be started
  on it; NetworkManager, bluez, power-profiles-daemon and cupsd would act on
  hardware HarmonyOS owns and are not allowed. The session bus works.
- **No user namespaces.** No bwrap, Chromium/Electron sandbox, rootless
  containers or flatpak.
- **No hardware devices.** The chroot has no DRM, sound, video, backlight or
  input devices. The HarmonyOS app is the only screen, keyboard and pointer.
- **Clients render on the CPU** (llvmpipe) unless started with `ohmarchy-gpu`. Hyprland uses the GPU.

## Launch paths and Omarchy's own apps

| Item | Works | Notes |
|---|---|---|
| Terminal (SUPER+RETURN) | ✅ | 0.35 s. `xdg-terminal-exec` picks foot; Omarchy's ghostty/alacritty aren't installed. |
| Tmux, Herdr (SUPER+ALT/CTRL+RETURN) | ✅ | 0.4 s. |
| Browser (SUPER+SHIFT+RETURN, Chromium) | ⚠️ | 1.0 s cold (new profile), 0.9 s for a new window. Needs `--no-sandbox` (`~/.config/chromium-flags.conf`). Logs system-bus errors (UPower), which are harmless. The `chromium.desktop` entry with Chromium already running opens a tab, not a window. |
| Web apps (SUPER+SHIFT+A etc., webapp `.desktop` entries) | ✅ | 1.0-1.3 s, as Chromium `--app` windows. Whether a site loads depends on the network. |
| File manager (SUPER+SHIFT+F, and cwd variant) | ⚠️ | Nautilus, 1.0 s. No removable media or disks (udisks). |
| Editor (SUPER+SHIFT+N) | ✅ | nvim in foot, 0.35 s. |
| btop, lazygit (`omarchy-launch-tui`) | ✅ | 0.4 s. btop shows no CPU clock (no cpufreq). |
| Docker | ⚠️ | No container runtime on HongMeng; the docker CLI uses dockerd in route I's VM over ssh (`docker run`, `docker compose`, lazydocker work; needs `ohmarchy-vm start`). See acceptance.md A1b. |
| Music TUI cliamp (SUPER+SHIFT+ALT+M) | ⚠️ | Was: exits without ALSA/PipeWire. PipeWire now runs; not re-tested. |
| Spotify, Signal, 1Password (SUPER+SHIFT+M/G/SLASH) | ❌ | Not installed (no aarch64 packages in the repo). |
| Obsidian (SUPER+SHIFT+O) | ⚠️ | 1.2 s with `--no-sandbox`. Without it Electron's setuid sandbox aborts. Fix: `/usr/local/bin/obsidian` wrapper (below). |
| Omawrite (SUPER+SHIFT+W) | ✅ | 1.0-1.4 s. |
| About (menu > About) | ✅ | Already open on the desktop (foot). |
| Screensaver (menu > System > Screensaver) | ✅ | ttfx in foot, 0.7 s. The idle-triggered screensaver is turned off by the desktop setup. |

## Omarchy menu and shell overlays

| Item | Works | Notes |
|---|---|---|
| Omarchy menu (root, Apps, Learn, Install, System, ...) | ✅ | Quickshell layer, 0.4 s. |
| App launcher (menu > Apps) | ✅ | Runs `uwsm-app -- gtk-launch ID.desktop`. `uwsm-app` is a shim (no systemd --user). |
| Keybinding cheatsheet (SUPER+K, Learn > Keybindings) | ✅ | 0.7 s, 224 bindings parsed. |
| Learn > Omarchy/Hyprland/Arch/... | ✅ | Web apps (see above). |
| Style > Theme | ✅ | Selector in 1.0 s. `omarchy-theme-set` takes 19 s. It warns that `mv` can't set `security.selinux`, which is harmless. |
| Style > Background, Font, Bar | ✅ | By inspection: file and shell IPC only. |
| Setup > Monitors/Keybindings/Input/Hyprland | ✅ | Opens the file in nvim (editor path). |
| Setup > Network, Bluetooth, Power, DNS | ❌ | NetworkManager, bluez and power-profiles-daemon need the system bus. HarmonyOS manages these. |
| Setup > Security > SSHD, Direct Boot | ❌ | By inspection: systemd units and a boot loader. Don't run. |
| Install > Package / Remove > Package | ✅ | Terminal with pacman and fzf, 0.4 s. pacman works. |
| Install > AUR | ❌ | `yay` reaches the AUR, but builds hang in `fakeroot` (SysV IPC). |
| Install > Web App, TUI | ✅ | Floating terminal, 0.4 s. |
| Install > Development > Docker DB | ❌ | No docker daemon. |
| Update > Omarchy (`omarchy-update`) | ⚠️ | Not run. `omarchy-update-available` answers in 0.4 s (`checkupdates` shim). The update itself would run pacman (works), AUR (fakeroot, fails) and mise (works). |
| Update > Process > Shell | ✅ | Restarts Quickshell. |
| Update > Hardware (Audio, Wi-Fi, Bluetooth), Time, Timezone | ❌ | By inspection: systemctl/timedatectl. |
| Update > Password > User | ⚠️ | `passwd` works. The chroot user has no password by default (sudo needs none). |
| System > Lock | ❌ | Turned off by the desktop setup: HarmonyOS locks the machine. On its own it couldn't unlock: no `/etc/pam.d/omarchy-lock-password` and no user password. |
| System > Suspend, Hibernate | ❌ | `systemctl` fails without systemd; nothing happens. HarmonyOS owns power. |
| System > Logout, Reboot, Shutdown | ❌ | By inspection: they close all windows, then `uwsm stop` / `systemctl` fail. The session stays and the host is untouched. To stop: `omarchy desktop stop` from the host. |
| Clipboard history (`omarchy-menu-clipboard`) | ✅ | 0.4 s. `wl-copy`/`wl-paste` work. |
| Emoji picker | ✅ | 0.4 s. |
| Notifications | ✅ | Quickshell owns `org.freedesktop.Notifications`; `notify-send` works. |
| Screenshot (PRINT, `omarchy-capture-screenshot`) | ⚠️ | grim saves to `~/Pictures`. Omarchy's editor (tensaku) isn't installed. |
| Screen recording | ❌ | gpu-screen-recorder refuses llvmpipe ("opengl environment is not properly setup"). wf-recorder isn't installed (untested). |
| Share > Receive / Clipboard (LocalSend) | ✅ | 1.0 s. Listens on the host's network. |
| Idle (screensaver, lock) | ⚠️ | The idle monitor works (input from the app counts). Both actions are turned off by the desktop setup. |

## Other preinstalled GUI apps (`/usr/share/applications`)

| App | Works | Notes |
|---|---|---|
| Aether | ✅ | 1.3 s. |
| CMake GUI | ✅ | 0.7 s. |
| Pinta | ✅ | 2.3 s. |
| Moonlight | ✅ | 1.2 s to window. Streaming untested; it would decode on the CPU. |
| disktree | ✅ | 1.3 s. |
| gliff, Hype, monologue | ✅ | 0.7-1.3 s. |
| Omacalc, Omacut | ✅ | 1.0 s. |
| Omasnap | ⚠️ | Starts as a full-screen layer surface, not a window. |
| imv | ✅ | 0.4 s. |
| LibreOffice (Start Center, Writer, Calc) | ⚠️ | 2.7 s with the statx fix (below). Without it, GTK 3 aborts on its first icon. |
| Evince | ⚠️ | 1.0 s with the statx fix; aborts without it. |
| Papers | ✅ | 1.0 s. |
| mpv | ⚠️ | 0.4 s with `gpu-context=wayland`. Without it, mpv's GPU probe falls into x11 and asserts. Fix: `~/.config/mpv/mpv.conf` (below). Video decodes and renders on the CPU. |
| LocalSend | ✅ | 1.0 s. |
| Superwhisper (settings) | ⚠️ | 0.9 s. Dictation needs a microphone, and there is none. |
| Print Settings (system-config-printer) | ⚠️ | 1.3 s with the statx fix. No cupsd. |
| CUPS (web) | ❌ | Opens `localhost:631` in Chromium; nothing listens. |
| Disks (gnome-disks) | ⚠️ | Opens in 1.0 s on the system D-Bus (udisks2); lists no disks: the session has no block devices. |
| Disk Usage (`dua`) | ❌ | `dua` isn't installed. |
| uuctl | ❌ | Needs systemd --user and dmenu. |
| qv4l2 | ❌ | Missing `libQt6Core5Compat.so.6`. |
| qvidcap | ❌ | No `/dev/video0`. |
| signed | ⚠️ | Needs a PDF argument; from the launcher it prints its help and exits. |
| Fcitx 5 configuration | ⚠️ | No config GUI installed; the entry opens Nautilus. |
| nvim, vim, btop (Terminal=true entries) | ✅ | In foot, 0.4 s. |

## System features

| Feature | Works | Notes |
|---|---|---|
| SysV IPC (`tests/compat/sysv_ipc.c`) | ⚠️ | Shared memory and semaphores work. Message queues: a `msgrcv` that is already blocked is never woken by a later `msgsnd` (the message is queued; a non-blocking `msgrcv` reads it), so fakeroot, hence makepkg, hangs. Fix: preloaded `libhongmeng-msgrcv.so` polls instead; with it all three pass and `fakeroot chown` works. An idle waiter costs 0.2 % of one core (backoff 1 ms for the first second, then up to 20 ms). Roll back: remove its line from the Arch root's `/etc/ld.so.preload`. |
| Session D-Bus | ✅ | Started with the desktop. Activation works for services with an `Exec=` (portals, gvfs, keyring, fcitx5). |
| System D-Bus | ⚠️ | `ohmarchy-sysbus`, started and stopped by `omarchy desktop start/stop`; socket on the session's own `/run`. Started as the `dbus` user (switching to it itself fails: no PR_SET_KEEPCAPS). Bus activation limited to udisks2, polkit and upower; the launch helper (setuid) works. Roll back: delete `/opt/ohmarchy/bin/ohmarchy-sysbus`. |
| Audio | ✅ | No `/dev/snd`; PipeWire (started with the desktop) plays into a sink that the display app plays through OHAudio. About 75-105 ms to the speaker. See acceptance.md A3. No microphone. |
| Wi-Fi, Bluetooth widgets | ❌ | NetworkManager/bluez: system bus. The network itself works (host's network namespace). `nm-online` is replaced (`/opt/ohmarchy/overrides`) so Omarchy's first run no longer asks to set up Wi-Fi on a machine that is online. |
| Power profile, battery | ⚠️ | upower runs but lists no battery (`upower -e`: only the display device). No power-profiles-daemon. |
| Brightness | ❌ | No backlight device; HarmonyOS controls the panel. |
| Printing | ❌ | cupsd not running. |
| Removable media | ❌ | udisks2 runs but the session's `/dev` has no block devices (on purpose: HarmonyOS owns the disks). |
| Polkit / pkexec | ⚠️ | polkitd starts on the system bus; no authentication agent tested. Use `sudo` (no password). |
| Portals | ⚠️ | xdg-desktop-portal with the gtk and hyprland backends; FileChooser, Screenshot, OpenURI, Settings, etc. are on the bus. Not exercised from an app. ScreenCast needs PipeWire. |
| Xwayland | ✅ | X11 client (`QT_QPA_PLATFORM=xcb cmake-gui`) maps in 0.4 s. |
| Chinese input | ✅ | fcitx5 pinyin, started by the desktop with Omarchy's environment; Ctrl+Space switches. "nihao" + space gives 你好 in foot. The HarmonyOS IME through `ohime` is an option (`OHMARCHY_IME=harmony`), not verified on screen. |
| Multi-monitor | ❌ | One headless output shown in one app window. |
| Clipboard to/from HarmonyOS | ❌ | Not bridged. Wayland clipboard inside works. |
| HarmonyOS files | ⚠️ | Not mounted. A bind mount from the host (e.g. `/storage/media/100/local/files/Docs` into the session's mount namespace) works, but only root can read it (uid 60000 gets EACCES). |
| Docker | ⚠️ | No daemon here (dockerd would need cgroups and would change the HarmonyOS network: shared namespace). The CLI uses dockerd in route I's VM over ssh instead; see acceptance.md A1b. |
| Podman, flatpak | ❌ | Not installed; both need user namespaces (bwrap fails: "Creating new namespace failed"). |
| AUR / makepkg | ⚠️ | `fakeroot` hangs: `faked` talks over a SysV message queue, and makepkg's packaging step blocks in `msgrcv` for good (`/proc/<pid>/wchan`: `ipcmgr_msgrcv`; seen 2026-10-24 packaging linux-aarch64). ALARM has no `fakeroot-tcp`. Workaround for local packages: run a copy of makepkg with its root check removed, as root, so it needs no fakeroot (`sed 's/^\(\s*\)if (( EUID == 0 )); then/\1if false; then/' /usr/bin/makepkg`). `yay -Si` works. |
| pacman | ✅ | Omarchy and ALARM repositories. |
| systemd services | ❌ | No systemd. Shims: `uwsm-app`, `systemd-run --user`, `systemd-cat`, `checkupdates`. |
| mise | ✅ | Downloads through gh-proxy (`url_replacements` in `~/.config/mise/config.toml`); node and codex installed. |
| Sandboxes in apps | ⚠️ | Chromium/Electron need `--no-sandbox`. glycin (GTK image loading) runs its loaders unsandboxed and warns. |
| GPU for clients | ⚠️ | llvmpipe by default (GL 4.5, ES 3.2 on the CPU; apps log zink/DRI errors, which are harmless). `ohmarchy-gpu APP` runs an app on the Maleoon GPU (virpipe; es2gears 99-115 frames/s at 1920x1280); some Qt Quick GL is rejected by the system virglrenderer. Hyprland itself always uses the GPU. |

## Performance

| Client | Time to window |
|---|---|
| foot, nvim, btop, lazygit, tmux | 0.35-0.4 s |
| imv, mpv, Xwayland (cmake-gui) | 0.4 s |
| Nautilus, Papers, Evince, Omawrite, LocalSend | 1.0 s |
| Chromium (new window or cold profile), web apps | 0.9-1.3 s |
| Obsidian, Aether, Moonlight | 1.2-1.3 s |
| Pinta | 2.3 s |
| LibreOffice | 2.7 s |

Every client renders on the CPU with llvmpipe (20 threads). Static UIs feel
normal. Video, WebGL and animated apps cost CPU and are the slow case.
Compositing and the frame path to the app are in
[native-desktop.md](native-desktop.md#status).

## Fixes made during this check

`native/40-install-desktop.sh` applies the first three (the shim's source is
`native/desktop/hongmeng-statx.c`); the PAM file is not applied.

| Fix | For |
|---|---|
| `statx` preload (native/desktop/hongmeng-statx.c, built and preloaded by 40-install-desktop.sh) | HongMeng returns EFAULT for `statx(fd, "", AT_EMPTY_PATH)`. Rust's `File::metadata` uses it, so glycin's image loaders fail ("Bad address (os error 14)") and GTK 3 apps abort on their first icon (LibreOffice, Evince, Print Settings). The shim falls back to `fstat`. It must be global: glycin starts its loaders with an empty environment. |
| `/usr/local/bin/obsidian`: `exec /opt/obsidian/obsidian --no-sandbox "$@"` | Electron's setuid sandbox. |
| `~/.config/mpv/mpv.conf`: `gpu-context=wayland` | mpv's x11 assertion. |
| `/etc/pam.d/omarchy-lock-password` (`auth`/`account include system-auth`) | Only matters if the lock is turned back on (it also needs a user password). Unverified. |

The shim:

```c
#define _GNU_SOURCE
#include <errno.h>
#include <fcntl.h>
#include <string.h>
#include <sys/stat.h>
#include <sys/syscall.h>
#include <sys/sysmacros.h>
#include <unistd.h>

int statx(int dirfd, const char *path, int flags, unsigned int mask, struct statx *x)
{
	long r = syscall(SYS_statx, dirfd, path, flags, mask, x);
	if (r == 0 || errno != EFAULT || !x || !path || path[0] || !(flags & AT_EMPTY_PATH))
		return r;
	struct stat s;
	if ((dirfd == AT_FDCWD ? stat(".", &s) : fstat(dirfd, &s)) != 0)
		return -1;
	memset(x, 0, sizeof *x);
	x->stx_mask = STATX_BASIC_STATS;
	x->stx_blksize = s.st_blksize; x->stx_nlink = s.st_nlink;
	x->stx_uid = s.st_uid; x->stx_gid = s.st_gid; x->stx_mode = s.st_mode;
	x->stx_ino = s.st_ino; x->stx_size = s.st_size; x->stx_blocks = s.st_blocks;
	x->stx_atime.tv_sec = s.st_atim.tv_sec; x->stx_atime.tv_nsec = s.st_atim.tv_nsec;
	x->stx_mtime.tv_sec = s.st_mtim.tv_sec; x->stx_mtime.tv_nsec = s.st_mtim.tv_nsec;
	x->stx_ctime.tv_sec = s.st_ctim.tv_sec; x->stx_ctime.tv_nsec = s.st_ctim.tv_nsec;
	x->stx_rdev_major = major(s.st_rdev); x->stx_rdev_minor = minor(s.st_rdev);
	x->stx_dev_major = major(s.st_dev); x->stx_dev_minor = minor(s.st_dev);
	return 0;
}
```

Build: `gcc -O2 -shared -fPIC -o /usr/local/lib/ohmarchy-statx.so statx-shim.c`.
Test: `gdk-pixbuf-csource /usr/share/icons/Yaru/16x16/status/image-missing.png`
prints C source instead of "Bad address".

## How to re-check

As the user inside the session, with the desktop's environment:

```sh
export XDG_RUNTIME_DIR=/run/user/$(id -u) WAYLAND_DISPLAY=wayland-1 OMARCHY_PATH=/usr/share/omarchy
export HYPRLAND_INSTANCE_SIGNATURE=$(ls -t $XDG_RUNTIME_DIR/hypr | head -1)
```

- Hyprland's config is Lua: launch with
  `hyprctl dispatch 'hl.dsp.exec_cmd("CMD > /tmp/CMD.log 2>&1")'` and close with
  `hyprctl dispatch 'hl.dsp.window.close({window="address:0x..."})'`.
  `hyprctl dispatch exec ...` is a Lua syntax error.
- Time to window: poll `hyprctl -j clients` for a new address whose class
  matches. Match the class: other windows may appear meanwhile. Don't kill pids
  that existed before (Chromium web apps share the browser's process).
- Shell overlays (menu, launcher, clipboard, emoji) are layers, not clients:
  diff `hyprctl -j layers | jq -r '.[].levels[][].namespace'`.
- Apps that open no window report their reason in the log. Typical: system bus
  (`/run/dbus/system_bus_socket`), `/dev/snd`, `/dev/video0`, a missing binary.
- Desktop entries: `ls /usr/share/applications ~/.local/share/applications`;
  launch with `gtk-launch ID.desktop`, as the launcher does.
- Services: `busctl --user list`, `busctl --user introspect
  org.freedesktop.portal.Desktop /org/freedesktop/portal/desktop`.
