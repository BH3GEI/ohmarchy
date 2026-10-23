# Route D: Arch Linux ARM natively on the HongMeng kernel

The HongMeng kernel of HarmonyOS PCs implements enough of the Linux syscall ABI
to run an unmodified Arch Linux ARM userland directly: no VM, no Linux engine
container. The Arch root lives in an ext4 image on `/data`, and a root shell on
the host enters it with `unshare` (mount + pid namespace) and `chroot`.
Omarchy's packages install from its signed AArch64 repository, so the terminal
side of Omarchy (bash setup, starship prompt, LazyVim, themes, btop, lazygit,
mise) runs at native speed on the host's CPU.

The kernel has no GPU or DRM device. Omarchy's Hyprland desktop still runs
here with a patched Hyprland and aquamarine, rendering on the GPU through the
host's virglrenderer and shown by a HarmonyOS app: see
[native-desktop.md](native-desktop.md). Route C's 鸿融 VM is the other desktop
([hongrong-whole-os.md](hongrong-whole-os.md)); Wayland apps from route D can
open windows there through waypipe (`omarchy -g APP`).

## Status

Verified on a Kirin X90 HarmonyOS PC, HongMeng kernel 1.11.13.0:

- Arch Linux ARM (aarch64, rolling; pacman fully updated) in a 64 GB sparse
  ext4 image, one persistent session with catatonit as pid 1.
- `bin/omarchy` opens a login shell as the user (or root) from any root shell
  on the host, with a proper pty and job control; `omarchy -c CMD` runs one
  command.
- Omarchy 4.0.6: `omarchy`, `omarchy-settings` and the quattro branch's base
  and aarch64 package lists install from the stable channel (896 packages in
  the end, about 1.9 GB downloaded). In the shell: Omarchy's bash rc, aliases and
  starship prompt, `fastfetch` (reports Omarchy 4.0.6 on the HongMeng kernel),
  nvim with Omarchy's LazyVim config and bundled plugins, `omarchy-theme-set`
  (switches nvim, btop and terminal colors; all themes listed), btop, lazygit,
  tmux, mise with Node, gum, eza, zoxide, fzf, ripgrep.
- Toolchains: gcc, gdb, strace, go, node, python (asyncio, multiprocessing),
  git over https.
- Graphics: Wayland apps (foot verified) show as ordinary tiled windows in the
  鸿融 VM's Hyprland desktop through waypipe: `omarchy -g foot`. The native
  desktop is in [native-desktop.md](native-desktop.md).

Not working:

- Stock Hyprland does not start: aquamarine needs a DRM/GBM render node and
  the kernel has no DRM. The patched build in
  [native-desktop.md](native-desktop.md) works around it.
- No systemd: cgroup v1 only and no user/cgroup namespaces, so systemd cannot
  be pid 1. Services do not run; `systemctl enable` only writes links.
