import { UIAbility } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
export default class InstallAbility extends UIAbility {
  onCreate(): void { hilog.info(0xBEEF, 'VMPROBE', 'InstallAbility onCreate'); }
}
