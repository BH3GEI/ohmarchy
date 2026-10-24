import { UIAbility } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
export default class VMConsoleAbility extends UIAbility {
  onCreate(): void { hilog.info(0xBEEF, 'VMPROBE', 'VMConsoleAbility onCreate'); }
}
