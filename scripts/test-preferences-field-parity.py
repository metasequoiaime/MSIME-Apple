#!/usr/bin/env python3
"""Keep the settings page's Preferences shape and the Rust document in step.

`client_core::preferences::Preferences` carries `deny_unknown_fields`, and
Tauri's `save_preferences` deserializes the front end's object straight into
it. A key the page can write but the struct does not have therefore does not
get dropped - it fails the whole save, so touching one unmapped toggle stops
the settings window persisting anything at all. That is what happened to the
three smart-punctuation sub-switches, and nothing would have caught it before
a user did.

A field only Rust has is the milder direction: a setting nobody can reach from
the settings page. Those exist on purpose sometimes, so they are listed here
with the reason rather than being reported.
"""

from __future__ import annotations

import pathlib
import re
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
UI = ROOT / "packages/ui/src/index.tsx"
RUST = ROOT / "crates/client-core/src/preferences.rs"

# Rust fields with no control on the settings page, and why.
RUST_ONLY = {
    "Preferences": {
        # Preserved so the Windows default config keeps a counterpart for every
        # key of the source's, even though this client renders candidates with
        # Direct2D only and offers no choice to make.
        "ui_backend",
    },
}


def ts_types(source: str) -> dict[str, set[str]]:
    """Type name -> its own top-level keys.

    Brace matching rather than a line-anchored pattern: these declarations come
    both as one line and as many, and a regex that assumes the multi-line shape
    runs past the closing brace and collects whatever follows.
    """
    out: dict[str, set[str]] = {}
    for match in re.finditer(r"export type (\w+) = \{", source):
        start = match.end() - 1
        depth = 0
        end = start
        for index in range(start, len(source)):
            if source[index] == "{":
                depth += 1
            elif source[index] == "}":
                depth -= 1
                if depth == 0:
                    end = index
                    break
        body = source[start + 1 : end]
        # Only this type's own keys; a nested inline object is reached through
        # whichever named type owns it, not counted twice here.
        keys: set[str] = set()
        depth = 0
        for piece in re.split(r"([{}])", body):
            if piece == "{":
                depth += 1
                continue
            if piece == "}":
                depth -= 1
                continue
            if depth == 0:
                keys.update(re.findall(r"(?:^|[;\n])\s*(\w+)\??:", piece))
        out[match.group(1)] = keys
    return out


def rust_structs(source: str) -> dict[str, set[str]]:
    out: dict[str, set[str]] = {}
    for name, body in re.findall(r"pub struct (\w+)\s*\{(.*?)\n\}\n", source, re.S):
        out[name] = set(re.findall(r"^\s*pub (\w+):", body, re.M))
    return out


def main() -> int:
    ts = ts_types(UI.read_text(encoding="utf-8"))
    rust = rust_structs(RUST.read_text(encoding="utf-8"))
    if "Preferences" not in ts or "Preferences" not in rust:
        print("Preferences type not found; the parser needs updating", file=sys.stderr)
        return 1

    failures = []
    checked = 0
    for name in sorted(set(ts) & set(rust)):
        checked += 1
        unmapped = sorted(ts[name] - rust[name])
        if unmapped:
            failures.append(
                f"{name}: the settings page can write {unmapped}, which "
                f"client_core::preferences::{name} has no field for. "
                "deny_unknown_fields means saving fails outright."
            )
        unreachable = sorted(rust[name] - ts[name] - RUST_ONLY.get(name, set()))
        if unreachable:
            failures.append(
                f"{name}: {unreachable} exist in Rust with no control on the "
                "settings page. Add one, or record the reason in RUST_ONLY."
            )

    for failure in failures:
        print(f"FAIL {failure}", file=sys.stderr)
    if failures:
        return 1
    print(f"Preferences field parity: {checked} shared types agree")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
