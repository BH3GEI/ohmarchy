import { UIAbility } from '@kit.AbilityKit';
import { window } from '@kit.ArkUI';
import { hilog } from '@kit.PerformanceAnalysisKit';
import jl from 'libjl.so';

const CMD: string =
  'echo ===J-START===; ' +
  'echo pipe: $(ls / | wc -l) entries in /; ' +
  'echo pid=$$; ' +
  '{ sleep 1 & echo bg_pid=$!; wait; }; ' +
  'echo cmdsub=$(ls /data 2>/dev/null | wc -l); ' +
  'for i in 1 2 3; do echo loop$i; done; ' +
  'echo ===J-END===';

export default class EntryAbility extends UIAbility {
  onCreate(): void {
    hilog.info(0xBEEF, 'JLOADER', 'onCreate -> runBusybox');
    try {
      const r: number = (jl as Record<string, Object>)['runBusybox'] !== undefined
        ? (jl.runBusybox(CMD) as number) : -1;
      hilog.info(0xBEEF, 'JLOADER', 'runBusybox returned %{public}d', r);
    } catch (e) { hilog.error(0xBEEF, 'JLOADER', 'threw %{public}s', (e as Error)?.message); }
  }
  onWindowStageCreate(ws: window.WindowStage): void { ws.loadContent('pages/Index', () => {}); }
}
