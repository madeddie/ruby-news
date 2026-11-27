#!/usr/bin/env python3
import json
import os
from http.server import BaseHTTPRequestHandler, HTTPServer
from urllib.parse import urlparse, parse_qs, unquote
from urllib.request import Request, urlopen
from urllib.error import URLError
from readability import Document

PORT = int(os.environ.get("PORT", 5000))
UA = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36"


class Handler(BaseHTTPRequestHandler):
    def log_message(self, format, *args):
        pass

    def do_GET(self):
        parsed = urlparse(self.path)

        if parsed.path == "/health":
            self._json(200, {"ok": True})
            return

        if parsed.path != "/extract":
            self._json(404, {"error": "not found"})
            return

        params = parse_qs(parsed.query)
        url = unquote(params.get("url", [None])[0] or "")
        if not url:
            self._json(400, {"error": "missing url parameter"})
            return

        try:
            req = Request(url, headers={"User-Agent": UA})
            with urlopen(req, timeout=15) as resp:
                html = resp.read().decode("utf-8", errors="replace")
        except URLError as e:
            self._json(502, {"error": "fetch failed: " + str(e)})
            return
        except Exception as e:
            self._json(502, {"error": str(e)})
            return

        doc = Document(html)
        self._json(200, {"title": doc.title(), "content": doc.summary()})

    def _json(self, status, data):
        body = json.dumps(data).encode()
        self.send_response(status)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)


if __name__ == "__main__":
    server = HTTPServer(("0.0.0.0", PORT), Handler)
    print(f"Readability service listening on :{PORT}", flush=True)
    server.serve_forever()
