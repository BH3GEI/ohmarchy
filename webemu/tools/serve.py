#!/usr/bin/env python3
"""Serve the route L page on a desktop for comparison runs: webemu/web, webemu/vendor
and webemu/image/out on one origin, with HTTP Range (v86's async disk needs it) and
the same config.json the app generates.  Usage: serve.py [port]  (default 8086)"""
import http.server, json, os, re, sys
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
DIRS = [os.path.join(ROOT, d) for d in ("web", "vendor", "image/out")]
TYPES = {".html": "text/html", ".js": "text/javascript", ".css": "text/css", ".wasm": "application/wasm"}

class H(http.server.BaseHTTPRequestHandler):
    def do_GET(self):
        name = self.path.split("?")[0].lstrip("/") or "index.html"
        if name == "config.json":
            img = os.path.join(ROOT, "image/out/arch32.img")
            return self.send(200, json.dumps({"disk_size": os.path.getsize(img), "disk_from": "serve.py", "memory_mb": 512}).encode(), "application/json")
        for d in DIRS:
            p = os.path.join(d, os.path.basename(name))
            if os.path.isfile(p):
                break
        else:
            return self.send(404, b"not found", "text/plain")
        size = os.path.getsize(p)
        m = re.match(r"bytes=(\d+)-(\d*)", self.headers.get("Range", ""))
        start, end = (int(m.group(1)), min(int(m.group(2)) if m.group(2) else size - 1, size - 1)) if m else (0, size - 1)
        with open(p, "rb") as f:
            f.seek(start)
            data = f.read(end - start + 1)
        extra = {"Content-Range": f"bytes {start}-{end}/{size}"} if m else {}
        self.send(206 if m else 200, data, TYPES.get(os.path.splitext(p)[1], "application/octet-stream"), extra)

    def send(self, code, data, ctype, extra={}):
        self.send_response(code)
        self.send_header("Content-Type", ctype)
        self.send_header("Content-Length", str(len(data)))
        self.send_header("Accept-Ranges", "bytes")
        self.send_header("Cache-Control", "no-store")
        for k, v in extra.items():
            self.send_header(k, v)
        self.end_headers()
        self.wfile.write(data)

    def log_message(self, *a):
        pass

http.server.ThreadingHTTPServer(("127.0.0.1", int(sys.argv[1]) if len(sys.argv) > 1 else 8086), H).serve_forever()
