// The sandbox build's permission settings (the icon's "权限设置"): the sandbox's
// policy.conf as a form. Read, checked and written only through the helper
// ohm-sandboxd (readpolicy, policycheck, writepolicy), which takes this app's uid
// alone and checks every line again before anything changes; policy.sh's parser then
// decides what the next start applies. Nothing here starts Linux.
import { router, promptAction } from '@kit.ArkUI';
import { common } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import ohdisp from 'libohdisp.so';

const SANDBOX_BUNDLE = 'com.ohmarchy.sandbox';
// the capabilities policy.sh lets the user keep (POL_KEEPABLE), with what they allow
const CAPS: string[][] = [
  ['net_admin', '配置网络设备、路由、防火墙'],
  ['syslog', '读内核日志'],
  ['sys_tty_config', '配置终端设备'],
  ['linux_immutable', '设置不可修改的文件属性'],
  ['perfmon', '性能监控'],
  ['checkpoint_restore', '进程检查点/恢复'],
  ['wake_alarm', '唤醒闹钟'],
  ['block_suspend', '阻止休眠'],
  ['audit_read', '读审计日志'],
];
const DEVS: string[][] = [
  ['fuse', 'FUSE 文件系统（/dev/fuse）'],
  ['net/tun', '虚拟网卡（/dev/net/tun）'],
];
const DIM = '#787c99';
const TEXT = '#c0caf5';
const RED = '#f7768e';

@Entry
@Component
struct Settings {
  @State network: string = 'pasta';
  @State rows: number[] = [];  // share rows (ids); their texts in hosts/insides
  @State caps: string[] = [];
  @State devs: string[] = [];
  @State prefixes: number[] = [];  // abstract_allow rows (ids); texts in prefixText
  @State check: string = '读取中…';
  @State message: string = '';
  @State busy: boolean = false;
  @State advanced: boolean = false;
  private hosts: Map<number, string> = new Map<number, string>();
  private insides: Map<number, string> = new Map<number, string>();
  private prefixText: Map<number, string> = new Map<number, string>();
  private dropExtra: string = '';  // cap_drop_extra: kept as read, not shown
  private nextId: number = 1;

  aboutToAppear(): void {
    this.load();
  }

  private body(reply: string): string {
    const nl = reply.indexOf('\n');
    return nl < 0 ? '' : reply.substring(nl + 1);
  }

  private load(): void {
    ohdisp.sandboxCtl('readpolicy').then((r: string) => {
      if (!r.startsWith('ok')) {
        this.message = '读不到当前设置：' + r;
        return;
      }
      this.parse(this.body(r));
      this.refreshCheck();
    });
  }

  private refreshCheck(): void {
    ohdisp.sandboxCtl('policycheck').then((r: string) => {
      this.check = r.startsWith('ok') || r.startsWith('failed') ? this.body(r) : r;
    });
  }

  private parse(text: string): void {
    const rows: number[] = [];
    const prefixes: number[] = [];
    this.hosts.clear();
    this.insides.clear();
    this.prefixText.clear();
    for (const raw of text.split('\n')) {
      const line = raw.split('#')[0].trim();
      const eq = line.indexOf('=');
      if (eq < 0) {
        continue;
      }
      const key = line.substring(0, eq).trim();
      const words = line.substring(eq + 1).trim().split(' ').filter((w: string) => w.length > 0);
      if (key === 'network' && words.length === 1) {
        this.network = words[0];
      } else if (key === 'share' && words.length === 3) {
        const id = this.nextId++;
        this.hosts.set(id, words[0]);
        this.insides.set(id, words[1]);
        rows.push(id);
      } else if (key === 'cap_keep') {
        this.caps = words;
      } else if (key === 'cap_drop_extra') {
        this.dropExtra = words.join(' ');
      } else if (key === 'dev') {
        this.devs = words;
      } else if (key === 'abstract_allow') {
        for (const w of words) {
          const id = this.nextId++;
          this.prefixText.set(id, w);
          prefixes.push(id);
        }
      }
    }
    this.rows = rows;
    this.prefixes = prefixes;
  }

