#!/usr/bin/env python3
"""Port the fixed Windows quanpin autocorrection pipeline to the locked Engine.

MSIME-Windows 467b9804 contains the accumulated corrections from 3c2f3ae3,
34c69fbe, c064cc64, 49d0bf58, 94abc08e, 6673155c and 3ee2ecdb.  The shared
Engine lock predates them, while this repository already overlays independent
lattice, learning, cache and Google-spelling work.  Apply a strict contextual
patch after those overlays, then regenerate the large deterministic typo table
from the Engine's own legal-syllable list instead of checking in generated
vendor source.
"""

from pathlib import Path
import re
import runpy


HERE = Path(__file__).resolve().parent
PATCH = HERE / "engine-overlays" / "quanpin-autocorrect-parity.patch"
GENERATOR = HERE / "engine-overlays" / "generate_quanpin_autocorrect.py"
HUNK = re.compile(r"^@@ -(\d+)(?:,(\d+))? \+(\d+)(?:,(\d+))? @@")


def _patch_line(line: str) -> tuple[str, str]:
    # A normal unified diff spells an empty context line as " \\n", which is
    # trailing whitespace when the patch is itself versioned. The stored patch
    # uses "~\\n" for that one case; translate it back before matching.
    if line == "~\n":
        return " ", "\n"
    return line[:1], line[1:]


def _apply_file(root: Path, relative: str, hunks: list[list[str]]) -> None:
    path = root / relative
    source = path.read_text(encoding="utf-8").splitlines(keepends=True)
    output: list[str] = []
    cursor = 0

    for hunk in hunks:
        match = HUNK.match(hunk[0])
        if match is None:
            raise RuntimeError(f"malformed Engine overlay hunk for {relative}: {hunk[0].rstrip()}")
        decoded = [_patch_line(line) for line in hunk[1:]]
        expected = [body for marker, body in decoded if marker in {" ", "-"}]
        matches = [
            position
            for position in range(cursor, len(source) - len(expected) + 1)
            if source[position : position + len(expected)] == expected
        ]
        if len(matches) != 1:
            nominal = int(match.group(1))
            raise RuntimeError(
                f"Engine overlay expected one contextual match for {relative} near line {nominal}, "
                f"found {len(matches)}"
            )
        output.extend(source[cursor : matches[0]])
        cursor = matches[0]

        for line in hunk[1:]:
            if line.startswith("\\ No newline at end of file"):
                continue
            marker, body = _patch_line(line)
            if marker in {" ", "-"}:
                if cursor >= len(source) or source[cursor] != body:
                    actual = "<end of file>" if cursor >= len(source) else source[cursor].rstrip("\n")
                    raise RuntimeError(
                        f"Engine overlay context mismatch in {relative}:{cursor + 1}: "
                        f"expected {body.rstrip()!r}, found {actual!r}"
                    )
                if marker == " ":
                    output.append(body)
                cursor += 1
            elif marker == "+":
                output.append(body)
            else:
                raise RuntimeError(f"unknown Engine overlay marker {marker!r} in {relative}")

    output.extend(source[cursor:])
    path.write_text("".join(output), encoding="utf-8", newline="\n")


def _read_patch() -> list[tuple[str, list[list[str]]]]:
    lines = PATCH.read_text(encoding="utf-8").splitlines(keepends=True)
    files: list[tuple[str, list[list[str]]]] = []
    index = 0
    while index < len(lines):
        if not lines[index].startswith("--- a/"):
            raise RuntimeError(f"unexpected Engine overlay line: {lines[index].rstrip()}")
        old_path = lines[index][6:].rstrip("\n")
        index += 1
        if index >= len(lines) or not lines[index].startswith("+++ b/"):
            raise RuntimeError(f"missing new-file header after {old_path}")
        new_path = lines[index][6:].rstrip("\n")
        if new_path != old_path:
            raise RuntimeError(f"Engine overlay cannot rename {old_path} to {new_path}")
        index += 1
        hunks: list[list[str]] = []
        while index < len(lines) and not lines[index].startswith("--- a/"):
            if not lines[index].startswith("@@ "):
                raise RuntimeError(f"missing hunk header for {old_path}: {lines[index].rstrip()}")
            start = index
            index += 1
            while index < len(lines) and not lines[index].startswith(("@@ ", "--- a/")):
                index += 1
            hunks.append(lines[start:index])
        files.append((old_path, hunks))
    return files


def apply(root: Path) -> None:
    for relative, hunks in _read_patch():
        _apply_file(root, relative, hunks)

    namespace = runpy.run_path(str(GENERATOR), run_name="__quanpin_autocorrect_generator__")
    generate = namespace.get("generate")
    if not callable(generate):
        raise RuntimeError(f"Engine autocorrect generator has no generate() function: {GENERATOR}")
    generate(root)


if __name__ == "__main__":
    import sys

    apply(Path(sys.argv[1]))
