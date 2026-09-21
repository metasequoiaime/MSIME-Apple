#!/usr/bin/env python3
"""The handwriting panel never offers more than the shared contract accepts.

The panel caps strokes, points per stroke and candidates; `client-core`'s panel
contract caps the same three and rejects a request that exceeds them. The two
are written in different languages and live in different files, so the only
thing keeping them in agreement is that nobody has raised the panel's number.

Raising it is silent in the worst way: the user draws a stroke the panel accepts
and recognition simply returns nothing, because the request was refused before
it reached a recogniser. The invariant is one-directional - the panel may be
stricter, never looser - so that is what this checks.

Equality is fine and is the case for candidates today; what must not happen is
the panel exceeding the contract.
"""

from __future__ import annotations

import pathlib
import re
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
CONTRACT = ROOT / "crates/client-core/src/panels.rs"
PANEL = ROOT / "packages/ui/src/keyboard/panels.tsx"

# (what it bounds, Rust constant, TypeScript constant)
LIMITS = [
    ("strokes in one request", "MAX_STROKES", "MAX_HANDWRITING_STROKES"),
    ("points in one stroke", "MAX_POINTS_PER_STROKE", "MAX_CAPTURED_POINTS"),
    ("candidates offered", "MAX_CANDIDATES", "MAX_HANDWRITING_CANDIDATES"),
]


def rust_value(text: str, name: str) -> int | None:
    match = re.search(rf"const {name}: usize = (\d+);", text)
    return int(match.group(1)) if match else None


def typescript_value(text: str, name: str) -> int | None:
    match = re.search(rf"const {name} = (\d+);", text)
    return int(match.group(1)) if match else None


def main() -> int:
    if not CONTRACT.exists() or not PANEL.exists():
        print("skipped: the handwriting contract or panel is not present")
        return 0
    contract = CONTRACT.read_text(encoding="utf-8")
    panel = PANEL.read_text(encoding="utf-8")

    findings = []
    checked = []
    for description, rust_name, ts_name in LIMITS:
        allowed = rust_value(contract, rust_name)
        offered = typescript_value(panel, ts_name)
        if allowed is None:
            findings.append(f"{rust_name} is no longer a plain constant in panels.rs")
            continue
        if offered is None:
            findings.append(f"{ts_name} is no longer a plain constant in panels.tsx")
            continue
        if offered > allowed:
            findings.append(
                f"{description}: the panel offers {offered} and the contract accepts "
                f"{allowed}, so the excess is drawn and then refused with nothing shown"
            )
            continue
        checked.append(f"{description} {offered}/{allowed}")

    for finding in findings:
        print(f"FAIL {finding}", file=sys.stderr)
    if findings:
        return 1
    print("handwriting limits: " + ", ".join(checked))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
