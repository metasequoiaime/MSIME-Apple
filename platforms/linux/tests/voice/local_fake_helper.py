"""A stand-in for msime-voice-local speaking its JSON-lines protocol, for the Linux voice service tests.

Environment:
  FAKE_HELPER_AVAILABLE=0  report the runtime missing in hello
  FAKE_HELPER_LOG=<file>   append every request (audio as its byte count) as a JSON line
  FAKE_HELPER_FINAL=<text> the final transcript (default 水杉输入法)
A start whose model ends in "/broken" answers an error; audio after "crash" in the model path exits the process.
"""
import base64
import json
import os
import sys


def emit(message):
    sys.stdout.write(json.dumps(message, ensure_ascii=False) + "\n")
    sys.stdout.flush()


def log(message):
    path = os.environ.get("FAKE_HELPER_LOG")
    if path:
        with open(path, "a", encoding="utf-8") as output:
            output.write(json.dumps(message, ensure_ascii=False) + "\n")


def main():
    available = os.environ.get("FAKE_HELPER_AVAILABLE", "1") == "1"
    emit({"type": "hello", "version": 1, "available": available,
          "error": "" if available else "libsherpa-onnx-c-api.so: cannot open shared object file"})
    session = None
    model = ""
    received = 0
    for line in sys.stdin:
        message = json.loads(line)
        op = message.get("op")
        if op == "audio":
            data = base64.b64decode(message["pcm16"])
            log({"op": "audio", "bytes": len(data), "pid": os.getpid()})
        else:
            log(dict(message, pid=os.getpid()))
        if op == "start":
            session = message.get("id")
            model = message.get("model", "")
            received = 0
            if model.endswith("/broken"):
                emit({"type": "error", "id": session, "message": "no recognizer in " + model})
                session = None
                continue
            emit({"type": "started", "id": session})
        elif op == "audio" and session is not None:
            if "crash" in model:
                sys.exit(3)
            received += len(data)
            # One partial per second of audio: the whole transcript so far, as the helper reports it.
            if received // 32000 != (received - len(data)) // 32000:
                emit({"type": "partial", "id": session, "text": "听到%d秒" % (received // 32000)})
        elif op == "finish" and session is not None:
            emit({"type": "final", "id": session, "text": os.environ.get("FAKE_HELPER_FINAL", "水杉输入法")})
            session = None
        elif op == "cancel" and session is not None:
            emit({"type": "cancelled", "id": session})
            session = None
        elif op == "ping":
            emit({"type": "pong", "id": message.get("id"), "available": available})


if __name__ == "__main__":
    main()
