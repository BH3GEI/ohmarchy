import { UIAbility } from '@kit.AbilityKit';
import { window } from '@kit.ArkUI';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { virtualization } from '@hms.virtService.vmManager';

const TAG: string = 'VMPROBE';
const DOM: number = 0xBEEF;
const ME: string = 'com.ohmarchy.vmtest';

export let probeResult: string = 'probe not run yet';

async function probe(): Promise<void> {
  // 1) read-only: does the service answer a non-partner caller at all?
  try {
    const range = virtualization.getVmAvailableCpuNumRange();
    hilog.info(DOM, TAG, 'cpuRange OK %{public}s', JSON.stringify(range));
    probeResult = 'cpuRange OK: ' + JSON.stringify(range) + '\n';
  } catch (e) {
    const err = e as Error;
    hilog.error(DOM, TAG, 'cpuRange FAIL %{public}s', JSON.stringify(err));
    probeResult = 'cpuRange FAIL: ' + JSON.stringify(err) + '\n';
  }
  // 2) decisive: createVm as a debug-signed third-party app. CREATE ONLY — never startVm,
  //    because the shared vm_manager is running the 鸿融 main VM right now.
  const cfg: Record<string, Object> = { 'vmName': 'probe', 'cpuNum': 2, 'memSize': 2048 };
  let created = false;
  try {
    const st = await virtualization.createVm(ME, cfg);
    created = true;
    hilog.info(DOM, TAG, 'createVm SUCCESS state=%{public}s', st);
    probeResult += 'createVm SUCCESS: ' + st + '\n';
  } catch (e) {
    const err = e as Error;
    const code: string = String((err as object as Record<string, Object>)?.['code']);
    hilog.error(DOM, TAG, 'createVm FAIL code=%{public}s msg=%{public}s full=%{public}s',
      code, err?.message, JSON.stringify(err));
    probeResult += 'createVm FAIL code=' + code + ' ' + JSON.stringify(err) + '\n';
  }
  // 3) cleanup: if we actually created a VM under OUR bundle, destroy it so nothing lingers.
  if (created) {
    try {
      await virtualization.destroyVm(ME);
      hilog.info(DOM, TAG, 'destroyVm(%{public}s) OK', ME);
      probeResult += 'destroyVm OK\n';
    } catch (e) {
      hilog.error(DOM, TAG, 'destroyVm FAIL %{public}s', JSON.stringify(e as Error));
      probeResult += 'destroyVm FAIL: ' + JSON.stringify(e as Error) + '\n';
    }
  }
}

export default class EntryAbility extends UIAbility {
  onCreate(): void {
    hilog.info(DOM, TAG, 'onCreate; starting probe (create-only, no startVm)');
    probe();
  }
  onWindowStageCreate(windowStage: window.WindowStage): void {
    windowStage.loadContent('pages/Index', (err) => {
      if (err.code) { hilog.error(DOM, TAG, 'loadContent failed %{public}s', JSON.stringify(err)); }
    });
  }
}
