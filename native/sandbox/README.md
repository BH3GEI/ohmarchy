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

Status 2026-10-27: image created on ohdev (14 GB used); start, stop and reset not yet
run. The app side (`com.ohmarchy.sandbox`,
its own socket names) is still to do.
