import { AbilityConstant, UIAbility, Want } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { window } from '@kit.ArkUI';

const DOMAIN = 0x0120;

// Want parameters (aa start ... --pi w 64 --pi h 32 --pi x 0 --pi y 0 --pi draw 0):
// window size and position in px; draw 0 keeps the vote (frame callback) but
// presents no buffers, so the window need not take a composition layer.
export default class EntryAbility extends UIAbility {
  private w: number = 240;
  private h: number = 48;
  private x: number = 0;
  private y: number = 0;

  onCreate(want: Want, launchParam: AbilityConstant.LaunchParam): void {
    const p = want.parameters ?? {};
    if (typeof p['w'] === 'number') { this.w = p['w'] as number; }
    if (typeof p['h'] === 'number') { this.h = p['h'] as number; }
    if (typeof p['x'] === 'number') { this.x = p['x'] as number; }
    if (typeof p['y'] === 'number') { this.y = p['y'] as number; }
    AppStorage.setOrCreate('draw', p['draw'] !== 0);
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
      win.moveWindowTo(this.x, this.y).catch(() => {});
      hilog.info(DOMAIN, 'vote120', 'window %{public}dx%{public}d at %{public}d,%{public}d', this.w, this.h, this.x, this.y);
    });
  }
}
