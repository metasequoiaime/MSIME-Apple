#!/usr/bin/env python3
"""Compile the Windows sources for x86 as well as x64.

A 32-bit TSF DLL is loaded into every 32-bit host application, so the same
C++ has to build for both. Nothing checked that: `build-cross.sh x86` needs a
DWARF-unwinding MinGW for the Rust side, and the toolchain in common use on
macOS is SJLJ, so the whole architecture went unbuilt — and a call that
compiles only on x86_64 sat in the candidate window. `FONTENUMPROCW` is
`__stdcall`; a captureless lambda converts to a `__cdecl` function pointer,
which is the same type on x86_64 and a different one on x86.

The flags come from the x64 build's compile_commands.json rather than a second
list kept by hand, so a source or an include added to CMake is covered here
without anyone remembering to. Only the compiler is swapped: this is a syntax
check, not a link, so it needs none of the 32-bit libraries.
"""

from __future__ import annotations

import json
import pathlib
import shlex
import subprocess
import sys
from concurrent.futures import ThreadPoolExecutor

ROOT = pathlib.Path(__file__).resolve().parent.parent
COMPILER = "i686-w64-mingw32-g++"
HOST_COMPILER = "x86_64-w64-mingw32-g++"


def database() -> pathlib.Path | None:
    for build in sorted((ROOT / "target/windows-full").glob("*/compile_commands.json")):
        return build
    return None


def check(entry: dict[str, str]) -> tuple[str, str]:
    arguments = shlex.split(entry["command"])
    swapped = [COMPILER if HOST_COMPILER in argument else argument for argument in arguments]
    # -o and -c would write an object for the wrong architecture next to the
    # x64 one. Syntax-only answers the question without touching the tree.
    cleaned: list[str] = []
    skip = False
    for argument in swapped[1:]:
        if skip:
            skip = False
            continue
        if argument in ("-o", "-c"):
            skip = argument == "-o"
            continue
        cleaned.append(argument)
    result = subprocess.run(
        [swapped[0], "-fsyntax-only", *cleaned],
        cwd=entry["directory"], capture_output=True, text=True,
    )
    return entry["file"], "" if result.returncode == 0 else result.stderr


def main() -> int:
    path = database()
    if path is None:
        print("skipped: no x64 cross build to take compile flags from")
        print("  run platforms/windows/build-cross.sh x64 once to enable this check")
        return 0
    try:
        subprocess.run([COMPILER, "--version"], capture_output=True, check=True)
    except (OSError, subprocess.CalledProcessError):
        print(f"skipped: {COMPILER} is not installed")
        return 0

    entries = [
        entry for entry in json.loads(path.read_text(encoding="utf-8"))
        if entry["file"].endswith((".cpp", ".cc"))
    ]
    failures = []
    with ThreadPoolExecutor() as pool:
        for source, error in pool.map(check, entries):
            if error:
                relevant = [line for line in error.splitlines() if "error:" in line]
                failures.append(f"{source}\n    " + "\n    ".join(relevant[:3]))

    for failure in failures:
        print(f"FAIL {failure}", file=sys.stderr)
    if failures:
        return 1
    print(f"windows x86 syntax: {len(entries)} sources compile for i686 too")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
