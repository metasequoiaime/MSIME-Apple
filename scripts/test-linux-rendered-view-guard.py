#!/usr/bin/env python3
"""Every read of the Linux host's rendered view must be guarded by is_object().

`rendered_view` is JSON null until the first render, and it is reset to null on
every session rebuild - a Chinese/English toggle, a menu override that has no
shared preferences directory to save into, a scheme change. nlohmann's `value()`
throws on null, and a throw inside the key handler is caught by `guarded`, so the
symptom is not a crash: the key is silently dropped and one line goes into the
warning log.

That is what happened to the first letter typed after the Ctrl mode shortcut
opened Chinese input. Sixteen of the eighteen reads in the file already carried
the guard; two did not, and one of those was evaluated before the identity fences
that would have stopped short of it.

This is checked statically because reproducing it needs a live IBus session with
a rebuilt Engine session, which no phase of the local gate has.
"""
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / "platforms/linux/src/core/ClientEngine.cpp"

lines = SOURCE.read_text().split("\n")

# A read is guarded when `rendered_view.is_object()` decided it could happen.
# Conditions and blocks here span several lines, so look at a window ending at
# the read rather than at the line alone: the guard is either in the same
# condition or in the `if` that opened the block the read sits in. A window is
# crude, but the alternative is a C++ parser, and the guard that was missing was
# not within a hundred lines.
WINDOW = 20


def guarded(index: int) -> bool:
    start = max(0, index - WINDOW)
    # Forward as far as the end of this statement, for a guard written after the
    # read inside the same multi-line condition.
    end = index
    while end < len(lines) - 1 and not re.search(r"[;{]\s*$", lines[end]):
        end += 1
    return "rendered_view.is_object()" in "\n".join(lines[start : end + 1])


unguarded = [
    (index + 1, line.strip())
    for index, line in enumerate(lines)
    if "rendered_view.value(" in line and not guarded(index)
]

if unguarded:
    for number, line in unguarded:
        print(f"{SOURCE}:{number}: rendered_view read without is_object(): {line}")
    sys.exit(
        "rendered_view is null until the first render and after every session "
        "rebuild; value() on it throws and the key is dropped"
    )

reads = sum(1 for line in lines if "rendered_view.value(" in line)
if reads < 10:
    sys.exit(f"expected the rendered view to be read throughout the host, found {reads}")
print(f"linux rendered view guard: {reads} reads, all guarded")
