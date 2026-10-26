# Can a third-party HarmonyOS app create VMs without root?

Goal: find out whether a normal (non-system, non-root) HarmonyOS app can use the
system VM service (`@hms:virtService.vmManager` / `@ohos.virtualization`) to
create and boot a VM — the way OSEasy (`com.oseasy1.ohvm`) and 铠大师
(`com.sanway.ecoengine`) do. If so, Route C's dev image and a no-root self-built
VM (Route I) need no root. Investigated on ohdev (MateBook 14, HM740, HarmonyOS 7.0).

## What OSEasy and 铠大师 actually are (read-only, `bm dump`)

Both are ordinary AppGallery apps, not system apps:

| | com.oseasy1.ohvm | com.sanway.ecoengine |
|---|---|---|
| appDistributionType | app_gallery | app_gallery |
| appProvisionType | release | release |
| isSystemApp | false | false |
| bundleType | 0 (app) | 0 (app) |
| appIdentifier | 5765880207855186917 | 5765880207853281933 |

**No virtualization permission.** Their `requestPermissions` are all ordinary
`ohos.permission.*` (ACCESS_USER_FULL_DISK, CAMERA, FILE_ACCESS_PERSIST,
GET_NETWORK_INFO, INTERNET, MICROPHONE, READ_WRITE_DOWNLOAD_DIRECTORY, …). There
is **no** `MANAGE_VM` or any virtualization/vm permission in either manifest.

**They declare a `VirtualAbility`.** In `module.json` each has an extension
ability named `VirtualAbility` (`srcEntrance ./ets/vmability/VMAbility.ets`,
`extensionAbilityType: 255`). 255 is an internal/unspecified extension type not
in the public SDK's extension-type enum; the whole VM UI is a set of type-255
extension abilities (InstallAbility, VMAbility, WinAppAbility, …).

## The API is a closed HMS module

Strings in OSEasy's installed `entry.hap` show it imports **`@hms:virtService.vmManager`**
and calls `createVm()`, plus a `virtualization` namespace
(`virtualization.getVmDiskSize`, `.mountUSBToVm`, `.unmountCDDriveFromVm`, …) and
`createVmApplicationForm(...)`.

This module is **not in the public DevEco SDK**:

- `sdk/default/openharmony/{js,ets}/api` has no `@ohos.virtualization`,
  `vmManager`, `virtService` or `createVm` declaration.
- `sdk/hms` exists but is empty (0 `.d.ts`): the HMS SDK component that would
  carry `@hms:virtService.*` is not shipped/installed.

So a third-party developer cannot `import` `@hms:virtService.vmManager` with the
standard toolchain — hvigor cannot resolve it. OSEasy/铠大师 have it as AppGallery
VM partners with access to the restricted HMS SDK (and likely an entitlement).

## Not gated by the static container whitelist

`/system/etc/virt_service/` has bundle allowlists — `brokers/bms/hmos_bms_config.json`
and `hmos_fusion_manager/hmos_fusion_config.json` — but they list Huawei's own
bundles (dataclone, databackup, sceneboard, hisuite) and a few fusion/abroad
apps, for the container (rgm/isula) and fusion paths. Neither OSEasy nor 铠大师 is
in them, yet both create VMs, so the VM (`vmManager`) path is **not** gated by
that static allowlist. The caller check is in `libvm_manager` itself
(`GetAppIdByCallingUid`, `caller identity validation failed`).

## Reverse-engineered API surface (from OSEasy's `ets/modules.abc`)

`strings` on `com.oseasy1.ohvm`'s `ets/modules.abc` gives the real call shape:

- module specifier **`@hms:virtService.vmManager`** (compiled form of `@hms.virtService.vmManager`)
- a **`virtualization`** namespace: `createVm(bundleName, config)`, `startVm(bundleName, …)`,
  `stopVm`, `pauseVm`, `resumeVm`, `destroyVm(bundleName)`, `getVmAvailableCpuNumRange()`,
  `getVmDiskSize`/`setVmDiskSize`, `mountUSBToVm`/`unmountUSBFromVm`, `addSharedFolder`,
  `sendDataToVm`, `on/off('vmViewStateChange'|'vmMemoryChange')`
- plus `createVmApplicationForm('entry','VmFormAbility','VmForm')` for the VM form card.

Crucially the abc also contains the constants **`UNTRUSTED_CALLER` / `untrusted_caller`**,
`callerBundleName`, `publisherBundleName`, `hasPermissions` — so the VM service **validates
the calling app's identity** and has a dedicated "untrusted caller" rejection.

## Runtime test (option A): build a stub, debug-sign, install, call the API

