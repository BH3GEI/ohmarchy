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

## Gate so far, and what's left to test

Build-time gate confirmed: the VM API is a closed HMS partner module absent from
the public SDK. Remaining question (runtime): with a stub `.d.ts` to compile
against and the real module resolved on-device at runtime, does the vmManager
service accept a debug-signed third-party caller, or reject it by signature /
appId / entitlement? That empirical test (build a minimal HAP, debug-sign,
install, call `createVm`, read the error and hilog) is next; booting a created VM
would need `/data/local/vm.lock`.
