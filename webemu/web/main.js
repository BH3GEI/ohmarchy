// Route L page: Arch Linux 32 in v86, serial console in xterm.js.
// Lines starting with "ROUTEL" go to console.log; the app forwards them to hilog.
"use strict";
const T0 = performance.now();
const ms = () => Math.round(performance.now() - T0);
const log = (...a) => console.log("ROUTEL t=" + ms() + " " + a.join(" "));
const stat = document.getElementById("stat");
const marks = {};
const mark = (name) => { if (!(name in marks)) { marks[name] = ms(); log("mark", name, marks[name]); } };

// --- 1. Engine probe: does this WebView run WebAssembly, and how fast? ---------
// f(n): acc = ((acc + i*i) ^ 7) for i < n, as a hand-assembled wasm module.
const WASM_LOOP = new Uint8Array([
  0x00, 0x61, 0x73, 0x6d, 0x01, 0x00, 0x00, 0x00,
  0x01, 0x06, 0x01, 0x60, 0x01, 0x7f, 0x01, 0x7f,
  0x03, 0x02, 0x01, 0x00,
  0x07, 0x05, 0x01, 0x01, 0x66, 0x00, 0x00,
  0x0a, 0x2b, 0x01, 0x29, 0x01, 0x02, 0x7f,
  0x02, 0x40, 0x03, 0x40,
  0x20, 0x01, 0x20, 0x00, 0x4f, 0x0d, 0x01,
  0x20, 0x02, 0x20, 0x01, 0x20, 0x01, 0x6c, 0x6a, 0x41, 0x07, 0x73, 0x21, 0x02,
  0x20, 0x01, 0x41, 0x01, 0x6a, 0x21, 0x01,
  0x0c, 0x00, 0x0b, 0x0b, 0x20, 0x02, 0x0b,
]);
function jsLoop(n) { let acc = 0; for (let i = 0; i < n; i++) acc = ((acc + Math.imul(i, i)) | 0) ^ 7; return acc; }
function probe() {
  const r = { ua: navigator.userAgent, wasm: typeof WebAssembly === "object",
              cores: navigator.hardwareConcurrency, mem_gb: navigator.deviceMemory };
  const N = 1e8;
  let t = performance.now(); r.js_check = jsLoop(N); r.js_ms = Math.round(performance.now() - t);
  if (r.wasm) {
    try {
      const inst = new WebAssembly.Instance(new WebAssembly.Module(WASM_LOOP));
      inst.exports.f(1000);
      t = performance.now(); r.wasm_check = inst.exports.f(N); r.wasm_ms = Math.round(performance.now() - t);
    } catch (e) { r.wasm_error = String(e); }
  }
  log("probe", JSON.stringify(r));
  return r;
}

// --- 2. Count v86's own JIT: it compiles guest code into wasm modules at runtime
// with WebAssembly.instantiate(bytes, {e: imports}). Each success is a block of
// x86 code turned into native code by the engine's wasm compiler.
const jit = { ok: 0, fail: 0, bytes: 0, first_error: null };
if (typeof WebAssembly === "object") {
  const origInstantiate = WebAssembly.instantiate.bind(WebAssembly);
  WebAssembly.instantiate = function (src, imports) {
    const p = origInstantiate(src, imports);
    if (imports && imports.e && src instanceof Uint8Array) {
      jit.bytes += src.length;
      p.then(() => { jit.ok++; }, (e) => { jit.fail++; if (!jit.first_error) { jit.first_error = String(e); log("jit-fail", e); } });
    }
    return p;
  };
}

