#!/usr/bin/env python3
"""A JSON null read out of org.json must be tested with isNull, not given a fallback.

`optString(name, fallback)` returns the fallback only when the key is absent. When the key is
present and holds `JSONObject.NULL` it returns the four-letter string "null", because org.json
stringifies the null sentinel before deciding whether to fall back. `JSONArray.optString(index,
fallback)` behaves the same way.

The shared runtime uses JSON null for "there is nothing here", so every one of these reads is
pointed straight at the case that misbehaves. The smart-punctuation decision document says
`replace_with: null` when a punctuation key should just be typed; the host read it with a null
fallback, found a non-empty string, and did what a real replacement asks for - delete the character
before the cursor and commit the replacement. Every punctuation key deleted a character and typed
`null`. On an empty field a comma produced `null`; after 你好 it produced 你null.

Nothing caught it. It compiles, the JVM smokes cannot construct org.json, and the shape is
indistinguishable from correct code until a document with an explicit null reaches it on a device.
"""
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SOURCES = sorted((ROOT / "platforms/android/java").rglob("*.java"))

READ = re.compile(r"\.optString\([^;]*,\s*null\s*\)")
# The guard may sit on the line above when the conditional is wrapped, which is how the
# repository's own correct sites read.
WINDOW = 2

findings = []
for source in SOURCES:
    lines = source.read_text().split("\n")
    for index, line in enumerate(lines):
        if not READ.search(line):
            continue
        window = "\n".join(lines[max(0, index - WINDOW) : index + 1])
        if ".isNull(" in window:
            continue
        findings.append((source.relative_to(ROOT), index + 1, line.strip()))

if findings:
    for path, number, text in findings:
        print(f"{path}:{number}: optString with a null fallback and no isNull guard: {text}")
    sys.exit(
        'org.json returns the string "null" for a JSON null rather than the fallback; '
        "test the key with isNull first"
    )

guarded = sum(1 for source in SOURCES for line in source.read_text().split("\n") if READ.search(line))
if guarded < 1:
    sys.exit("expected the host to read optional JSON strings; found none to check")
print(f"android json null reads: {guarded} null-fallback reads, all guarded by isNull")
