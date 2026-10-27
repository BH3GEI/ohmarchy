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

- namespaces: mount, pid, ipc, uts its own; net and time shared with the host;
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
- there is no devpts filesystem (mount: No such device; the host's `/dev/pts` is
  empty). ptys still work through `/dev/ptmx`: glibc's `openpty()` gets the other
  end with TIOCGPTPEER, but no `/dev/pts/N` node ever appears, so `ttyname()` fails
  (checked in the demo session, 2026-10-28). The sandbox has `/dev/ptmx` like the
  demo, so the same should hold inside; not yet checked there.

## Known boundaries (v1)

- The network namespace is the host's: the sandbox uses HarmonyOS's network stack,
  so it reaches services listening on the host's loopback and its abstract unix
  sockets. To be closed with a network namespace of its own (a4 is working out
  how Docker's networking fits).
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

To do: open the app on screen, a pty check inside the sandbox, the app side (`com.ohmarchy.sandbox`, its own socket names), Docker's
start with its own capability set (a4).
