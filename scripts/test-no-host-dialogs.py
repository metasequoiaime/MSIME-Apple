#!/usr/bin/env python3
"""No `window.confirm`, `window.alert` or `window.prompt` in the shared UI.

These are not dialogs this application can rely on. The shared settings page runs in six hosts, and
on the two Apple ones it renders through wry's WKWebView, whose `WKUIDelegate` implements none of
the JavaScript dialog methods - `runJavaScriptAlertPanel`, `runJavaScriptConfirmPanel`,
`runJavaScriptTextInputPanel`. WKWebView has no built-in ones, so the panel is never shown and
`confirm()` returns `false` immediately: the guarded action silently never runs, and the button
claims a feature that does nothing. Measured, not inferred - a minimal WKWebView in that exact
configuration answers in about two milliseconds with nothing on screen.

Where they do appear they are host modals: they do not follow the page theme, they carry the
host's own button labels (wry's Android client hardcodes English `OK`/`Cancel` under a Chinese
UI), and while one is up the page's own keyboard and focus handling is suspended.

`useConfirm` in `packages/ui/src/core/confirm.tsx` is the replacement, and it behaves the same
everywhere because it is part of the page.

Only the shared UI is covered. A native host calling its own platform dialog is a different thing
and is not this check's business.
"""

from __future__ import annotations

import pathlib
import re
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
SEARCH = ["packages/ui/src", "apps/desktop/src", "apps/harmony/src"]
# Vendored upstream assets are copied verbatim and are checked by their own parity scripts.
SKIP_PREFIXES = ("packages/ui/src/upstream",)
# `window.` is optional: bare `confirm(...)` resolves to the same global.
PATTERN = re.compile(r"(?<![.\w])(?:window\s*\.\s*)?(confirm|alert|prompt)\s*\(")


def offenders(relative: str, text: str) -> list[str]:
    findings = []
    for number, line in enumerate(text.splitlines(), 1):
        for match in PATTERN.finditer(line):
            # An explicit `window.` is always the global, whichever name follows it. The check is
            # on the matched text rather than on what precedes it: `window` is inside the match,
            # so looking behind the match start finds everything except the word being tested -
            # which is how the first version of this guard passed `window.confirm` straight
            # through while catching the other two.
            if match.group(0).lstrip().startswith("window"):
                findings.append(f"{relative}:{number}: {line.strip()}")
                continue
            # Bare `confirm(` is the hook's own method in this repository; bare `alert(` and
            # `prompt(` have no local meaning here, so they are the global.
            if match.group(1) == "confirm":
                continue
            findings.append(f"{relative}:{number}: {line.strip()}")
    return findings


def main() -> int:
    findings = []
    for area in SEARCH:
        base = ROOT / area
        if not base.exists():
            continue
        for path in sorted(base.rglob("*")):
            if path.suffix not in {".ts", ".tsx"} or not path.is_file():
                continue
            relative = path.relative_to(ROOT).as_posix()
            if relative.startswith(SKIP_PREFIXES):
                continue
            findings.extend(offenders(relative, path.read_text(encoding="utf-8")))

    for finding in findings:
        print(f"FAIL {finding}", file=sys.stderr)
    if findings:
        print(
            "\nUse useConfirm() from packages/ui/src/core/confirm.tsx. The host dialogs do not "
            "appear at all on the Apple hosts, so a button behind one does nothing there.",
            file=sys.stderr,
        )
        return 1
    print("host dialogs: the shared UI asks in-page")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