  // only lines of the policy's own grammar; the helper and policy.sh check them again
  private compose(): string {
    const lines: string[] = ['# written by the settings page', `network = ${this.network}`];
    for (const id of this.rows) {
      const h = (this.hosts.get(id) ?? '').trim();
      const i = (this.insides.get(id) ?? '').trim();
      if (h !== '' || i !== '') {
        lines.push(`share = ${h} ${i} rw`);
      }
    }
    if (this.caps.length > 0) {
      lines.push(`cap_keep = ${this.caps.join(' ')}`);
    }
    if (this.dropExtra !== '') {
      lines.push(`cap_drop_extra = ${this.dropExtra}`);
    }
    if (this.devs.length > 0) {
      lines.push(`dev = ${this.devs.join(' ')}`);
    }
    const p: string[] = [];
    for (const id of this.prefixes) {
      const t = (this.prefixText.get(id) ?? '').trim();
      if (t !== '') {
        p.push(t);
      }
    }
    if (p.length > 0) {
      lines.push(`abstract_allow = ${p.join(' ')}`);
    }
    return lines.join('\n') + '\n';
  }

  private save(restart: boolean): void {
    this.busy = true;
    this.message = '保存中…';
    ohdisp.sandboxCtl('writepolicy', this.compose()).then((r: string) => {
      this.busy = false;
      if (!r.startsWith('ok')) {
        this.message = '没有保存，设置有问题：' + this.body(r).trim();
        return;
      }
      this.check = this.body(r);
      if (!restart) {
        this.message = '已保存。下次打开沙箱时生效。';
        return;
      }
      this.message = '已保存，正在重启沙箱…';
      hilog.info(0x0D0D, 'ohdisp', 'settings: saved, restarting the sandbox');
      // the helper takes requests in order: stop, then the new app process's start
      ohdisp.sandboxCtl('stop').then(() => {
        try {
          const ctx = getContext(this) as common.UIAbilityContext;
          ctx.getApplicationContext().restartApp({ bundleName: SANDBOX_BUNDLE, abilityName: 'EntryAbility' });
        } catch (e) {
          this.message = '已保存，Linux 已停止。请重新打开沙箱。';
        }
      });
    });
  }

  private close(): void {
    if (Number(router.getLength()) > 1) {
      router.back();
    } else {
      (getContext(this) as common.UIAbilityContext).terminateSelf();
    }
  }

  private toggle(list: string[], v: string, on: boolean): string[] {
    const out = list.filter((x: string) => x !== v);
    if (on) {
      out.push(v);
    }
    return out;
  }

  @Builder
  section(title: string, note: string) {
    Column() {
      Text(title).fontSize(16).fontColor(TEXT).fontWeight(FontWeight.Medium)
      if (note !== '') {
        Text(note).fontSize(12).fontColor(DIM).margin({ top: 2 })
      }
    }
    .alignItems(HorizontalAlign.Start)
    .width('100%')
    .margin({ top: 18, bottom: 6 })
  }

  @Builder
  netChoice(value: string, label: string, risky: boolean) {
    Row() {
      Radio({ value: value, group: 'network' })
        .checked(this.network === value)
        .enabled(false)
      Text(label).fontSize(14).fontColor(DIM)
      if (risky) {
        Text(' 高风险').fontSize(12).fontColor(RED)
      }
    }
    .margin({ right: 16 })
  }

