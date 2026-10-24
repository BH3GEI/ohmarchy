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

## Runtime test (option A): build a stub, debug-sign, install, call `createVm`

Supervisor-approved 2-hour empirical test. Minimal probe app `com.ohmarchy.vmtest`
(`native/vmtest/`): `EntryAbility.onCreate` calls `virtualization.getVmAvailableCpuNumRange()`
then `virtualization.createVm('com.ohmarchy.vmtest', …)` — **create only, never `startVm`**
(the device's `vm_manager` is simultaneously running the 鸿融 main VM), and `destroyVm` to
clean up if a VM is actually created.

Gates cleared so far:

1. **Build-time gate — PASSED with a stub.** The public DevEco SDK ships no
   `@hms.virtService.vmManager` (195 `@hms.*` d.ts, none virt/vm). Dropping a hand-written
   stub `.d.ts` (`native/vmtest/stub/`, reverse-engineered from the abc) into
   `sdk/default/hms/ets/api/` lets hvigor resolve the import and the HAP compiles. So the
   closed SDK is **not** an absolute barrier — a third party can compile against the API
   with a stub.
2. **Install gate — PASSED.** The HAP, signed with the OpenHarmony **test** keys + a debug
   provisioning profile bound to the device UDID (not an AppGallery cert), installs via
   `bm install -r`: `appProvisionType=debug`, `appDistributionType=none`. Declaring/importing
   the VM API does not block install.

Remaining (the real question): **does the runtime `vm_manager` service accept this
debug-signed, non-AppGallery caller, or reject it** (expected: `UNTRUSTED_CALLER`, i.e. a
signature/appId gate)? Launch the probe, read `hilog` for the `VMPROBE` verdict and any
`vm_manager`/`virt_service` rejection reason. Launch foregrounds a window briefly, so it
waits for `/data/local/screen.lock`; create-only needs no `vm.lock`. Result pending.