Supervisor-approved empirical test. Minimal probe app `com.ohmarchy.vmtest`
(`native/vmtest/`), **create-only, never `startVm`** (the device's `vm_manager` was
simultaneously running the 鸿融 main VM), with `destroyVm` cleanup. Built against a
hand-written stub `.d.ts`, signed with the OpenHarmony **test** keys (not an AppGallery
cert), installed with `bm install -r`.

The runtime verdict, layer by layer — every obvious gate is **open** for a debug-signed,
non-AppGallery third-party app, until the service's own authorization check:

| Layer | Result |
|---|---|
| Compile against the closed API | **PASS** with a stub `.d.ts` (hvigor resolves `@hms:virtService.vmManager`) |
| Install the debug-signed HAP | **PASS** (`appProvisionType=debug`, `appDistributionType=none`) |
| Load the closed module at runtime | **PASS** — the module resolves and loads; all ~80 `virtualization.*` functions are enumerable (`Object.keys`) |
| Reach the VM service over IPC | **PASS** — `getVmStatus('com.ohmarchy.vmtest')` returns `0` (STATE_STOPPED) with no error |
| Privileged query | **DENIED** — `getVmAvailableCpuNumRange()`/`getVmAvailableMemorySizeRange()` return `[201,…]`, `getHostSN()` throws **`201 Permission denied`** |
| `createVm(bundle, minimalCfg)` | `401` = **`VM_ERROR_INVALID_PARAM`** (reaches the module; config rejected) |
| `createVm(bundle, fullCfg)` | resolves (no throw) but **no VM is created** — no new entry under `/data/service/*/vm_manager`, no `stratovirt`, 鸿融 untouched |

`VmErrorCode = {VM_OK:0, VM_ERROR_INVALID_PARAM:401, VM_ERROR_IPC_FAILED:403, VM_ERROR_NULLPTR:404}`
— so the `401` is a **parameter** error, not a permission error. Enums also recovered:
`VmState`, `VmStartType {START,MEMORY_SNAPSHOT_RESUME,FORCE_START}`,
`StorageType {TYPE_VIRTIO,TYPE_USB}`, `NetMode {MODE_BRIDGE,MODE_NAT}`, `Feature {…}`.

### Where the gate is

Not the SDK, not install, not module-load, not IPC reachability. The gate is the VM
service's **caller-authorization check on privileged operations** (`libvm_manager`'s
`GetAppIdByCallingUid` + "caller identity validation", with the `UNTRUSTED_CALLER`
constant seen in OSEasy's abc). A plain debug-signed third-party app is refused the
privileged calls (`201`) and cannot actually create a VM.

OSEasy/铠大师 pass this check **without declaring any VM permission** — their full manifests
request only ordinary `ohos.permission.*`, and `applicationInfo.permissions` is empty. The
only things they have that an ordinary app does not are (a) an **AppGallery release
signature / appId** (a VM partner identity) and (b) a cluster of **type-255 extension
abilities** (`VirtualAbility`, `VMConsoleAbility`, `WinAppAbility`, `VmFormAbility`,
`StatusBarAbility`). So authorization is tied to the app's **identity**, not to a
grantable permission a third party could simply request.
### The authorization mechanism (from `libvm_manager.z.so`)

Pulled `/system/lib64/libvm_manager.z.so` (the VM-service SA) and analysed it. The caller
check uses two things:

1. `AccessTokenKit::VerifyAccessToken(tokenId, "ohos.permission.MANAGE_VM")`. `MANAGE_VM`
   is defined (`/system/etc/access_token/permission_definitions.json`) as
   `grantMode: system_grant`, `availableLevel: system_basic`, `availableType: SYSTEM`,
   `provisionEnable: true` — a restricted permission, grantable to a non-system app only
   via an ACL in its signing provisioning profile.
2. `GetAppIdentifier()` — reads the caller's **appIdentifier** (the AppGallery-issued app
   identity) and checks it. Our debug app's `appIdentifier` is **empty**, so
   `GetAppIdentifier can not get appIdentifier` → `permission denied`, logged by the SA for
   every call (even `getVmStatus`; the `0` the client saw was a masked default).

**The decisive finding:** `libvm_manager.z.so` contains a **hardcoded allowlist of eight
appIdentifiers** in `.rodata` (constructed into a global container at library init via
`__cxa_atexit`/`operator new`):

```
5765880207853062833  5765880207853281933*  5765880207854471529  5765880207854951925
5765880207855081199  5765880207855082215   5765880207855186917** 5765880207855187037
```

`*` = 铠大师 (`com.sanway.ecoengine`), `**` = OSEasy (`com.oseasy1.ohvm`) — i.e. the two
known VM apps are on the list. So the gate is **a baked-in partner allowlist, not a
"non-empty appIdentifier" check**.

