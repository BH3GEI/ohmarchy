# ohm-sandbox

Launcher for the sandboxed native route (direction: [handover.zh-CN.md](../../docs/handover.zh-CN.md)
§1.5 and §3(b)). Run as root on the HarmonyOS host:

```
ohm-sandbox create    # new image from the demo session's root (read only), plus a snapshot
ohm-sandbox start | stop | status
ohm-sandbox reset     # back to the snapshot (stopped first)
ohm-sandbox run CMD.. # a command inside, as root
ohm-sandbox shell
```

## Kept apart from the demo version

The demo (`native/arch.sh`, `/data/local/archtest`, the boot service) is not touched:

- its own directory, `/data/local/ohm-sandbox/` (`root.img`, `clean.img`, `root/`,
  `sandbox.pid`, `sandbox.loop`, `sandbox.log`); `OHM_SANDBOX` overrides it;
- the first free loop device (loop1 on ohdev, where the demo holds loop0);
- no autostart: started by hand;
- nothing is shared with the demo session (image, directory, loop device, pid file;
  no sockets while there is no app), so both can run at once; `start` refuses only if
  `root.img` is attached to a loop already. `create` and `reset` borrow GNU tar/cp
  from the demo's root (read only), and `reset` copies 14 GB, a few minutes of disk load;
- `create` only reads the demo's root (build trees and caches are left out).

`ohm-capdrop` (from `ohm-capdrop.c`) drops the capabilities and joins the namespaces
for `run`; build it static and put it in the sandbox's `bin/`:

```
SDK=/Applications/DevEco-Studio.app/Contents/sdk/default/openharmony/native
$SDK/llvm/bin/clang --target=aarch64-linux-ohos --sysroot=$SDK/sysroot -static -O2 -o ohm-capdrop ohm-capdrop.c
```

## Tested on ohdev, 2026-10-28, beside the running demo

start, status, `config-check.sh`, stop, reset (about a minute, nice 19), all with the
demo desktop running; its health check before and after was identical (same
processes and pids, same md5 of its scripts and boot configs). What the check
printed (`/data/local/ohm-sandbox/evidence/config-check-20261028.txt`):

- namespaces: mount, pid, ipc, uts its own; net and time shared with the host (net
  its own since, see Network);
- capability bounding set `b18cecff` (the list in `ohm-sandbox` dropped);
- `/` the image (nodev), `/proc` its own, `/proc/sys` and `/sys` read-only, `/dev` a
  tmpfs with null, zero, full, random, urandom, tty, ptmx and the dma-heap node;
- processes inside: catatonit (pid 1) and the command run.

HongMeng differences met on the way:

- util-linux `setpriv` fails ("keep process capabilities failed": PR_SET_KEEPCAPS is
  refused), hence `ohm-capdrop`; PR_CAPBSET_DROP itself works;
- toybox `nsenter` opens `/proc/PID/ns/*` after entering the mount namespace, where
  that pid does not exist; `ohm-capdrop --enter` opens them all first;
- a read-only remount of a sysfs bind is refused (ENOTSUP); a fresh sysfs mounted
  read-only works;
- there is no devpts filesystem (mount: No such device). Opening `/dev/ptmx` makes
  the slave appear as a node in the host's `/dev/pts`, which the demo binds in.
  The sandbox does not (it would show every host pty, root shells included), so
  terminals that open the slave by path fail inside: foot, Omarchy's terminal,
  says "failed to open pseudo terminal slave device: No such file or directory"
  (2026-10-28). Fixed without binding anything in: `desktop/hongmeng-ptypeer.c`,
  preloaded inside, opens "/dev/pts/N" through this process's own master
  (TIOCGPTPEER) when the node is missing, and names the slave for `ttyname`
  (HongMeng gives it no name: an anonymous inode, device 0:0) from what it opened
  or, for the standard fds, from OHMARCHY_TTY; it wraps openpty and forkpty for
  the programs that use those. Checked inside: a slave opened by name works and
  is named (it fails without the shim), `script -c tty` prints /dev/pts/0, a tmux
  pane gets /dev/pts/0, and the same as builder. foot on screen failed at first:
  strace showed its child unlocks the master, closes it, and only then opens the
  slave by name, when there is no master left to ask. The shim now records
  masters from posix_openpt and, when a forked child closes one, keeps its slave
  for that open. HongMeng refuses TIOCGPTPEER without O_NOCTTY, so the shim asks
  with it and gives a session leader its controlling tty with TIOCSCTTY. foot's
  exact sequence in python then works as builder (named, controlling tty).
  OHMARCHY_PTY_DEBUG=1 (stderr) or =/path traces what the shim does.

