// Route L: an ArkWeb page running v86 (x86 emulator, guest code JIT-compiled to
// WebAssembly) with Arch Linux 32. Everything is served to the page under
// https://routel.local/ by onInterceptRequest: the page, scripts and the BIOS from
// rawfile, and the disk image with byte ranges, from the app sandbox
// (files/arch32.img) if present, else from rawfile.
import { webview } from '@kit.ArkWeb';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { fileIo as fs } from '@kit.CoreFileKit';
import { common } from '@kit.AbilityKit';
import { resourceManager } from '@kit.LocalizationKit';

const DOMAIN = 0x0D0E;
const TAG = 'routel';
const ORIGIN = 'https://routel.local/';
const DISK = 'arch32.img';

const MIME: Record<string, string> = {
  'html': 'text/html', 'js': 'text/javascript', 'css': 'text/css', 'json': 'application/json',
  'wasm': 'application/wasm',
};

class Disk {
  fd: number = -1;
  base: number = 0;
  size: number = 0;
  where: string = '';
}

@Entry
@Component
struct Index {
  controller: webview.WebviewController = new webview.WebviewController();
  private ctx: common.UIAbilityContext = getContext(this) as common.UIAbilityContext;
  private disk: Disk = new Disk();
  private cache: Map<string, ArrayBuffer> = new Map();

  aboutToAppear(): void {
    this.openDisk();
  }

  openDisk(): void {
    const local = this.ctx.filesDir + '/' + DISK;
    try {
      if (fs.accessSync(local)) {
        const f = fs.openSync(local, fs.OpenMode.READ_ONLY);
        this.disk.fd = f.fd;
        this.disk.size = fs.statSync(local).size;
        this.disk.where = local;
      }
    } catch (e) {
      hilog.warn(DOMAIN, TAG, 'sandbox disk: %{public}s', JSON.stringify(e));
    }
    if (this.disk.fd < 0) {
      try {
        const d: resourceManager.RawFileDescriptor = this.ctx.resourceManager.getRawFdSync(DISK);
        this.disk.fd = d.fd;
        this.disk.base = d.offset;
        this.disk.size = d.length;
        this.disk.where = 'rawfile';
      } catch (e) {
        hilog.error(DOMAIN, TAG, 'no disk image: %{public}s', JSON.stringify(e));
      }
    }
    hilog.info(DOMAIN, TAG, 'ROUTEL disk %{public}s size %{public}d', this.disk.where, this.disk.size);
  }

  rawfile(name: string): ArrayBuffer | undefined {
    let b = this.cache.get(name);
    if (b === undefined) {
      try {
        const u8: Uint8Array = this.ctx.resourceManager.getRawFileContentSync('web/' + name);
        b = u8.buffer.slice(u8.byteOffset, u8.byteOffset + u8.byteLength) as ArrayBuffer;
        this.cache.set(name, b);
      } catch (e) {
        return undefined;
      }
    }
    return b;
  }

  respond(code: number, mime: string, data: ArrayBuffer | string, headers: Array<Header>): WebResourceResponse {
    const r = new WebResourceResponse();
    r.setResponseCode(code);
    r.setReasonMessage(code === 206 ? 'Partial Content' : code === 200 ? 'OK' : 'Not Found');
    r.setResponseMimeType(mime);
    r.setResponseEncoding('utf-8');
    headers.push({ headerKey: 'Access-Control-Allow-Origin', headerValue: '*' });
    headers.push({ headerKey: 'Cache-Control', headerValue: 'no-store' });
    r.setResponseHeader(headers);
    r.setResponseData(data);
    r.setResponseIsReady(true);
    return r;
  }

  serveDisk(req: WebResourceRequest): WebResourceResponse {
    let range = '';
    for (const h of req.getRequestHeader()) {
      if (h.headerKey.toLowerCase() === 'range') {
        range = h.headerValue;
      }
    }
    const m = /bytes=(\d+)-(\d*)/.exec(range);
    const size = this.disk.size;
    let start = 0;
    let end = size - 1;
    if (m) {
      start = Number(m[1]);
      if (m[2].length > 0) {
        end = Math.min(Number(m[2]), size - 1);
      }
    }
    const len = Math.max(0, end - start + 1);
    const buf = new ArrayBuffer(len);
    let got = 0;
    while (got < len) {
      const n = fs.readSync(this.disk.fd, buf, { offset: this.disk.base + start + got, length: len - got });
      if (n <= 0) {
        break;
      }
      got += n;
    }
    const hs: Array<Header> = [
      { headerKey: 'Accept-Ranges', headerValue: 'bytes' },
      { headerKey: 'Content-Length', headerValue: String(len) },
    ];
    if (m) {
      hs.push({ headerKey: 'Content-Range', headerValue: `bytes ${start}-${end}/${size}` });
    }
    return this.respond(m ? 206 : 200, 'application/octet-stream', buf, hs);
  }

  intercept(req: WebResourceRequest): WebResourceResponse | null {
    const url = req.getRequestUrl();
    if (!url.startsWith(ORIGIN)) {
      return null;
    }
    let name = url.substring(ORIGIN.length).split('?')[0];
    if (name === '') {
      name = 'index.html';
    }
    if (name === DISK) {
      return this.serveDisk(req);
    }
    if (name === 'config.json') {
      const cfg = `{"disk_size":${this.disk.size},"disk_from":"${this.disk.where}","memory_mb":512}`;
      return this.respond(200, 'application/json', cfg, []);
    }
    const b = this.rawfile(name);
    if (b === undefined) {
      return this.respond(404, 'text/plain', 'not found', []);
    }
    const ext = name.substring(name.lastIndexOf('.') + 1);
    return this.respond(200, MIME[ext] ?? 'application/octet-stream', b, []);
  }

  build() {
    Column() {
      Web({ src: ORIGIN + 'index.html', controller: this.controller })
        .width('100%')
        .height('100%')
        .javaScriptAccess(true)
        .domStorageAccess(true)
        .fileAccess(false)
        .defaultFocus(true)
        .onInterceptRequest((event) => {
          if (!event) {
            return null;
          }
          try {
            return this.intercept(event.request);
          } catch (e) {
            hilog.error(DOMAIN, TAG, 'intercept: %{public}s', JSON.stringify(e));
            return null;
          }
        })
        .onConsole((event) => {
          if (event) {
            hilog.info(DOMAIN, TAG, '%{public}s', event.message.getMessage());
          }
          return false;
        })
        .onRenderExited((event) => {
          hilog.error(DOMAIN, TAG, 'ROUTEL render exited %{public}d', event?.renderExitReason ?? -1);
        })
    }
    .width('100%')
    .height('100%')
    .backgroundColor('#111111')
  }
}
