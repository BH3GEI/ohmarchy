import { AbilityConstant, ConfigurationConstant, UIAbility, Want } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { window } from '@kit.ArkUI';
import { webview } from '@kit.ArkWeb';

const DOMAIN = 0x0D0E;

export default class EntryAbility extends UIAbility {
  onCreate(want: Want, launchParam: AbilityConstant.LaunchParam): void {
    this.context.getApplicationContext().setColorMode(ConfigurationConstant.ColorMode.COLOR_MODE_DARK);
    // DevTools over the device's devtools socket, for measuring the page.
    webview.WebviewController.setWebDebuggingAccess(true);
  }

  onWindowStageCreate(windowStage: window.WindowStage): void {
    windowStage.loadContent('pages/Index', (err) => {
      if (err.code) {
        hilog.error(DOMAIN, 'routel', 'loadContent failed: %{public}s', JSON.stringify(err));
        return;
      }
      windowStage.getMainWindowSync().setWindowKeepScreenOn(true);
    });
  }
}
