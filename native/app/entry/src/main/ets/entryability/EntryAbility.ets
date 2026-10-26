import { AbilityConstant, ConfigurationConstant, UIAbility, Want } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { window } from '@kit.ArkUI';

const DOMAIN = 0x0D0D;

export default class EntryAbility extends UIAbility {
  onCreate(want: Want, launchParam: AbilityConstant.LaunchParam): void {
    this.context.getApplicationContext().setColorMode(ConfigurationConstant.ColorMode.COLOR_MODE_DARK);
    const jlp: Object | undefined = want?.parameters?.['jl'];
    AppStorage.setOrCreate('jl', jlp === true || jlp === 'true');
    const imp: Object | undefined = want?.parameters?.['immersive'];
    AppStorage.setOrCreate('immersive', imp === true || imp === 'true');
  }

  onWindowStageCreate(windowStage: window.WindowStage): void {
    windowStage.loadContent('pages/Index', (err) => {
      if (err.code) {
        hilog.error(DOMAIN, 'ohdisp', 'loadContent failed: %{public}s', JSON.stringify(err));
        return;
      }
      // Experiment (--pb immersive true): immersive full screen, to see whether
      // HarmonyOS still opens its start menu on the Super key then.
      if (AppStorage.get<boolean>('immersive') === true) {
        windowStage.getMainWindow().then((w: window.Window) => {
          w.maximize(window.MaximizePresentation.ENTER_IMMERSIVE).catch((e: object) =>
            hilog.error(DOMAIN, 'ohdisp', 'maximize: %{public}s', JSON.stringify(e)));
          try {
            w.setImmersiveModeEnabledState(true);
          } catch (e) {
            hilog.error(DOMAIN, 'ohdisp', 'immersive: %{public}s', JSON.stringify(e));
          }
          hilog.info(DOMAIN, 'ohdisp', 'immersive full screen requested');
        });
      }
      // Opens as a normal window; maximize it from the title bar for the full desktop.
      // No keep-screen-on: the screen times out and locks as HarmonyOS decides,
      // as with any other app.
    });
  }
}
