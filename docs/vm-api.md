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

### Still pending (to make it airtight)
- The `vm_manager` **service-side** log line for a third-party `createVm` (the exact
  rejection reason), captured during the probe run.
- Whether declaring a `VirtualAbility` (type-255) extension lifts the `201` — if it does,
  the gate is the extension (satisfiable by any third party → no-root VM feasible); if not,
  the gate is the AppGallery signature/appId entitlement (a Huawei VM-partner privilege).

### Bottom line so far
A third party **can** compile, install, load and talk to the VM service without root — but
**cannot create a VM**: the service authorizes privileged VM operations by caller identity
(AppGallery VM-partner signature/appId), not by a permission an ordinary developer can
declare. Route I ("no-root self-built VM") is therefore blocked for a non-partner app at
the service's identity check, pending the two tests above.
