"""Doubao streaming transport, based on MSIME-Windows b21a1671.

No request, audio, transcript, credential, or remote error body is logged.
"""
import gzip
import json
import logging
import queue
import socket
import struct
import threading
import time
import uuid
import zlib


CHUNK_BYTES = 6400  # 200ms of 16kHz signed 16-bit mono PCM.
MAX_RESPONSE = 1024 * 1024


def websocket_dependency():
    from importlib.metadata import version
    if version("websockets").split(".")[0] != "15":
        raise ValueError("Doubao requires websockets 15.x")
    from websockets.sync.client import ClientConnection, connect
    return ClientConnection, connect


def packet(kind, flags, sequence, payload):
    compressed = gzip.compress(payload, mtime=0)
    return bytes((0x11, kind << 4 | flags, 0x11, 0)) + struct.pack(
        ">iI", sequence, len(compressed)) + compressed


def parse_response(message):
    if not isinstance(message, bytes) or not 4 <= len(message) <= MAX_RESPONSE:
        raise ValueError("invalid Doubao message")
    header = (message[0] & 15) * 4
    if message[0] >> 4 != 1 or header < 4 or header > len(message):
        raise ValueError("invalid Doubao header")
    kind, flags = message[1] >> 4, message[1] & 15
    serialization, compression = message[2] >> 4, message[2] & 15
    offset = header + (4 if flags & 1 else 0) + (4 if flags & 4 else 0)
    if kind == 15:
        # Do not expose the server's diagnostic body to logs or the host.
        raise ValueError("Doubao rejected request")
    if kind != 9 or offset + 4 > len(message) or serialization != 1:
        raise ValueError("invalid Doubao response")
    length = struct.unpack_from(">I", message, offset)[0]
    offset += 4
    if length != len(message) - offset:
        raise ValueError("truncated Doubao payload")
    payload = message[offset:]
    if compression == 1:
        decoder = zlib.decompressobj(16 + zlib.MAX_WBITS)
        payload = decoder.decompress(payload, MAX_RESPONSE + 1)
        if (len(payload) > MAX_RESPONSE or not decoder.eof or
            decoder.unconsumed_tail or decoder.unused_data):
            raise ValueError("invalid or oversized Doubao gzip")
    elif compression != 0:
        raise ValueError("unsupported Doubao compression")
    value = json.loads(payload)
    body = value.get("payload_msg", value)
    result = body.get("result", {})
    text = result.get("text", "")
    if not isinstance(text, str):
        raise ValueError("invalid Doubao transcript")
    return text, bool(flags & 2)


def request_body(options):
    request = {"model_name": "bigmodel", "result_type": "full", "show_utterances": False}
    for key, default in (("enable_itn", True), ("enable_punc", True), ("enable_ddc", False)):
        value = options.get("doubao_" + key, default)
        if type(value) is not bool:
            raise ValueError("invalid Doubao option")
        request[key] = value
    boosting = options.get("doubao_boosting_table_id", "")
    if not isinstance(boosting, str) or len(boosting.encode()) > 512:
        raise ValueError("invalid Doubao boosting table")
    if boosting:
        request["corpus"] = {"boosting_table_id": boosting}
    return json.dumps({"user": {"uid": "metasequoia-ime"},
                       "audio": {"format": "pcm", "codec": "raw", "rate": 16000,
                                 "bits": 16, "channel": 1},
                       "request": request}).encode()


