import { AbilityConstant, ConfigurationConstant, UIAbility, Want } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { window } from '@kit.ArkUI';
import { notificationManager } from '@kit.NotificationKit';

const DOMAIN = 0x0D0D;

export default class EntryAbility extends UIAbility {
  onCreate(want: Want, launchParam: AbilityConstant.LaunchParam): void {
    this.context.getApplicationContext().setColorMode(ConfigurationConstant.ColorMode.COLOR_MODE_DARK);
    const jlp: Object | undefined = want?.parameters?.['jl'];
    AppStorage.setOrCreate('jl', jlp === true || jlp === 'true');
    const imp: Object | undefined = want?.parameters?.['immersive'];
    AppStorage.setOrCreate('immersive', imp === true || imp === 'true');
    this.notify(want);
    this.shortcut(want);
  }

  // The sandbox build's "Reset Linux" shortcut on the icon (want parameter action=reset):
  // the page asks for confirmation.
  private shortcut(want: Want): void {
    if (want?.parameters?.['action'] === 'reset') {
      AppStorage.setOrCreate('resetRequested', Date.now());
    }
  }

  // `aa start -b com.ohmarchy.display -a EntryAbility --ps notify TEXT [--ps notifyTitle T]`:
  // a HarmonyOS notification from the host, e.g. the docker gate's "another VM
  // runs" (`omarchy docker-refused`). The first one asks the user to allow them.
  onNewWant(want: Want, launchParam: AbilityConstant.LaunchParam): void {
    this.notify(want);
    this.shortcut(want);
  }

  private notify(want: Want): void {
    const text: Object | undefined = want?.parameters?.['notify'];
    if (typeof text !== 'string' || text === '') {
      return;
    }
    const t: Object | undefined = want?.parameters?.['notifyTitle'];
    // SOCIAL_COMMUNICATION: the ordinary slot HarmonyOS allows banners for. On
    // ohdev (2026-10-27, the app in front) neither it nor the default slot showed
    // a banner: the notification lands in the notification centre (the bell gets
    // a red dot); banners are the user's per-app notification setting.
    const req: notificationManager.NotificationRequest = {
      id: 1,
      notificationSlotType: notificationManager.SlotType.SOCIAL_COMMUNICATION,
      content: {
        notificationContentType: notificationManager.ContentType.NOTIFICATION_CONTENT_BASIC_TEXT,
        normal: { title: typeof t === 'string' && t !== '' ? t : 'Omarchy', text: text }
      }
    };
    notificationManager.isNotificationEnabled()
      .then((on: boolean) => on ? Promise.resolve() : notificationManager.requestEnableNotification(this.context))
      .then(() => notificationManager.publish(req))
      .then(() => hilog.info(DOMAIN, 'ohdisp', 'notification: %{public}s', text))
      .catch((e: object) => hilog.error(DOMAIN, 'ohdisp', 'notification: %{public}s', JSON.stringify(e)));
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
      // The sandbox build opens maximized, like an app that is a whole desktop.
      if (this.context.applicationInfo.name === 'com.ohmarchy.sandbox') {
        windowStage.getMainWindow().then((w: window.Window) => w.maximize()).catch((e: object) =>
          hilog.error(DOMAIN, 'ohdisp', 'maximize: %{public}s', JSON.stringify(e)));
      }
      // Otherwise it opens as a normal window; maximize it from the title bar.
      // No keep-screen-on: the screen times out and locks as HarmonyOS decides,
      // as with any other app.
    });
  }
}
