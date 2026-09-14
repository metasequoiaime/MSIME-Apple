"""Synthetic loopback-only HTTP fixture; never log request bodies or headers."""
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from socketserver import TCPServer
import json
import subprocess
import sys
import threading
import time

errors = []
counts = {}


class Handler(BaseHTTPRequestHandler):
    def log_message(self, *_):
        pass

    def do_POST(self):
        try:
            size = int(self.headers["Content-Length"])
            assert 0 < size < 65536
            body = self.rfile.read(size)
            assert self.headers["Authorization"] == "Bearer fixture-token"
            counts[self.path] = counts.get(self.path, 0) + 1
            if self.path == "/asr":
                assert b"fixture-model" in body and b"RIFF" in body
                assert b"changed-after-snapshot" not in body
                assert b'name="language"\r\n\r\nen\r\n' in body
                response = {"text": "synthetic transcript"}
            else:
                document = json.loads(body)
                assert document["messages"][0]["content"] == "synthetic prompt"
                response = {"choices": [{"message": {"content": "synthetic polished"}}]}
            if self.path == "/polish-timeout":
                time.sleep(6)
            self.send_response(500 if self.path == "/polish-failure" else 200)
            self.end_headers()
            self.wfile.write(json.dumps(response).encode())
        except (BrokenPipeError, ConnectionResetError):
            if self.path != "/polish-timeout":
                errors.append("unexpected disconnected fixture")
        except Exception:
            errors.append("fixture assertion failed")
            self.send_error(500)


class Server(ThreadingHTTPServer):
    def server_bind(self):
        TCPServer.server_bind(self)
        self.server_name = "localhost"
        self.server_port = self.server_address[1]


server = Server(("127.0.0.1", 0), Handler)
threading.Thread(target=server.serve_forever, daemon=True).start()
try:
    result = subprocess.run([sys.argv[1], f"http://127.0.0.1:{server.server_port}"], timeout=20)
    assert result.returncode == 0 and not errors
    assert counts == {"/asr": 3, "/polish": 1, "/polish-failure": 1, "/polish-timeout": 1}
finally:
    server.shutdown()
    server.server_close()