Inherited files: processes inside held fd 13, the host's `/dev/kmsg`, inherited
from the shell that started the launcher. `ohm-capdrop` now closes every fd above 2
before anything runs inside, and init's and the desktop's stdio go to the
sandbox's own `/dev/null`; afterwards no process inside held a host file except a
`run` command's own stdio (its output to the caller), 2026-10-28.

## Known boundaries (v1)

- Abstract Unix sockets are shared with the host. HongMeng does not keep abstract
  names per network namespace (checked 2026-10-28: a host process connected to a
  name bound inside the sandbox's own network namespace), so the sandbox can still
  connect to every abstract socket the host's processes listen on, HarmonyOS's own
  services among them (the list and who owns each: `abstract-sockets-ohdev.md`).
  The app's sockets with the desktop work because of this. Abstract names per
  network namespace, as Linux keeps them, is a request to HarmonyOS
  (docs/handover.zh-CN.md 3(a)).
- The SELinux domain is still `su` (HarmonyOS's policy cannot be extended at run
  time on ohdev, 2026-10-28); a domain of its own is a request to HarmonyOS.

## Desktop (2026-10-28, ohdev, no screen yet)

`ohm-sandbox build-helpers` rebuilt ohime, the sound relay and ohmarchy-desktop
inside (sources from `src/`, fed in on stdin) so they use the sandbox's names;
`native/sandbox/build-app.sh` built `com.ohmarchy.sandbox`, installed beside the
demo's app (uids 20020168 and 20020165). `ohm-sandbox desktop start` brought up
Hyprland, PipeWire, the relay and D-Bus inside as `builder`, the GPU broker on the
host waiting for the app (`@ohmsbx-vtest`), next to the demo's `@ohmarchy-*`
sockets; `desktop stop` and `stop` left nothing behind. The demo's health check
was identical before and after.

On screen (2026-10-28): the app shows the sandbox's desktop in its own window
beside the demo's; mouse clicks and keys reach it (Alt+Shift+2 switched to
workspace 2); `cowsay` installed with pacman as root through `ohm-sandbox run`
(builder's sudo asks for a password, as on any Arch); inside, `/storage`,
`/sdcard`, `/system` and `/vendor` do not exist and `/data` holds only the
image's own `local` directory (evidence: `ls-host-paths-20261028.txt`).

On screen again (2026-10-28 02:10): Alt+Shift+Return opened foot in the sandbox's
window; in it `tty` printed /dev/pts/0, `ls /storage` said No such file or
directory, `/data` showed only the image's `local`, `cowsay sandbox` drew its cow.

## As an app (2026-10-28)

The app starts and stops Linux itself through the helper `ohm-sandboxd`
(`ohm-sandboxd.c`, started by `ohm-sandbox serve`): it listens on @ohmsbx-ctl, takes
connections only from `com.ohmarchy.sandbox`'s uid (SO_PEERCRED) and one line each,
only `start`, `stop`, `reset` or `status`, mapped to fixed launcher calls (nothing
the client sends reaches a command line), one request at a time. Opening the app
sends `start` (the overlay says "Starting Linux…"), closing it sends `stop`; the
icon's menu has "Reset Linux" (a shortcut; the app asks before it resets). The
sandbox build opens maximized. The GPU broker no longer restarts the desktop when
the app connects: the helper owns that.

Checked from the command line on ohdev: a test instance answered status, start (17
s), status (running), stop, and refused an unknown line; the real one refused a root
client.

On screen (2026-10-28 02:49-03:01): a double-click on "Omarchy (sandbox)" started
Linux (16 s) and the desktop filled the screen; the app found the GPU broker right
after the start (it looks again for 30 s, since the broker comes up with Linux).
"关闭窗口" in the dock icon's menu closed the app and Linux stopped (10 s). "Reset
Linux" from the desktop icon's menu opened the app, which asked, reset (33 s) and
started again; cowsay, installed after the snapshot, was gone. A failing step no
longer stops the helper's sequence (desktop stop fails when nothing is left).

Using it (full screen, no title bar):

- Alt+Tab switches to other windows (HarmonyOS's switcher) and back.
- Ctrl+Alt+Escape minimizes the app (Omarchy binds nothing there; Alt+Shift+Escape
  would be Super+Escape, its system menu).
- Close: "关闭窗口" in the dock icon's menu (right-click or long-press); Linux stops
  with the app.
- Reset: "Reset Linux" in the same menu, or the desktop icon's; it asks first.
- Not tried: the mouse at the top edge, three-finger swipes (no injected touchpad).

## Install and uninstall (from this computer)

```
native/sandbox/install.sh HOST [--write-system]
native/sandbox/uninstall.sh HOST
```

`install.sh` builds the helper binaries and the app (signed for the device), copies
them and the launcher, installs the app, makes the Linux image from the demo
session's root if there is none (and rebuilds the helpers inside it), starts the
helper, and checks: the sandbox and its desktop start, and the demo session, its
processes, the init cfgs, `ld-musl` and `libc.so` are as before. Its only file
outside /data is `/system/etc/init/ohm-sandboxd.cfg` (the helper at boot, through
`boot-serve.sh`): without `--write-system` it is only shown; with it, written only
if absent, and compared after writing. `uninstall.sh` removes the helper, the app,
`/data/local/ohm-sandbox`, and that cfg only if it is the installer's, byte for byte.

On ohdev (2026-10-28): installed with `--write-system`; the cfg written and read back
the same. Init reads cfgs only at boot (`begetctl start_service ohm-sandboxd` before a
reboot: "Cannot find service"), so the helper at boot is checked at the next reboot;
until then it runs from `ohm-sandbox serve`.

To do: check the helper at the next reboot; Docker's start with its own capability
set (a4).

## Network (2026-10-28)

The sandbox has a network namespace of its own (`start`: `unshare -n`). pasta
(passt.top, commit 6aa4f88, with `passt-hongmeng.patch`; built inside by
`ohm-sandbox build-pasta`, as `bin/pasta`) runs on the host and joins it: the
sandbox gets the host's address and routes, and its TCP, UDP and ICMP go out
through host sockets, like an app's own connections. Nothing is forwarded inward
(`-t none -u none -T none -U none`), the gateway is not mapped to the host
(`--no-map-gw`), and the host's routes and firewall are not touched. HarmonyOS keeps
the default route in a table of its own (2009, policy routing); `start` reads it
there. After the PC changes networks, `ohm-sandbox net` connects it again.

Checked on ohdev, on screen in the app's terminal: https://archlinux.org 200 and
`pacman -Sy`; the host's `127.0.0.1:22` refused (curl 7). The app's display, sound
and GPU sockets connected as before; stop ends pasta.

HongMeng differences pasta met (the patch): no user namespaces (`/proc/self/uid_map`
absent); `CLONE_FILES` not honoured, so what a `clone()`d child opens is not in the
parent's table (its namespace calls run in a thread instead: threads share the
table, and `setns()` in one moves only that thread); `close_range` refuses
`CLOSE_RANGE_UNSHARE`; tmpfs takes no size options; and with its capabilities
dropped it cannot open `/proc/<pid>/ns/net` (ENOENT), so `start` lends it a bind
mount of it, lazily unmounted once pasta holds it.