  build() {
    Column() {
      Row() {
        Text('沙箱权限设置').fontSize(22).fontColor(TEXT).fontWeight(FontWeight.Bold).layoutWeight(1)
        Button('关闭').onClick(() => this.close())
      }
      .width('100%')
      .margin({ bottom: 8 })

      Scroll() {
        Column() {
          this.section('网络', '本版本里沙箱与本机共用网络（能上网，也能连到本机的服务）；独立网络下一版启用，这一项现在还不起作用。')
          Row() {
            this.netChoice('pasta', '联网', false)
            this.netChoice('off', '断网', false)
            this.netChoice('host', '和本机共享', true)
          }

          this.section('共享本机目录', '沙箱里的 root 能读写这些目录里的所有文件。主机路径要用绝对路径。只读：本机（HongMeng）暂不支持，目前只能读写。')
          ForEach(this.rows, (id: number) => {
            Row() {
              TextInput({ text: this.hosts.get(id) ?? '', placeholder: '本机路径，如 /data/local/tmp/share' })
                .layoutWeight(1)
                .onChange((v: string) => { this.hosts.set(id, v); })
              Text(' → ').fontColor(DIM)
              TextInput({ text: this.insides.get(id) ?? '', placeholder: '沙箱里的路径，如 /mnt/share' })
                .layoutWeight(1)
                .onChange((v: string) => { this.insides.set(id, v); })
              Text(' 读写 ').fontColor(TEXT).fontSize(13)
              Button('删除').onClick(() => {
                this.rows = this.rows.filter((x: number) => x !== id);
              })
            }
            .width('100%')
            .margin({ bottom: 6 })
          }, (id: number) => id.toString())
          Button('+ 添加目录').onClick(() => {
            const r = this.rows.slice();
            r.push(this.nextId++);
            this.rows = r;
          })

          Row() {
            Text(this.advanced ? '▾ 高级' : '▸ 高级').fontSize(16).fontColor(TEXT)
          }
          .width('100%')
          .margin({ top: 18 })
          .onClick(() => { this.advanced = !this.advanced; })

          if (this.advanced) {
            this.section('额外的能力', '默认全部去掉；勾上就让沙箱里的 root 多一项权限。')
            ForEach(CAPS, (c: string[]) => {
              Row() {
                Checkbox({ name: c[0] })
                  .select(this.caps.includes(c[0]))
                  .onChange((on: boolean) => { this.caps = this.toggle(this.caps, c[0], on); })
                Text(`${c[0]}：${c[1]}`).fontSize(13).fontColor(TEXT)
              }
              .width('100%')
            }, (c: string[]) => c[0])

            this.section('额外的设备', '默认只有最少的几个设备。')
            ForEach(DEVS, (d: string[]) => {
              Row() {
                Checkbox({ name: d[0] })
                  .select(this.devs.includes(d[0]))
                  .onChange((on: boolean) => { this.devs = this.toggle(this.devs, d[0], on); })
                Text(d[1]).fontSize(13).fontColor(TEXT)
              }
              .width('100%')
            }, (d: string[]) => d[0])

            this.section('抽象 socket 放行前缀', '多余的一层、不是安全边界：静态程序和沙箱里的 root 能绕过。只填字母、数字和 . _ / -')
            ForEach(this.prefixes, (id: number) => {
              Row() {
                TextInput({ text: this.prefixText.get(id) ?? '', placeholder: '前缀，如 foo-' })
                  .layoutWeight(1)
                  .onChange((v: string) => { this.prefixText.set(id, v); })
                Button('删除').onClick(() => {
                  this.prefixes = this.prefixes.filter((x: number) => x !== id);
                })
              }
              .width('100%')
              .margin({ bottom: 6 })
            }, (id: number) => id.toString())
            Button('+ 添加前缀').onClick(() => {
              const p = this.prefixes.slice();
              p.push(this.nextId++);
              this.prefixes = p;
            })
          }

          this.section('当前实际权限（下次启动时生效的）', '[硬] 由内核强制；[软] 尽力而为；! 表示比默认放宽。')
          Text(this.check)
            .fontFamily('monospace')
            .fontSize(12)
            .fontColor(TEXT)
            .width('100%')
            .padding(10)
            .backgroundColor('#16161e')
            .borderRadius(6)
        }
        .width('100%')
        .alignItems(HorizontalAlign.Start)
      }
      .layoutWeight(1)
      .align(Alignment.Top)  // short content starts at the top, not in the middle
      .scrollBar(BarState.Auto)

      if (this.message !== '') {
        Text(this.message).fontSize(13).fontColor(this.message.startsWith('没有') ? RED : TEXT).margin({ top: 8 })
      }
      Row() {
        Button('保存').enabled(!this.busy).onClick(() => this.save(false)).margin({ right: 12 })
        Button('保存并重启沙箱').enabled(!this.busy).onClick(() => {
          promptAction.showDialog({
            title: '保存并重启沙箱？',
            message: 'Linux 会停下再起来，里面开着的程序都会关掉。',
            buttons: [{ text: '取消', color: TEXT }, { text: '重启', color: RED }]
          }).then((r: promptAction.ShowDialogSuccessResponse) => {
            if (r.index === 1) {
              this.save(true);
            }
          });
        })
      }
      .margin({ top: 10 })
    }
    .width('100%')
    .height('100%')
    .padding(20)
    .backgroundColor('#1a1b26')
  }
}
