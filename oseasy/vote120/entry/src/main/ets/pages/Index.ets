// ohmarchy-120: a small transparent window whose XComponent votes 120 Hz
// (libvote120.so). Keep it visible next to a window that renders at 120 frames/s
// but does not vote itself (the Oseasy VM). The status line shows the rate the
// window's frame callback actually gets.
interface Vote120Module {
  getStatus(): string;
  setDraw(on: boolean): void;
}

@Entry
@Component
struct Index {
  @State status: string = 'vote 120 Hz';
  private vote?: Vote120Module;
  private timer: number = -1;

  aboutToAppear(): void {
    this.timer = setInterval(() => {
      if (this.vote) {
        this.status = this.vote.getStatus();
      }
    }, 1000);
  }

  aboutToDisappear(): void {
    clearInterval(this.timer);
  }

  build() {
    Stack() {
      XComponent({ id: 'vote120', type: XComponentType.SURFACE, libraryname: 'vote120' })
        .onLoad((ctx?: object) => {
          this.vote = ctx as Vote120Module;
          this.vote.setDraw(AppStorage.get<boolean>('draw') ?? true);
        })
        .width('100%')
        .height('100%')
        .backgroundColor(Color.Transparent)
      Text(this.status)
        .fontColor('#9aa5ce')
        .fontSize(10)
        .backgroundColor(Color.Transparent)
    }
    .width('100%')
    .height('100%')
    .backgroundColor(Color.Transparent)
  }
}
