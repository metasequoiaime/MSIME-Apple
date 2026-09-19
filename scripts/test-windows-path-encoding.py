#!/usr/bin/env python3
"""No `std::filesystem::path::string()` in C++ that Windows compiles.

Narrow strings in this repository are UTF-8. `path::string()` converts through
the *system* narrow encoding instead, which on Windows is the ANSI code page.
The two agree only on ASCII: under a profile such as `C:\\Users\\陆傲天` the call
either hands back different bytes or throws outright, and a throw in the middle
of a file operation aborts work that has already been half-published.

`u8string()` is the conversion that means what the rest of the code means. When
a derived name is being built, concatenating onto the path (`path += "-wal"`)
avoids the conversion altogether; every affix in this repository is ASCII, the
one thing every code page agrees on.

Platform directories that Windows never compiles are skipped: they run where
the system encoding is UTF-8, so the distinction does not arise there.
"""

from __future__ import annotations

import pathlib
import re
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
SEARCH = ["crates", "platforms/windows", "shared"]
SKIP_PREFIXES = (
    "platforms/macos",
    "platforms/linux",
    "platforms/android",
    "platforms/harmony",
    "platforms/ios",
)
PATTERN = re.compile(r"\.string\(\)")


def main() -> int:
    findings = []
    for area in SEARCH:
        base = ROOT / area
        if not base.exists():
            continue
        for path in sorted(base.rglob("*")):
            if path.suffix not in {".cpp", ".h", ".hpp", ".cc"} or not path.is_file():
                continue
            relative = path.relative_to(ROOT).as_posix()
            if relative.startswith(SKIP_PREFIXES) or "/vendor/" in relative:
                continue
            for number, line in enumerate(path.read_text(encoding="utf-8", errors="replace").splitlines(), 1):
                if PATTERN.search(line):
                    findings.append(f"{relative}:{number}: {line.strip()}")

    for finding in findings:
        print(f"FAIL {finding}", file=sys.stderr)
    if findings:
        print(
            "\nUse u8string(), or build derived names by concatenating onto the "
            "path so no narrow conversion happens at all.",
            file=sys.stderr,
        )
        return 1
    print("Windows path encoding: no ANSI narrow conversions")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