- `omarchy-menu` and other desktop commands fail ("omarchy-shell is not
  running") outside the native desktop. `omarchy-update-available` times out (GitHub); `omarchy-update`
  was not run. `omarchy-apply-system` must not be run (see Install).
- GitHub is not reachable from the host's network here; package lists come
  through a proxy, plugins and themes that fetch from GitHub fail.

## Layout on the host

```
/data/local/archtest/          ARCH_BASE (native/config.sh)
├── arch.img                   sparse ext4 image, the Arch root
├── arch/                      mount point, visible only inside the session
├── arch.sh                    session manager: start | status | run FILE | stop
├── bin/omarchy                launcher
├── session.pid, session.loop  host pid of the session's pid 1, its loop device
└── dl/alarm.tar.gz            Arch Linux ARM tarball (+ .md5)
```

`/data` is hmfs, mounted `nosuid,nodev`: device nodes and setuid binaries only
work inside the image, which is why the root is an image and not a directory.

## Getting a root shell on the host

The other routes drive the HarmonyOS machine from a host over `hdc`. This one
runs on the HarmonyOS machine itself and needs a root shell there: any ssh
server or terminal running as root in a domain that may `unshare`, `mount`,
`losetup` and `chroot` (`su` on a developer build, for example). The `hdc
shell` user is not root and cannot do this.

The built-in terminal app (`com.huawei.hmos.hishell`, an alacritty-based
terminal) runs as an ordinary app uid and the system has no `su`, so it cannot
enter the session. HarmonyOS ships a setuid `/system/bin/sudo` with its sudoers
under `/data/service/el1/public/sudo_config/`; whether the terminal's `sudo`
gives a root shell that can run `bin/omarchy` was not tried.

## Install

As root on the host, with this repository's `native/` directory copied to the
machine (GitHub may need a proxy or a copy over ssh):

```sh
cd native
sh 10-make-image.sh                    # ALARM tarball + md5, arch.img, arch.sh, bin/arch
B=/data/local/archtest
sh $B/arch.sh start
sh $B/arch.sh run 20-setup-arch.sh builder      # DNS, pacman, keys, -Syu, user (uid 60000), locales, splice fix
sh $B/arch.sh stop; sh $B/arch.sh start         # catatonit as pid 1 from now on
sh $B/arch.sh run 30-install-omarchy.sh builder # Omarchy repo and packages (~2 GB), user setup
```

`arch.sh run FILE` copies a host file (and an `etc/` directory next to it)
into the session's `/tmp` and runs it as root with a clean environment.

What `30-install-omarchy.sh` changes against an ISO install (compare
`hongrong/20-install-omarchy.sh`):

- **Repositories.** `native/etc/pacman.conf` is Route C's aarch64 template
  plus `DisableSandbox`. Package lists come from the same pinned quattro
  commit, through `gh-proxy.com` (override with `OMARCHY_LISTS`); pacman checks
  every package against Omarchy's key.
- **No `omarchy-apply-system`.** The session shares the host's network
  namespace, so its firewall step would load ufw rules into the HarmonyOS
  kernel. Its other steps need systemd, a boot loader, SDDM or hardware. Only
  the file-only `install/config/theme-system.sh` and `updatedb` run.
- **User.** `/etc/skel` is copied into the existing home, then
  `omarchy-provision-user --force --first-install` runs as the user with
  `OMARCHY_SETUP_CONTEXT=provision-owner` and Node from npmmirror, as on Route C.

Package scripts that call `systemctl` print "System has not been booted with
systemd" and carry on. systemd's pacman hooks skip `sysctl`, `binfmt` and
`udev` because `/run/systemd/system` does not exist in the session, so nothing
is written to the host's kernel settings.

## Daily use

```sh
/data/local/archtest/bin/omarchy               # login shell as builder
/data/local/archtest/bin/omarchy root          # login shell as root
/data/local/archtest/bin/omarchy -c btop       # one command (remaining words joined)
/data/local/archtest/bin/omarchy -g foot       # Wayland app as a window in route C (below)
/data/local/archtest/bin/omarchy stop|start|status
```

The launcher starts the session if needed, then enters it with `nsenter` and
switches user with coreutils `chroot --userspec` (no PAM). The environment is
built from scratch: `HOME`, `USER`, `SHELL`, `PATH`, `XDG_RUNTIME_DIR`
(`/run/user/UID`, created on demand), and `TERM`, `COLORTERM`, `LANG` passed
through from the caller. The caller's pty is given to the user, and an
interactive shell gets its own session with that pty as controlling terminal.
Add `/data/local/archtest/bin` to the root shell's `PATH` to type just
`omarchy`. This host launcher is not Omarchy's own `omarchy` command (its
command center), which exists only inside the session: `omarchy -c omarchy
theme list` runs the latter through the former.

`sudo` works inside (wheel, no password). `/tmp` and `/run` are tmpfs and
cleared on `omarchy stop`; everything else persists in the image. `omarchy stop`
syncs, kills the session and detaches the loop device.

## HongMeng quirks