### Conclusion (final)

A third-party HarmonyOS app **cannot** create or manage VMs via `@hms:virtService.vmManager`
without root, and this is **not** something a developer can unlock themselves:

- Not blocked by the SDK (a stub `.d.ts` compiles), by install (a debug HAP installs), by
  module-load (the closed module loads), or by IPC (the service answers).
- Blocked by the VM service's caller authorization: it requires the system permission
  `ohos.permission.MANAGE_VM` **and** that the caller's **appIdentifier be one of eight
  values hardcoded in `libvm_manager.z.so`**.
- OSEasy/铠大师 work because their AppGallery appIdentifiers are on that hardcoded list — a
  closed Huawei VM-partner program. Declaring the same abilities (`VirtualAbility`, …)
  changes nothing (they are ordinary UIAbilities and were tested: still denied).
- Even a legitimately AGC-signed third-party app (which would have a non-empty
  appIdentifier) would be rejected, because its identifier is not among the eight. The only
  way in is Huawei adding your appIdentifier to `libvm_manager` and shipping it in a system
  update.

**Therefore Route I (a no-root, self-built VM through the system VM service) is not viable
for a non-partner app.** The no-root VM paths that do work (Route C 鸿融, and OSEasy/铠大师
themselves) all rely on an app whose appIdentifier is on Huawei's VM-partner allowlist.

### Reproduction
`native/vmtest/` (probe app, create-only), `native/vmtest/stub/` (the stub `.d.ts`),
`device/vmapi/probe-run.sh` (launch + app/service hilog capture). The allowlist is in
`/system/lib64/libvm_manager.z.so` `.rodata`; the permission in
`/system/etc/access_token/permission_definitions.json`.

## "检测到有其它虚拟机正在运行" / 401 `Not support vm multi-instance` (2026-10-26)

Why OSEasy refused to start during the B demo preparation although no
`stratovirt` ran, from OSEasy's own log
(`/data/app/el2/100/base/com.oseasy1.ohvm/haps/entry/files/applogs/appLog.log`),
StratoVirt's logs (`/data/log/hwf_service/vmlog`, route I's
`/data/local/kaidashi/ownvm/svc/stratovirt.log`) and the persisted hilog
(`/data/log/hilog/hilog.*.gz`, readable with `zcat | strings`). Times CST.

**The dialog is the kit's 401, translated.** In OSEasy's `ets/modules.abc`
the text `检测到有其它虚拟机正在运行，请先将其关闭后再试。` sits in its
error-message table right after the kit's `Not support vm multi-instance.`.
It is not a check of OSEasy's own.

**Three different cases behind it:**

| When | What ran | What happened | Verdict |
|---|---|---|---|
| 03:25:44–51 | 鸿融's main VM (pid 8744, exit 04:23:42) | `createVm` → 401, OSEasy `destroyVm` + retry, four times, then the dialog stays | real refusal: one VM system-wide |
| 05:17:55 (the B demo blocker) | nothing (route I's last VM exited 05:05:02; 鸿融's next one ran 05:25:03–05:32:44, agent-2a's UI power cycle) | no kit call at all: OSEasy's log has only `received new want`, the hilog of 05:11–05:25 no `createVm` or vm_manager call before 05:20 | **stale**: the 03:25 dialog, shown again when OSEasy was brought to the front |
| 05:35:19 | nothing | `createVm` succeeds at once, VM to `STATE_VIEWING` | normal |
| 13:47:04 | nothing (route I's VM exited 13:45:54) | `createVm` → 401, OSEasy `destroyVm('com.oseasy1.ohvm')` + retry → success 3 s later | the kit still held OSEasy's own previous VM object; OSEasy recovers by itself |

So "no stratovirt, yet refused" was not a wrong state in the system service:
the refusal on screen was hours old. The guest power-off of 鸿融's VM is not
involved either (agent-2a, eb4646b: it is logged as `STOPPING` → `STOPPED`, the
same as 强制关机).

**What decides "another VM runs".** `libvm_manager.z.so` (vm_manager SA in
`sa_main`) has `GetActiveVmState`, `GetLxVmStateByUserId`, `HandleSetLxVmState`
and runs `/bin/pgrep -f|-x|-P` (strings); on 2026-10-26 13:20, with nothing
running, those `pgrep` patterns matched no process and vm_manager logged
`lxVmState: 0`.

**Workaround.**
- Before opening OSEasy or 鸿融: no other VM may run (`pidof stratovirt` empty;
  route I's Docker VM stops 3 minutes after the last docker command).
- If OSEasy shows the dialog: it may be old. Close it and press 安装 / 开机
  again once nothing runs; OSEasy destroys its stale VM object and retries by
  itself.
