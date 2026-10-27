# OSEasy guest-agent ("oeTool") protocol

Reverse-engineered 2026-10-27 from the OSEasy app (`com.oseasy1.ohvm`) for the
**disk-persistence** goal: make a Linux VM boot back into the already-installed
system (OSEasy shows "开机"), instead of OSEasy's only option being 再次安装,
which wipes `/dev/vda` and reinstalls. The end product is a minimal, compatible
**Linux** guest agent — a compatibility re-implementation for our own machines.
We do not modify OSEasy and do not forge any Huawei signature.

## Where the protocol lives

- `entry.hap` → `ets/modules.abc` (ArkTS bytecode, compiled with ark 13.0.1.0 —
  DevEco's bundled `ark_disasm` is older and cannot parse it; use `strings`) and
  `resources/rawfile/oetool.iso`.
- `oetool.iso` is the Windows guest tool disk OSEasy mounts into the guest
  (as the `unattend` cdrom). Its `agent_service.exe` is the Windows guest agent
  and the authoritative source for the wire protocol. It is built from
  `D:\oseasy\harmony_VM_develop\vmagentservice\`.
- Other oetool.iso payloads: `OEToolsetup.exe`, `setup/{oobe,pe,specialize}.bat`
  (Windows OOBE install of the agent + virtio drivers), `config/*.json`,
  `driver/driver0/viostor` (Windows virtio-blk), `display/` (display agent),
  `share_folder.reg`.

(Binaries are kept out of the repo; they are preserved locally under
`~/oseasy-work/oetool-re/`.)

## Transport: virtio-serial

The agent talks to OSEasy over **virtio-serial** (vioserial), not TCP. The
Windows agent opens the ports and exposes them as named pipes:

| pipe (Windows) | role |
|---|---|
| `\\.\PIPE\VM_SYSTEM_SERVICE_COMMU` | command channel (`IService::CreateChannel`) |
| `\\.\PIPE\WIN_EVENT` | event channel (`EstablishEventChannel`) |
| `\\.\PIPE\PERF_COMM` | performance/preload |

Code path: `COMMON::MsgSock::WindowsSerialInit` → `COMMON::Service::HandleConnectSerial`
→ `IService::CreateChannel` + `IService::EstablishEventChannel` (with a
handshake step: "before/after handshake"). Log lines: `open serial port {} success`,
`Cannot find vioserial device, will retry`, `EstablishEventServer failed serial port = {}`.

On a Linux guest the equivalent is the virtio-console char device
`/dev/vportNpX`, matched by port **name** via `/sys/class/virtio-ports/*/name`.
The host side names the ports in its StratoVirt command line (observed:
`winbox_serial0`, `winbox_serial1`, `clipboard_vioser0`, `gfscl`,
`additions_vioser0`, `additions_vioser1`). Mapping those names to
VM_SYSTEM_SERVICE_COMMU / WIN_EVENT is an open item (stage-3 C).

## Wire protocol: Protobuf RPC

Messages are **Google Protobuf** over `COMMON::MsgSock`, framed with a header
(`parse header: size=`, fields `_packetSize` + `_msgType`) and checksummed
(`serial checksum invalid!` / `checksum not match!`). Embedded `.proto` files:
`Guest.proto`, `guest2host.proto`, `host2guest.proto`, `message_info.proto`.

Two protobuf packages:

- **`Guest.protobuf.link`** — transport / handshake: `Handshake`, `CapInfo`,
  `CapSet`, `Call` (the RPC envelope), `IpVersion`.
- **`Guest.protobuf.GuestAgent`** — services / payloads:
  - `CapInfo` / `CapSet` — capability negotiation.
  - `NetInfo`, `NicInfo`, `NicIpAddrInfo`, `DNSInfo`, `ProxyInfo`,
    `NetshPortForwardInfo` — network / Internet-Connection-Sharing (ICS, the
    `[NET::ICS] nic share` feature, public/private NIC bridging).
  - `UserProfileInfo` (+ `SharedInfoEntry`) — shared-folder / user profile.
  - `ResolutionInfo` — display resolution.
  - `TimeInfo` — time sync. `UpdateInfo` — agent self-update.
  - `HostIdentityInfo`, `GuestMemMonitorInfo`, `DialogInfo`, `DtMessage`.
  - generic wrappers `Bool`, `Bytes`, `Integer`, `String`.

Handshake: once a channel is up, exchange `link.Handshake` carrying
`CapInfo`/`CapSet` (the agent advertises its `AgentServiceCapSet`); on success
the host treats the agent as ready.

Shutdown commands/notifications: `GUEST_FORCESHUTDOWN`, `GUEST_QUICKSTART_SHUTDOWN`
("ForceShutdown guest").

## OSEasy (HarmonyOS) side — the state machine

From `modules.abc`:

- Agent state: `isOEToolInstalled`, `oeToolKeepalive` (heartbeat;
  `set/clear keepalive timer`), `vmOeToolVersion`, `oeToolCdromStatus`,
  `getVmStatus` via `virtualization.getVmStatus('com.oseasy1.ohvm')`.
- Install state: `install_complete`, `WAIT_INSTALL_COMPLETE`,
  `isFirstUsePreInstallVm`, `handlePreInstallSuccess`, page
  `pages/PreinstalledConfiguration`.
- VM lifecycle states: `STATE_STOPPED`, `STATE_RUNNING`, `STATE_VIEWING`
  (also `VM_STATE_NOT_RUNNING`). The boot-from-stopped entry is the action
  `vm.action.startVirtApp.VM_STATE_STOPPED`, delivered to the off-screen
  `Null2Ability` (manifest `skills`), surfaced by the desktop card
  `VmFormAbility`. Result actions: `vm.action.startVirtApp.SUCCESS` /
  `.VM_STATE_ERROR` / `.OTHER_VM_RUNNING` / `.FILE_CANNOT_SHARE`.
- Shared folders: `UserDirectorySharedToVM`, `enableGuestDiskShared`,
  `isVirtAppsSharedEnabled`, `switchVmNetworkShare`, `sendOeSharedFile`,
  `ECommonSharedFolderPathMap` (virtiofs, `tag=shared_dir`, registered through
  the vm_manager `virtiofs-cmd.sock`).

## Minimal Linux agent — plan

1. Open the correct virtio-serial port(s) (`/dev/vportNpX`, matched by the
   VM_SYSTEM_SERVICE_COMMU / WIN_EVENT port names).
2. Perform `link.Handshake` (reply with `CapInfo`/`CapSet`); bring up the
   command and event channels.
3. Send `oeToolKeepalive` on the host's expected interval.
   → OSEasy sets `isOEToolInstalled` + `install_complete`, so the VM persists as
   `STATE_STOPPED` and OSEasy offers 开机 instead of 再次安装.
4. Later: shared folders via `UserProfileInfo`/`SharedInfoEntry` + the virtiofs
   `share_id` registration, so `~/Shared` is read/write.

Ship it as a systemd service baked into the image.

## Stage-3 progress

- **A — DONE.** The embedded `FileDescriptorProto`s were carved out of
  `agent_service.exe` and decoded with `protoc`; the full schema is at
  `~/oseasy-work/oetool-re/proto/schema-decoded.txt` (+ the `.fd` blobs). Key
  messages, with field numbers:
  - `guest2host.proto` (`Guest.protobuf.link`): `Call{callID:1 u32, methodID:2
    u32, parameters:3 bytes, async:4 bool}`, `Result{callID:1 u32, response:2
    bytes, errorCode:3 i32}`, `Handshake{connectionMode:1 string, clientName:2
    string, authString:3 bytes}`, `AuthResult{result:1 bytes}`, `CapInfo`,
    `CapSet`, `ErrorCode{code:1 i32}`, `Void`, `PerfMsg`, `StabilityEvent`,
    `VmNetProxyInfo`, `VmNetMacInfo`.
  - `host2guest.proto` (`Guest.protobuf.GuestAgent`): `Bool/Bytes/Integer/String`,
    `UpdateInfo`, `NicIpAddrInfo`, `NicInfo`, `NetInfo`, `DtMessage`, `TimeInfo`.

- **B — partial.** The link layer is `COMMON::MsgSock` (`Create`, `Recv`, `Send`,
  `ReadTimed`, `DropLeftData`, `GetPortFromDevicePath`, `WindowsSerialInit`) with
  `COMMON::LinkBase::SerializeAndResponse`. A frame is a header (`_packetSize` +
  `_msgType`, "parse header: size=") + a protobuf body (a `link.Call`/`Result`) +
  a checksum ("receive data error: checksum mismatch"). The exact header byte
  layout and the checksum algorithm still need disassembly of `MsgSock::Recv`/
  `Send` (the "bad magic number" strings are allocator debug noise, not a frame
  magic).

- **C — partial.** The host channel is the vioserial device, opened via
  `MsgSock::GetPortFromDevicePath` / `Service::HandleConnectSerial`. Windows names
  the pipes `\\.\PIPE\VM_SYSTEM_SERVICE_COMMU` (command) and `\\.\PIPE\WIN_EVENT`
  (event). On the host the virtserialports are named (StratoVirt cmdline)
  `winbox_serial0/1`, `clipboard_vioser0`, `gfscl`, `additions_vioser0/1`; the
  exact pipe-name ↔ port-name mapping needs disassembly of
  `GetPortFromDevicePath`. Linux side: match by `/sys/class/virtio-ports/*/name`.

B and C need a PE disassembler (string analysis is exhausted). Deferred while the
native-desktop route is the top priority.
