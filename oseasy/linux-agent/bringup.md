# On-device bring-up runbook — ohmarchy-oseasy-agent

One pass, on ohdev, after the demo rehearsal, scheduled by the supervisor. Goal:
start an Omarchy VM in OSEasy, get the prototype agent running inside it, and in a
single session read off the three remaining unknowns **(which vport, the
`connectionMode` value, the method-id registry)** while checking whether the plain
(no-`authString`) handshake makes OSEasy treat the VM as "installed / can power on".

Secrets never go in this file or any commit/log: the VM login password and the
device lock password are entered only via `uitest`/command line, from the
supervisor, at run time.

## Success vs. stop criteria

- **Success:** OSEasy accepts the plain handshake and starts treating the VM as a
  normal/installed VM (ideally shows 开机 instead of only 再次安装), and we have
  captured the vport name, the `connectionMode` value that worked, and the inbound
  `Call.methodID`s. Screenshot the OSEasy state.
- **Stop (auth barrier):** OSEasy rejects the plain handshake, or explicitly
  requires `authString`. Do **not** craft/guess an authString. Record it in
  `../../docs/oseasy-vendor-request.md` as a request and report to the supervisor.

## Pre-flight

1. Supervisor has given the go (bring-up window after rehearsal).
2. `ssh ohdev` responds. `pidof stratovirt` is **empty** (no VM running; one VM per host).
3. The screen is free (no one else driving OSEasy/鸿融/native). Do not touch any
   window the user (Yao) opened.
4. The B ISO (`/data/local/vmtest/work/iso-out/oseasy-probe.iso`, 1.2 kernel) is in
   the guest Download dir, or re-copy it there (the media mounts only after the
   device is unlocked):
   `cp .../iso-out/oseasy-probe.iso /storage/media/100/local/files/Docs/Download/ ; chown 20001006:1006 ; chmod 640`.

## Step 1 — reach an Omarchy desktop in OSEasy

Drive OSEasy with `OHUI_HOST=ohdev OHUI_DIR=/tmp/ohui tools/ohdev/ohui`:
立即创建 → (检测到 ISO → 取消) → 点击选择 ISO → pick `oseasy-probe.iso` → 打开 →
下一步 → 继续安装 → 仍要安装 → 开始安装 → wait for install → reboots to Omarchy.
At the "Enter Password" lock, enter the VM login password via `ohui type` (not in
this file). Open a terminal (Omarchy: Super+Return).

Confirm boot health from the host while it installs:
`ssh ohdev 'sh -s' <<'EOF'` → `grep -c 'Invalid features select' /data/log/hwf_service/vmlog` (want 0).

**ISO-selection gotcha (seen 2026-10-28, machine under load ~20).** The picker
showed `已选 (1/1)` but OSEasy's page stayed empty (`点击选择 ISO`, 下一步 greyed) —
the selection did not propagate, across single-click+打开, double-click, and an 8 s
wait. It had worked on the same Download path in earlier runs, so it reads as a
file-access-grant / latency hiccup under heavy load, not a logic bug. Remedies, in
order:
1. **Don't rapid-click.** After `打开`, wait and watch 下一步 go orange before the
   next tap; the grant can lag when load is high.
2. **Confirm the right file** — the new ISO is `2032457728` bytes; don't pick an old one.
3. **Pre-stage where OSEasy reads directly.** The Download dir is on hmdfs/media,
   which **ignores `chmod`** (the ISO stays `640`, owner `20001006`, so OSEasy's uid
   can only read it via the picker grant). If the grant keeps failing, copy the ISO
   somewhere OSEasy can read as its own uid and pick it there.
4. Restart OSEasy (close → confirm 退出 → reopen the desktop card) and retry once.
5. If two retries still stall, **stop** and retry when the machine is idle — this
   step is latency-sensitive, not urgent.

## Step 2 — get the agent into the guest (zero image change)

In the guest terminal, in order of preference:

- **If the guest has outbound network:** fetch the three files from this repo:
  ```
  for f in frame pb agent; do curl -fsSLO https://raw.githubusercontent.com/BH3GEI/ohmarchy/main/oseasy/linux-agent/$f.py; done
  ```
- **Else:** on the host, serve them on the tap address and curl from the guest
  (guest IP is 172.16.100.2; host tap is the .1). `make-bundle` produces a single
  `bringup-agent.py` if a one-file curl/paste is easier.
- **Else:** paste `bringup-agent.py` (the single-file bundle) into the terminal.

## Step 3 — run and observe

```
python3 agent.py      # or: python3 bringup-agent.py
```
Read from its stderr log:
1. **`virtio-ports present: {...}`** — the name→/dev/vportNpX map. Note which names
   exist (winbox_serial0/1, additions_vioser0/1, …). → answers "which vport".
2. **handshake send line** — then watch for any inbound frame. If the port was
   wrong, no data arrives; try the next candidate via `OSEASY_* ` env (below).
3. **`RX frame ...`** lines — record each `type=` and `call={methodID,...}` →
   builds the method-id registry.

Meanwhile screenshot OSEasy: did its VM state change (installed / 开机 offered)?

### If the first guess is rejected, iterate (same session)

Try the candidates without editing code:
```
OSEASY_CONN_MODE=command OSEASY_HS_MSGTYPE=3 python3 agent.py   # event-channel style
OSEASY_CONN_MODE=event   OSEASY_HS_MSGTYPE=3 python3 agent.py
OSEASY_CONN_MODE=         OSEASY_HS_MSGTYPE=0 python3 agent.py   # empty mode
```
(The handshake msgType is the frame type byte; the event-channel handshake uses 3.
`connectionMode` is a runtime value we could not read statically — try command /
event / empty.) The agent also lists all ports; if none match, set
`PORT_NAME_CANDIDATES` from what `virtio-ports present` showed.

## Step 4 — record the findings

Fill the three answers into `agent.py` (port, connectionMode, msgType) and the
method-id dispatch, commit, and update `../../docs/oseasy-agent-protocol.md`
(remove the on-device TODOs). If an auth barrier was hit, record it in
`oseasy-vendor-request.md` instead.

## Step 5 — stop the VM (procedure, do not improvise)

In order (see `../../docs/vm-api.md`):
1. Clean guest poweroff from the guest terminal: `systemctl poweroff` (or `sudo poweroff`).
2. If the guest is unresponsive: `aa force-stop -b com.oseasy1.ohvm` (stops OSEasy
   re-pulling the VM).
3. Only then, if `stratovirt` is still up: `kill <exact-pid>` (never by name), then
   confirm `pidof stratovirt` is empty and **stays** empty (no auto-respawn).
Never touch a window Yao opened. Switch the foreground back to whatever was there.

## Step 6 — report

Report to the supervisor: handshake accepted or auth-barrier; the vport /
connectionMode / method-ids learned; OSEasy state (did 开机 appear?); HMV freed.
