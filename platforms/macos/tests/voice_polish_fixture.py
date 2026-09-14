"""Loopback synthetic text fixture; never log request bodies or credentials."""
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
import json
import subprocess
import sys
import threading

errors = []
counts = {}


class Handler(BaseHTTPRequestHandler):
    def log_message(self, *_):
        pass

    def do_POST(self):
        try:
            size = int(self.headers["Content-Length"])
            assert 0 < size < 65536
            data = json.loads(self.rfile.read(size))
            assert self.headers["Authorization"] == "Bearer fixture-token"
            assert data["model"] == "fixture-model"
            assert data["messages"][0]["content"] == "synthetic prompt"
            assert data["messages"][1]["content"] == "<asr_text>\nsynthetic transcript\n</asr_text>"
            counts[self.path] = counts.get(self.path, 0) + 1
            self.send_response(500 if self.path == "/failure" else 200)
            self.end_headers()
            value = "" if self.path == "/empty" else "synthetic polished"
            self.wfile.write(json.dumps({"choices": [{"message": {"content": value}}]}).encode())
        except Exception:
            errors.append("fixture assertion failed")
            self.send_error(500)


server = ThreadingHTTPServer(("127.0.0.1", 0), Handler)
threading.Thread(target=server.serve_forever, daemon=True).start()
try:
    result = subprocess.run([sys.argv[1], f"http://127.0.0.1:{server.server_port}"], timeout=20)
    assert result.returncode == 0 and not errors
    assert counts == {"/polish": 1, "/failure": 1, "/empty": 1}
finally:
    server.shutdown()
    server.server_close()
