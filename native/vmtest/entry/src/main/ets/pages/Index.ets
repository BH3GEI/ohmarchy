import { probeResult } from '../entryability/EntryAbility';

@Entry
@Component
struct Index {
  @State msg: string = 'VM API probe';

  aboutToAppear(): void {
    setTimeout(() => { this.msg = probeResult; }, 2500);
  }

  build() {
    Column() {
      Text('VM-API runtime probe')
        .fontSize(22).fontWeight(FontWeight.Bold).margin(12)
      Text(this.msg)
        .fontSize(14).margin(12).textAlign(TextAlign.Start)
      Button('re-read result').margin(12)
        .onClick(() => { this.msg = probeResult; })
    }.width('100%').height('100%')
  }
}