class DoubaoStream:
    def __init__(self, config, options, cancelled):
        self.config = config
        self.initial = request_body(options)
        self.cancelled = cancelled
        self.closed = threading.Event()
        self.done = threading.Event()
        self.audio = queue.Queue(maxsize=50)  # At most ten seconds awaiting upload.
        self.pending = bytearray()
        self.lock = threading.Lock()
        self.transport = None
        self.text = ""
        self.failed = False
        self.worker = threading.Thread(target=self.run, daemon=True)
        self.worker.start()

    def feed(self, chunk):
        if self.cancelled.is_set() or self.closed.is_set() or self.done.is_set():
            return
        self.pending.extend(chunk)
        while len(self.pending) >= CHUNK_BYTES:
            self.audio.put_nowait((bytes(self.pending[:CHUNK_BYTES]), False))
            del self.pending[:CHUNK_BYTES]

    def latest(self):
        with self.lock:
            if self.failed:
                raise ValueError("Doubao recognition failed")
            return self.text

    def finish(self, tick):
        if not self.done.is_set() and not self.cancelled.is_set():
            final = bytes(self.pending[:len(self.pending) // 2 * 2])
            self.pending.clear()
            self.audio.put_nowait((final, True))
        deadline = time.monotonic() + 30
        while not self.done.wait(0.1):
            if self.cancelled.is_set() or time.monotonic() >= deadline:
                self.close()
                if self.cancelled.is_set():
                    return ""
                raise TimeoutError("Doubao final response timeout")
            tick()
        return "" if self.cancelled.is_set() else self.latest()

    def close(self):
        self.closed.set()
        with self.lock:
            transport = self.transport
        if transport:
            # Interrupt a blocked send without waiting for the send lock or
            # a WebSocket close handshake. TLS still owns certificate checks.
            try:
                transport.shutdown(socket.SHUT_RDWR)
            except OSError:
                pass
        self.worker.join(timeout=12)

    def run(self):
        try:
            connection_type, connect = websocket_dependency()
            headers = {"X-Api-Resource-Id": self.config["resource_id"],
                       "X-Api-Request-Id": str(uuid.uuid4())}
            if self.config.get("app_key"):
                headers.update({"X-Api-App-Key": self.config["app_key"],
                                "X-Api-Access-Key": self.config["token"]})
            else:
                headers["X-Api-Key"] = self.config["token"]
            logger = logging.Logger("msime.voice.doubao")
            logger.disabled = True
            logger.propagate = False

            def connection_factory(sock, protocol, **kwargs):
                with self.lock:
                    self.transport = sock
                if self.closed.is_set() or self.cancelled.is_set():
                    sock.close()
                    raise ValueError("cancelled")
                return connection_type(sock, protocol, **kwargs)

            # The synchronous client rejects unsuccessful upgrades; it doesn't
            # follow redirects with these endpoint-bound authentication headers.
            with connect(self.config["endpoint"], additional_headers=headers,
                         user_agent_header="MSIME-Client", open_timeout=10,
                         close_timeout=1, ping_interval=10, ping_timeout=10,
                         max_size=MAX_RESPONSE, max_queue=4, compression=None,
                         logger=logger, create_connection=connection_factory) as websocket:
                if self.cancelled.is_set() or self.closed.is_set():
                    return
                websocket.send(packet(1, 1, 1, self.initial))
                sequence = 2
                finish_deadline = None
                last_response = time.monotonic()
                while not self.closed.is_set() and not self.cancelled.is_set():
                    if finish_deadline is None:
                        try:
                            chunk, final = self.audio.get(timeout=0.05)
                        except queue.Empty:
                            pass
                        else:
                            websocket.send(packet(2, 3 if final else 1, -sequence if final else sequence, chunk))
                            sequence += 1
                            if final:
                                finish_deadline = time.monotonic() + 30
                    # Drain replies while recording instead of waiting until
                    # the final audio frame, preserving live inline preedit.
                    for _ in range(8):
                        try:
                            message = websocket.recv(timeout=0.05 if finish_deadline else 0)
                        except TimeoutError:
                            break
                        text, final = parse_response(message)
                        last_response = time.monotonic()
                        if text:
                            with self.lock:
                                self.text = text
                        if final:
                            return
                    now = time.monotonic()
                    if (finish_deadline is not None and now >= finish_deadline) or now - last_response >= 30:
                        raise TimeoutError("Doubao response timeout")
        except Exception:
            if not self.cancelled.is_set() and not self.closed.is_set():
                with self.lock:
                    self.failed = True
        finally:
            with self.lock:
                self.transport = None
            self.done.set()
