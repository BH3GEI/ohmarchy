import { AbilityConstant, UIAbility, Want } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { window } from '@kit.ArkUI';

const DOMAIN = 0x0120;

// Want parameters (aa start ... --pi w 64 --pi h 32): window size in px.
export default class EntryAbility extends UIAbility {
  private w: number = 240;
  private h: number = 48;

  onCreate(want: Want, launchParam: AbilityConstant.LaunchParam): void {
    const p = want.parameters ?? {};
    if (typeof p['w'] === 'number') { this.w = p['w'] as number; }
    if (typeof p['h'] === 'number') { this.h = p['h'] as number; }
  }

  onWindowStageCreate(windowStage: window.WindowStage): void {
    windowStage.loadContent('pages/Index', (err) => {
      if (err.code) {
        hilog.error(DOMAIN, 'vote120', 'loadContent failed: %{public}s', JSON.stringify(err));
        return;
      }
      const win = windowStage.getMainWindowSync();
      win.setWindowBackgroundColor('#00000000');
      win.resize(this.w, this.h).catch(() => {});
      win.moveWindowTo(0, 0).catch(() => {});
      hilog.info(DOMAIN, 'vote120', 'window %{public}dx%{public}d', this.w, this.h);
    });
  }
}
