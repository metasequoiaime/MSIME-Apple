#!/usr/bin/env python3
"""A macOS test that creates a preferences suite has to remove it.

`NSUserDefaults initWithSuiteName:` writes a plist into the user's `~/Library/Preferences`, and
`removePersistentDomainForName:` empties that file without deleting it. A test that does neither -
or only the latter - leaves litter on every machine that ever runs the suite, forever, and nothing
else ever looks at those files again. 185 of them had piled up on the machine this was written on,
and `TestPreferenceSuite.h` records an earlier count of 3257.

So: every test source that opens a suite must also call `MSIMERemoveTestPreferenceSuite`, which
removes the domain *and* the file. This checks the pairing rather than the count, because the count
is a property of how often the suite has been run.
"""

from __future__ import annotations

import pathlib
import re
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
TESTS = ROOT / "platforms/macos/tests"
OPENS = "initWithSuiteName:"
REMOVES = "MSIMERemoveTestPreferenceSuite"
# A test may hand the suite name to a helper that removes it; name the helper's file so the pairing
# is still visible. Empty today, and an entry here should say which helper and why.
ALLOWED: dict[str, str] = {}


def main() -> int:
    if not TESTS.is_dir():
        print("skipped: the macOS tests are not present")
        return 0
    failures: list[str] = []
    paired = 0
    for path in sorted(TESTS.rglob("*.mm")) + sorted(TESTS.rglob("*.cpp")):
        text = path.read_text(encoding="utf-8", errors="ignore")
        if OPENS not in text:
            continue
        relative = str(path.relative_to(ROOT))
        if REMOVES in text:
            paired += 1
            continue
        if relative in ALLOWED:
            continue
        # A bare removePersistentDomainForName: is the half-fix that leaves the file behind, and is
        # worth naming separately: it reads like cleanup.
        empties = re.search(r"removePersistentDomainForName:", text) is not None
        failures.append(
            f"{relative} opens a preferences suite and "
            + (
                "only empties it, leaving the plist on disk"
                if empties
                else "never removes it"
            )
        )

    if failures:
        for failure in failures:
            print(failure, file=sys.stderr)
        print(f"call {REMOVES}(defaults, suite) before returning", file=sys.stderr)
        return 1
    print(f"preference suite cleanup: {paired} macOS tests open a suite, all of them remove it")
    return 0


if __name__ == "__main__":
    sys.exit(main())
