// The Linux desktop fills the window: libohdisp.so draws it into the XComponent and
// handles input. Until the first frame arrives, a status line says what is going on.
import { hilog } from '@kit.PerformanceAnalysisKit';
import { promptAction, router, window } from '@kit.ArkUI';
import { common } from '@kit.AbilityKit';
import { startJl } from '../jl/jl';

interface OhdispModule {
  getStatus(): string;
  setForeground(fg: boolean): void;
  swipe(phase: number, dx: number, dy: number, fingers: number): void;
  releaseKeys(): void;
  sandboxCtl(cmd: string): Promise<string>;
  gpuRetry(): void;
  takeMinimize(): boolean;
  setWindowId(id: number): void;
}

// The sandbox build (native/sandbox/build-app.sh) runs Linux through the helper
// ohm-sandboxd: start when the app opens, stop when it closes, reset on request.
const SANDBOX_BUNDLE = 'com.ohmarchy.sandbox';

@Entry
@Component
struct Index {
  @State status: string = 'Connecting to Omarchy…';
  // the sandbox helper's word while Linux starts or resets; shown over the status
  @State note: string = '';
  @StorageLink('resetRequested') @Watch('onResetRequested') resetRequested: number = 0;
  @StorageLink('settingsRequested') @Watch('onSettingsRequested') settingsRequested: number = 0;
  private sandbox: boolean = false;
  private started: boolean = false;  // Linux started by this app
  private ohdisp?: OhdispModule;
  private xc: XComponentController = new XComponentController();
  private timer: number = -1;
  private swipeX: number = 0;
  private swipeY: number = 0;

  // Three-finger touchpad swipes for Hyprland's gestures (workspace switching):
  // deltas since the last event, in px.
  private swipe(phase: number, ev?: GestureEvent): void {
    let dx = 0, dy = 0;
    if (ev) {
      const x = vp2px(ev.offsetX), y = vp2px(ev.offsetY);
      dx = x - this.swipeX;
      dy = y - this.swipeY;
      this.swipeX = x;
      this.swipeY = y;
    }
    if (phase === 0) {
      this.swipeX = 0;
      this.swipeY = 0;
    }
    this.ohdisp?.swipe(phase, dx, dy, 3);
  }

  private sandboxCtl(cmd: string, busy: string): Promise<boolean> {
    if (!this.ohdisp) {
      return Promise.resolve(false);
    }
    this.note = busy;
    return this.ohdisp.sandboxCtl(cmd).then((reply: string) => {
      const ok = reply.startsWith('ok');
      hilog.info(0x0D0D, 'ohdisp', 'sandbox %{public}s: %{public}s', cmd, ok ? 'ok' : reply);
      // on failure the helper's last output says why
      this.note = ok ? '' : 'Linux did not ' + cmd + ':\n' + reply.substring(reply.indexOf('\n') + 1).slice(-400);
      return ok;
    });
  }

  // Linux and its graphics service come up only now: look for that service again
  private startLinux(): Promise<boolean> {
    return this.sandboxCtl('start', 'Starting Linux…').then((ok: boolean) => {
      if (ok) {
        this.started = true;
        this.ohdisp?.gpuRetry();
      }
      return ok;
    });
  }

  // After a reset with the app open: the GPU renderer cannot take a new compositor's
  // window surface in this process (every present then failed to blit, 0x502), while
  // a new process can. So the app restarts itself; the new one starts Linux (already
  // running: a no-op) and shows the new desktop, as when the app is opened.
  private afterReset(): void {
    try {
      const ctx = getContext(this) as common.UIAbilityContext;
      ctx.getApplicationContext().restartApp({ bundleName: SANDBOX_BUNDLE, abilityName: 'EntryAbility' });
    } catch (e) {
      hilog.error(0x0D0D, 'ohdisp', 'restart after reset: %{public}s', JSON.stringify(e));
      this.startLinux().then(() => {
        this.note = 'Linux was reset. Close and open the app to see it.';
      });
    }
  }

  // from the icon's "权限设置" shortcut while the desktop is open: the settings page on top
  onSettingsRequested(): void {
    if (this.sandbox && this.settingsRequested !== 0) {
      router.pushUrl({ url: 'pages/Settings' });
    }
  }

  // from the icon's "Reset Linux" shortcut (EntryAbility): ask first; reset and start
  // only when confirmed (opened by the shortcut, nothing starts before the answer)
  onResetRequested(): void {
    if (!this.sandbox || this.resetRequested === 0 || !this.ohdisp) {
      return;
    }
    this.note = 'Reset Linux?';
    promptAction.showDialog({
      title: 'Reset Linux?',
      message: 'Everything installed or changed inside Linux is lost; it goes back to how it was installed.',
      buttons: [{ text: 'Cancel', color: '#c0caf5' }, { text: 'Reset', color: '#f7768e' }]
    }).then((r: promptAction.ShowDialogSuccessResponse) => {
      if (r.index === 1) {
        this.sandboxCtl('reset', 'Resetting Linux…').then((ok: boolean) => {
          if (ok) {
            this.afterReset();
          }
        });
      } else if (!this.started) {
        this.startLinux();
      } else {
        this.note = '';
      }
    }).catch(() => {
      if (!this.started) {
        this.startLinux();
      }
    });
  }

