# ohmarchy-oseasy-agent (prototype)

A minimal, interoperable Linux guest agent that speaks OSEasy's
(`com.oseasy1.ohvm`) guest-agent link protocol, so OSEasy treats an installed
Linux VM as **"installed, can power on"** instead of only offering 再次安装
(which wipes `/dev/vda`). Protocol details: [`../../docs/oseasy-agent-protocol.md`](../../docs/oseasy-agent-protocol.md).

This is a **clean-room re-implementation** built from the documented protocol. It
copies no vendor code, ships no vendor binary, and **bypasses no authentication**.

## Ethics / scope (agreed with the supervisor)

- **Interop only.** We send the plain handshake (`connectionMode` + `clientName`)
  and **do not** send `authString` or run the vendor's "authstring handshake" —
  `authString` is an optional protobuf field. If OSEasy rejects the plain
  handshake or demands `authString`, that is an **authentication barrier**: stop,
  record it in [`../../docs/oseasy-vendor-request.md`](../../docs/oseasy-vendor-request.md),
  do not work around it.
- **Honest identity.** `clientName` is `"ohmarchy-linux-agent"`. We never
  impersonate the vendor's agent name.

## Files

| file | what |
|---|---|
| `frame.py` | link frame codec: 7-byte header (size u32-BE, type u8, checksum u16-BE = sum of the 5 header bytes) + body. Section B of the protocol doc. |
| `pb.py` | hand-rolled protobuf codec (no deps) for `Handshake` / `Call` / `Result` / `CapInfo` / `CapSet`. Section A. |
| `agent.py` | the agent: find the virtio-serial port, open it, handshake, serve/keepalive loop. |
| `tests.py` | unit tests for the two codecs (known-byte vectors + round-trips). `python3 tests.py` |
| `ohmarchy-oseasy-agent.service` | systemd unit for the installed image. |

## Status

Known and unit-tested: the frame format and the message schema.

Resolvable only on-device (marked `TODO(on-device)` in `agent.py`):

1. **Which virtio-serial port** carries the `link` service. The agent matches
   `/sys/class/virtio-ports/*/name` against the host port names
   (`winbox_serial0/1`, `additions_vioser0/1`, …); the right one is confirmed by
   watching which port the host actually drives.
2. **`connectionMode` value and the handshake `msgType`** (the 1-byte frame type,
   0..3). Placeholders are overridable via env (`OSEASY_CONN_MODE`,
   `OSEASY_HS_MSGTYPE`).
3. **The method-id registry** — which `Call.methodID` means keepalive,
   install-complete, CapInfo query, etc. The agent logs every inbound frame so a
   bring-up run can read them off.

On-device testing is scheduled through the supervisor (one VM per host; the box
is shared).

What static analysis settled vs. what the bring-up run must read off:
- `msgType` is the 1-byte frame type = the `type` argument to `LinkBase::SendMessageA`;
  the **event-channel** handshake passes `3`. There is also a command channel. So
  `OSEASY_HS_MSGTYPE` defaults are a starting guess, confirmed on-device.
- `connectionMode` is a **runtime** `std::string` (the static image holds an empty
  SSO string), so its value cannot be read statically — the bring-up run observes
  what OSEasy accepts.
- The **method-id registry** is a numeric dispatch with no descriptive strings, so
  it is not enumerable statically. `agent.py` logs every inbound `Call` (its
  `methodID`, `parameters`) precisely so one bring-up session reads the ids off.

## Getting the agent into the guest

The guest cannot read OSEasy's shared folder (virtiofs `share_id` mode, see the
vendor-request doc), so delivery is one of:

1. **Bring-up (zero change to the demo image) — recommended.** In the guest's
   Omarchy terminal, fetch the three files and run them transiently:
   - if the guest has outbound network, `curl` them from this repo's raw URLs
     (`oseasy/linux-agent/{frame,pb,agent}.py`); otherwise
   - serve them from a tiny HTTP server on the host's tap address and `curl` from
     the guest, or
   - paste them in (they are small).
   Then `python3 agent.py` and watch its log. Nothing is installed — the demo
   image is untouched, so this is the smallest-footprint option for iterating.
2. **Production (after the protocol is confirmed).** Bake `frame.py`, `pb.py`,
   `agent.py` into the image under `/usr/lib/ohmarchy/oseasy-agent/` and enable
   `ohmarchy-oseasy-agent.service` in the ISO build (`oseasy/probe/build.sh`).

Use (1) for every bring-up run; only move to (2) once the handshake + method ids
are confirmed, to keep the published demo ISO stable.

## Test

```sh
cd oseasy/linux-agent && python3 tests.py
```