// --- 3. Emulator -----------------------------------------------------------------
const P = new URLSearchParams(location.search);
async function main() {
  const pr = probe();
  if (!pr.wasm) { stat.textContent = "this WebView has no WebAssembly (JIT disabled?): v86 cannot run"; return; }
  let cfg = {};
  try { cfg = await (await fetch("config.json")).json(); } catch (e) { log("no config.json", e); }
  const memMB = +(P.get("mem") || cfg.memory_mb || 512);
  const disk = cfg.disk_size || +P.get("disk_size");
  log("config", JSON.stringify(cfg), "mem", memMB);

  const term = new Terminal({ fontSize: +(P.get("font") || cfg.font || 16), scrollback: 5000,
                              theme: { background: "#111111" }, convertEol: false });
  term.open(document.getElementById("term"));
  const fit = () => {
    const el = document.getElementById("term");
    const core = term._core, cw = core._renderService.dimensions.css.cell.width,
          ch = core._renderService.dimensions.css.cell.height;
    if (cw && ch) term.resize(Math.max(40, Math.floor((el.clientWidth - 8) / cw)),
                              Math.max(10, Math.floor((el.clientHeight - 8) / ch)));
  };
  try { fit(); } catch (e) {}
  window.addEventListener("resize", () => { try { fit(); } catch (e) {} });
  term.focus();

  const emulator = window.emulator = new V86({
    wasm_path: "v86.wasm",
    memory_size: memMB << 20,
    vga_memory_size: 2 << 20,
    bios: { url: "seabios.bin" },
    vga_bios: { url: "vgabios.bin" },
    bzimage: { url: "vmlinuz" },
    initrd: { url: "initramfs.img" },
    cmdline: cfg.cmdline || "console=ttyS0,115200 root=/dev/sda rw audit=0 mitigations=off " +
             "tsc=reliable random.trust_cpu=on nowatchdog quiet",
    hda: { url: "arch32.img", async: true, size: disk },
    disable_keyboard: true,
    disable_mouse: true,
    autostart: true,
  });
  emulator.add_listener("emulator-ready", () => mark("emulator_ready"));

  // Serial: guest output to the terminal (batched per frame), keys back.
  let pending = [], tail = "", line = "";
  emulator.add_listener("serial0-output-byte", (b) => {
    if (!pending.length) requestAnimationFrame(() => { term.write(Uint8Array.from(pending)); pending = []; });
    pending.push(b);
    mark("first_serial_byte");
    const c = String.fromCharCode(b);
    tail = (tail + c).slice(-40);
    if (c === "\n") { if (line.startsWith("ROUTEL-BENCH")) log("guest", line.trim()); line = ""; }
    else line += c;
    if (tail.includes("Welcome to")) mark("systemd_banner");
    if (tail.endsWith("login: ")) mark("login_prompt");
    if (/\]# $/.test(tail) && !("shell_prompt" in marks)) {
      mark("shell_prompt");
      // Tell the guest the terminal size once (types one line into the shell).
      emulator.serial0_send(`stty rows ${term.rows} cols ${term.cols}\n`);
      // ?autobench=1 (desktop comparison runs): start the benchmark by itself.
      if (P.get("autobench")) emulator.serial0_send("routel-bench\n");
    }
    if (line === "" && tail.endsWith("ROUTEL-BENCH done\r\n")) mark("bench_done");
  });
  term.onData((d) => emulator.serial0_send(d));
  term.onKey(() => mark("first_key"));
  document.getElementById("bench").onclick = () => { emulator.serial0_send("routel-bench\n"); term.focus(); };

  // Status bar + periodic log: instruction rate (MIPS), JIT blocks, boot marks.
  let lastI = 0, lastT = performance.now(), n = 0;
  setInterval(() => {
    const now = performance.now(), i = emulator.get_instruction_counter();
    let d = i - lastI; if (d < 0) d += 2 ** 32;
    const mips = d / ((now - lastT) * 1000);
    lastI = i; lastT = now;
    const heap = performance.memory ? Math.round(performance.memory.usedJSHeapSize / 1048576) : "?";
    stat.textContent = `v86 + Arch Linux 32 | wasm ${pr.wasm ? "yes" : "NO"} (loop ${pr.wasm_ms} ms, js ${pr.js_ms} ms) | ` +
      `${mips.toFixed(1)} MIPS | jit blocks ${jit.ok} ok / ${jit.fail} failed | ` +
      `prompt ${marks.shell_prompt != null ? (marks.shell_prompt / 1000).toFixed(1) + " s" : "…"} | t ${(ms() / 1000).toFixed(0)} s`;
    if (++n % 5 === 0) log("stat", JSON.stringify({ mips: +mips.toFixed(2), jit_ok: jit.ok, jit_fail: jit.fail,
                                                   jit_kb: Math.round(jit.bytes / 1024), heap_mb: heap, marks }));
  }, 1000);
}
main().catch((e) => { log("fatal", e && e.stack || e); stat.textContent = "error: " + e; });