  aboutToAppear(): void {
    this.sandbox = getContext(this).applicationInfo.name === SANDBOX_BUNDLE;
    if (AppStorage.get<boolean>('jl') === true) { startJl(); }
    // Losing the focus releases the keys still pressed in the desktop: HarmonyOS
    // keeps the Super key's release (its start menu opens then and takes the focus).
    window.getLastWindow(getContext(this)).then((w: window.Window) => {
      w.on('windowEvent', (t: window.WindowEventType) => {
        if (t === window.WindowEventType.WINDOW_INACTIVE || t === window.WindowEventType.WINDOW_HIDDEN) {
          this.ohdisp?.releaseKeys();
        }
      });
      // The sandbox build is a whole desktop: it opens in full screen (EntryAbility),
      // and the title bar's maximize (or a double click on it) only maximizes, with
      // the title bar and the Dock still there. Maximized from a window means "back
      // to full screen"; maximized on the way down from full screen (the title bar's
      // restore) stays as the user asked, so a window can still be had.
      if (this.sandbox) {
        let last: window.WindowStatusType = window.WindowStatusType.FULL_SCREEN;
        w.on('windowStatusChange', (st: window.WindowStatusType) => {
          hilog.info(0x0D0D, 'ohdisp', 'window status %{public}d (was %{public}d)', st, last);
          if (st === window.WindowStatusType.MAXIMIZE && last === window.WindowStatusType.FLOATING) {
            w.maximize(window.MaximizePresentation.ENTER_IMMERSIVE).catch((e: object) =>
              hilog.error(0x0D0D, 'ohdisp', 'full screen: %{public}s', JSON.stringify(e)));
          }
          last = st;
        });
      }
    });
    this.timer = setInterval(() => {
      if (this.ohdisp) {
        this.status = this.ohdisp.getStatus();
        // the sandbox build's Ctrl+Alt+Escape: out of full screen, to the desktop
        if (this.ohdisp.takeMinimize()) {
          window.getLastWindow(getContext(this)).then((w: window.Window) => w.minimize());
        }
      }
    }, 500);
  }

  aboutToDisappear(): void {
    clearInterval(this.timer);
    if (this.sandbox) {
      this.ohdisp?.sandboxCtl('stop');  // the app closes: Linux stops with it
    }
  }

  // In front again: if the desktop went away meanwhile, the native side asks for
  // a new one (and the status overlay covers the old picture until it is there).
  onPageShow(): void {
    this.ohdisp?.setForeground(true);
  }

  onPageHide(): void {
    this.ohdisp?.releaseKeys();
    this.ohdisp?.setForeground(false);
  }

  build() {
    Stack() {
      XComponent({ id: 'ohdisp', type: XComponentType.SURFACE, libraryname: 'ohdisp', controller: this.xc })
        .onLoad((ctx?: object) => {
          this.ohdisp = ctx as OhdispModule;
          // the desktop's cursor becomes this window's pointer (cursor.cpp)
          window.getLastWindow(getContext(this)).then((w: window.Window) => {
            this.ohdisp?.setWindowId(w.getWindowProperties().id);
          });
          if (this.sandbox) {
            if (this.resetRequested !== 0) {
              this.onResetRequested();  // opened by "Reset Linux": ask before anything starts
            } else {
              this.startLinux();
            }
          }
          // For experiments with presenting into this window from another process
          // (route I, docs/vm-own.md): its surface id.
          hilog.info(0x0D0D, 'ohdisp', 'xcomponent surface id %{public}s', this.xc.getXComponentSurfaceId());
        })
        .width('100%')
        .height('100%')
        .focusable(true)
        .defaultFocus(true)
        .focusOnTouch(true)
        .gesture(PanGesture({ fingers: 3, distance: 5 })
          .onActionStart((ev: GestureEvent) => this.swipe(0))
          .onActionUpdate((ev: GestureEvent) => this.swipe(1, ev))
          .onActionEnd((ev: GestureEvent) => this.swipe(2, ev))
          .onActionCancel(() => this.swipe(3)))
      if (this.status.length > 0 || this.note.length > 0) {
        Column() {
          Text(this.note.length > 0 ? this.note : this.status)
            .fontColor('#c0caf5')
            .fontSize(16)
            .textAlign(TextAlign.Center)
            .padding(24)
        }
        .width('100%')
        .height('100%')
        .justifyContent(FlexAlign.Center)
        .backgroundColor('#1a1b26')
        .hitTestBehavior(HitTestMode.Transparent)
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor('#1a1b26')
  }
}
