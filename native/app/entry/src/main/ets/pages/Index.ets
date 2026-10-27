// The Linux desktop fills the window: libohdisp.so draws it into the XComponent and
// handles input. Until the first frame arrives, a status line says what is going on.
import { hilog } from '@kit.PerformanceAnalysisKit';
import { promptAction, window } from '@kit.ArkUI';
import { startJl } from '../jl/jl';

interface OhdispModule {
  getStatus(): string;
  setForeground(fg: boolean): void;
  swipe(phase: number, dx: number, dy: number, fingers: number): void;
  releaseKeys(): void;
  sandboxCtl(cmd: string): Promise<string>;
  gpuRetry(): void;
  takeMinimize(): boolean;
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
  private sandbox: boolean = false;
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
        this.ohdisp?.gpuRetry();
      }
      return ok;
    });
  }

  // from the icon's "Reset Linux" shortcut (EntryAbility): confirm, reset, start again
  onResetRequested(): void {
    if (!this.sandbox || this.resetRequested === 0) {
      return;
    }
    promptAction.showDialog({
      title: 'Reset Linux?',
      message: 'Everything installed or changed inside Linux is lost; it goes back to how it was installed.',
      buttons: [{ text: 'Cancel', color: '#c0caf5' }, { text: 'Reset', color: '#f7768e' }]
    }).then((r: promptAction.ShowDialogSuccessResponse) => {
      if (r.index === 1) {
        this.sandboxCtl('reset', 'Resetting Linux…')
          .then((ok: boolean) => ok ? this.startLinux() : false);
      }
    }).catch(() => {});
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
          if (this.sandbox) {
            this.startLinux().then(() => this.onResetRequested());
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
