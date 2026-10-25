import { UIAbility } from '@kit.AbilityKit';
import { window } from '@kit.ArkUI';
import { hilog } from '@kit.PerformanceAnalysisKit';
import xpm from 'libxpm.so';

export default class EntryAbility extends UIAbility {
  onCreate(): void {
    hilog.info(0xBEEF, 'XPMPROBE', 'ability onCreate -> runProbes()');
    try {
      const r: number = (xpm as Record<string, Object>)['runProbes'] !== undefined
        ? (xpm.runProbes() as number) : -1;
      hilog.info(0xBEEF, 'XPMPROBE', 'runProbes returned %{public}d', r);
    } catch (e) {
      hilog.error(0xBEEF, 'XPMPROBE', 'runProbes threw %{public}s', (e as Error)?.message);
    }
  }
  onWindowStageCreate(ws: window.WindowStage): void {
    ws.loadContent('pages/Index', () => {});
  }
}