| Quirk | Effect | Workaround (in `native/`) |
|---|---|---|
| No user or cgroup namespaces; cgroup v1 only | no rootless containers, no systemd as pid 1 | `unshare -m -p` as root, catatonit as pid 1 |
| No Landlock | pacman's download sandbox fails | `DisableSandbox` in pacman.conf |
| `mount -o loop` (toybox) fails with EFAULT | | `losetup` by hand |
| `losetup -f` names `/dev/loopN`, but only `loop0` has a node there; `losetup -a` lists only those | a second image fails to attach; `-a` misses it | attach the first free `/dev/block/loopN`; query each with `losetup DEV` |
| Namespace teardown leaves the loop bound; after a plain `umount` it is already detached | stale loop | `arch.sh stop` runs `losetup -d`; `10-make-image.sh` tolerates ENXIO |
| Binding a device node onto a file fails | no bind-mounted `/dev/null` etc. | tmpfs `/dev` with `mknod` |
| `mknod -m` is masked by umask | nodes not world-writable | `chmod 666` |
| devpts has no `ptmx` and `newinstance` fails | | bind the host's `/dev/pts`, `mknod /dev/ptmx c 5 2` |
| pacman's CheckSpace needs the root to be a mount point | | the root is the mounted ext4 image |
| `/data` is `nosuid,nodev` (and `errors=panic`) | no device nodes or setuid in a directory root | ext4 image |
| `splice()` from a drained pipe whose writers are gone into another pipe fails with EPIPE instead of returning 0 | coreutils 9.12 `cat` exits 1 on `cat > file <<EOF` (the file is complete); breaks package scripts and Omarchy's installer | `/etc/ld.so.preload` shim built by `20-setup-arch.sh` that reports EOF |
| tmpfs files carry an SELinux label that ext4 refuses (`security.selinux`, EACCES) | `mv` from `/tmp` into the image warns (exit 0) | none needed |
| toybox `nsenter` parses options after the command | `nsenter ... chroot R env -i ...` takes `-i` itself and the host environment leaks in | `--` before the command |
| `setpriv` fails: PR_SET_KEEPCAPS not permitted | | coreutils `chroot --userspec --skip-chdir /` |
| The pty is the controlling tty of a session outside the pid namespace | bash: "no job control in this shell" | `setsid -w -c` for interactive shells |
| No `/sys/devices/system/cpu/cpufreq`, no PCI | btop shows no CPU clock; `lspci` warns | none needed |
| No user namespace: uids are the host's | the user's processes run as that host uid; HarmonyOS uses most uids below 10000 (1000 `system`, 1001 `radio`) | `20-setup-arch.sh` creates the user with uid 60000 |
| SELinux enforcing | root's domain may run unsigned code from `/data` | none needed |

The syscall surface that works: threads, futexes, epoll, eventfd, timerfd,
signalfd, inotify, memfd with sealing, io_uring, ptrace (gdb, strace), large
sparse mmaps, sockets over the host's network. Page size 4K.

## Desktop: show apps in route C

With the 鸿融 VM of route C running and logged in to Hyprland, Wayland apps
started in route D open as normal windows on that desktop:

```
route D (host, chroot)                                 鸿融 VM (route C, 172.16.100.2)
app -> waypipe server -> $XDG_RUNTIME_DIR/route-d.sock
       -> socat -> TCP 172.16.100.2:7777 over the VM bridge -> socat -> waypipe client -> Hyprland
```

- VM side, once: copy `native/vm/route-d-display` to `~/.local/bin/` in the
  Omarchy guest and start it with the session, in `~/.config/hypr/autostart.lua`:
  `o.launch_on_start("/home/<user>/.local/bin/route-d-display")`. It runs
  `waypipe client` on a local socket and `socat` listening on the bridge
  address, port 7777. It needs `waypipe` and `socat` in the guest.
- Host side: `omarchy -g APP [ARG..]` starts, as the user, one `socat` bridge
  per session (`$XDG_RUNTIME_DIR/route-d.sock` to `172.16.100.2:7777`; set
  `ROUTE_D_VM` for another address), then `waypipe --no-gpu --compress lz4
  server -- APP` detached from the terminal. waypipe exits with the app; output
  goes to `$XDG_RUNTIME_DIR/route-d.log`. The host only connects out to the
  VM, nothing listens on the host.

Verified with foot: the window tiles in Hyprland, and fastfetch in it reports
the host's 20 CPUs (the VM has 6).

Limits: apps render on the host's CPU (no GPU in route D, so `--no-gpu`); only
the compositing in the VM uses the GPU. The VM has to be running and logged in.
X11-only apps need Xwayland in the chain (not tried).

## Desktop status

Stock Hyprland 0.56 fails here with aquamarine's "no allocator available" (it
needs a DRM/GBM render node even headless), and anything on the HarmonyOS
screen needs a HarmonyOS app that owns a window. Both are solved in
[native-desktop.md](native-desktop.md): a dma-heap allocator and surfaceless EGL
in patched aquamarine/Hyprland, a frame export socket, a display app, and a
vtest server on the host's virglrenderer for the GPU (the same zink-on-Maleoon
renderer route C's VM uses).

## Next steps

- Launch route D apps from the VM's menu (desktop entries that call into the
  host), and clipboard sharing.
- The native desktop's own next steps are in [native-desktop.md](native-desktop.md#status).
- Hyprland with a dumb buffer allocator (aquamarine has no non-DRM allocator
  today).
- A launcher entry reachable from the built-in terminal, if its `sudo` gives a
  suitable root shell.
