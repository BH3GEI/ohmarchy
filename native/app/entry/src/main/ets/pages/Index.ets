// The Linux desktop fills the window: libohdisp.so draws it into the XComponent and
// handles input. Until the first frame arrives, a status line says what is going on.
interface OhdispModule {
  getStatus(): string;
}

@Entry
@Component
struct Index {
  @State status: string = 'Connecting to Omarchy…';
  private ohdisp?: OhdispModule;
  private timer: number = -1;

  aboutToAppear(): void {
    this.timer = setInterval(() => {
      if (this.ohdisp) {
        this.status = this.ohdisp.getStatus();
      }
    }, 500);
  }

  aboutToDisappear(): void {
    clearInterval(this.timer);
  }

  build() {
    Stack() {
      XComponent({ id: 'ohdisp', type: XComponentType.SURFACE, libraryname: 'ohdisp' })
        .onLoad((ctx?: object) => {
          this.ohdisp = ctx as OhdispModule;
        })
        .width('100%')
        .height('100%')
        .focusable(true)
        .defaultFocus(true)
        .focusOnTouch(true)
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
