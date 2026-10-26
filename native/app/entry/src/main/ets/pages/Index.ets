// The Linux desktop fills the window: libohdisp.so draws it into the XComponent and
// handles input. Until the first frame arrives, a status line says what is going on.
import { hilog } from '@kit.PerformanceAnalysisKit';
import { startJl } from '../jl/jl';

interface OhdispModule {
  getStatus(): string;
  setForeground(fg: boolean): void;
  swipe(phase: number, dx: number, dy: number, fingers: number): void;
}

@Entry
@Component
struct Index {
  @State status: string = 'Connecting to Omarchy…';
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

  aboutToAppear(): void {
    if (AppStorage.get<boolean>('jl') === true) { startJl(); }
    this.timer = setInterval(() => {
      if (this.ohdisp) {
        this.status = this.ohdisp.getStatus();
      }
    }, 500);
  }

  aboutToDisappear(): void {
    clearInterval(this.timer);
  }

  // In front again: if the desktop went away meanwhile, the native side asks for
  // a new one (and the status overlay covers the old picture until it is there).
  onPageShow(): void {
    this.ohdisp?.setForeground(true);
  }

  onPageHide(): void {
    this.ohdisp?.setForeground(false);
  }

  build() {
    Stack() {
      XComponent({ id: 'ohdisp', type: XComponentType.SURFACE, libraryname: 'ohdisp', controller: this.xc })
        .onLoad((ctx?: object) => {
          this.ohdisp = ctx as OhdispModule;
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
      if (this.status.length > 0) {
        Column() {
          Text(this.status)
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
