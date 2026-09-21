#!/usr/bin/env python3
"""No merge-conflict markers anywhere in the tracked tree.

The pre-commit hook already rejects markers in a staged diff, and markers still
reached `develop` three times: `8f35bd20`, and then six `|||||||` lines in
`docs/windows-parity.md` that survived for weeks. Both escapes have the same
shape. The hook looks at a *diff*, so it only ever sees the commit that
introduces a marker; once one is in `HEAD` no later commit touching another part
of the file will mention it again, and nothing looks at the file as it stands.
This walks the tree instead, which is the only way an already-landed marker gets
found.

The markers are the four git writes: `<<<<<<< ref`, `||||||| ref` (the base
section, present under `merge.conflictStyle` diff3/zdiff3), `=======`, and
`>>>>>>> ref`. The bare `=======` is deliberately not matched on its own - it is
a Markdown/reStructuredText heading underline far more often than it is a
conflict - so a conflict is reported by its labelled markers, of which a real
one always has at least two.
"""

from __future__ import annotations

import pathlib
import re
import subprocess
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
# Binary payloads and generated bundles are excluded by extension rather than by
# path: a marker cannot be read out of them, and a false positive in a minified
# bundle would be indistinguishable from a real one.
BINARY_SUFFIXES = {
    ".png", ".jpg", ".jpeg", ".gif", ".ico", ".icns", ".webp", ".svg",
    ".pdf", ".zip", ".gz", ".xz", ".dat", ".bin", ".so", ".dylib", ".dll",
    ".a", ".lib", ".exe", ".ttf", ".otf", ".woff", ".woff2", ".mp3", ".wav",
}
MARKER = re.compile(r"^(?:<{7}|\|{7}|>{7})(?: .*)?$")
# This file names the markers it looks for, so it would report itself.
SELF = "scripts/test-conflict-markers.py"


def tracked_files() -> list[str]:
    listing = subprocess.run(
        ["git", "ls-files", "-z"],
        cwd=ROOT,
        capture_output=True,
        check=True,
        text=True,
    )
    return [name for name in listing.stdout.split("\0") if name]


def main() -> int:
    findings = []
    for relative in tracked_files():
        if relative == SELF:
            continue
        path = ROOT / relative
        if path.suffix.lower() in BINARY_SUFFIXES or not path.is_file():
            continue
        try:
            text = path.read_text(encoding="utf-8")
        except (UnicodeDecodeError, OSError):
            continue
        for number, line in enumerate(text.splitlines(), 1):
            if MARKER.match(line):
                findings.append(f"{relative}:{number}: {line.strip()}")

    for finding in findings:
        print(f"FAIL {finding}", file=sys.stderr)
    if findings:
        print(
            "\nA conflict was resolved by deleting some markers and not all. "
            "Remove the remaining lines and check that the surrounding text is "
            "the resolution you meant, not both sides concatenated.",
            file=sys.stderr,
        )
        return 1
    print("conflict markers: none in the tracked tree")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
