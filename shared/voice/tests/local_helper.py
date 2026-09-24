"""End-to-end check of msime-voice-local against a real runtime and an installed model.

usage: local_helper.py <msime-voice-local> <runtime library> <model directory>

Speaks the stdin/stdout protocol from shared/voice/README.md with the recording the model ships in test_wavs (or, when the installer dropped it, a second of silence) and requires a final answer. The transcript itself is not compared: that would pin a model's output, not this code's behaviour.
"""
import base64
import json
import subprocess
import sys
import wave
from pathlib import Path

helper, runtime, model = sys.argv[1:4]
recordings = sorted(Path(model).glob("test_wavs/*.wav"))
if recordings:
    with wave.open(str(recordings[0])) as recording:
        assert recording.getframerate() == 16000 and recording.getnchannels() == 1 and recording.getsampwidth() == 2
        pcm = recording.readframes(recording.getnframes())
else:
    pcm = b"\0\0" * 16000

process = subprocess.Popen([helper, "--runtime", runtime, "--idle-exit", "30"], stdin=subprocess.PIPE, stdout=subprocess.PIPE, text=True)


def send(message):
    process.stdin.write(json.dumps(message) + "\n")
    process.stdin.flush()


def receive():
    line = process.stdout.readline()
    assert line, "helper exited early"
    return json.loads(line)


hello = receive()
assert hello["type"] == "hello" and hello["available"], hello
send({"op": "start", "id": 7, "model": model, "language": "zh-CN", "hotwords": ["流式识别", "GitHub"]})
started = receive()
assert started == {"type": "started", "id": 7}, started
chunk = 3200 * 2
for offset in range(0, len(pcm), chunk):
    send({"op": "audio", "pcm16": base64.b64encode(pcm[offset : offset + chunk]).decode()})
send({"op": "finish"})
partials = 0
while True:
    message = receive()
    if message["type"] == "partial":
        partials += 1
        continue
    assert message["type"] == "final" and message["id"] == 7, message
    break
if recordings:
    assert message["text"], "a real recording produced no text"
    print(f"final after {partials} partials: {message['text']}")

# A second session reuses the loaded model; cancelling it answers "cancelled".
send({"op": "start", "id": 8, "model": model})
assert receive()["type"] == "started"
send({"op": "cancel"})
assert receive() == {"type": "cancelled", "id": 8}
process.stdin.close()
assert process.wait(timeout=30) == 0
