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

## Test

```sh
cd oseasy/linux-agent && python3 tests.py
```
