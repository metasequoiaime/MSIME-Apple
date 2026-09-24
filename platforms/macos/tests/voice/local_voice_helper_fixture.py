#!/usr/bin/env python3
"""A stand-in for msime-voice-local that speaks its stdin/stdout protocol without a model.

LocalVoiceRequestTest points MSIME_VOICE_LOCAL_HELPER here. The session's language picks a behaviour, so each case drives one helper path:
- anything else: one partial per audio message counting the samples so far, and on finish a final naming the sample count and the hotwords the start carried;
- "exit": the process exits as soon as audio arrives, as a crashed helper would;
- "error": the start fails the way a model that will not load does.
Every request line is appended to the file named by MSIME_LOCAL_VOICE_FIXTURE_LOG, so the test can check what was sent after the request is gone.
"""
import base64
import json
import os
import sys

log_path = os.environ.get("MSIME_LOCAL_VOICE_FIXTURE_LOG")


def emit(message):
    sys.stdout.write(json.dumps(message, ensure_ascii=False) + "\n")
    sys.stdout.flush()


emit({"type": "hello", "version": 1, "available": True, "error": ""})
session = None
for line in sys.stdin:
    message = json.loads(line)
    if log_path:
        with open(log_path, "a", encoding="utf-8") as log:
            log.write(json.dumps({key: value for key, value in message.items() if key != "pcm16"}) + "\n")
    op = message.get("op")
    if op == "start":
        if message.get("language") == "error":
            emit({"type": "error", "id": message["id"], "message": "synthetic model failure"})
            continue
        session = {"id": message["id"], "samples": 0, "hotwords": message.get("hotwords", []), "language": message.get("language")}
        emit({"type": "started", "id": message["id"]})
    elif op == "audio" and session:
        if session["language"] == "exit":
            sys.exit(3)
        pcm = base64.b64decode(message["pcm16"])
        assert len(pcm) % 2 == 0
        session["samples"] += len(pcm) // 2
        emit({"type": "partial", "id": session["id"], "text": f"partial {session['samples']}"})
    elif op == "finish" and session:
        emit({"type": "final", "id": session["id"], "text": f"final {session['samples']} {','.join(session['hotwords'])}".strip()})
        session = None
    elif op == "cancel" and session:
        emit({"type": "cancelled", "id": session["id"]})
        session = None
