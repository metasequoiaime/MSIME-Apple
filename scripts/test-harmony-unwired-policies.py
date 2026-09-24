#!/usr/bin/env python3
"""Check that no HarmonyOS host module is reachable only from its own tests.

A module under `platforms/harmony/entry/src/main/ets` that nothing in the application imports is
not shipped code, whatever its tests say. This has happened twice, and both times every gate was
green:

  * #3419 — four accessibility label policies had been ported from the source and unit-tested, and
    the view attached none of them. The keyboard announced nothing to a screen reader while four
    groups of assertions passed.
  * #3435 — a merge resolved a conflict by taking the pre-#3419 side and put the same state back.
    The policy file and its tests disappeared together, so the assertion count fell from 1293 to
    1289 and nothing turned red. A revert that removes a whole feature reads, in every check, as a
    slightly smaller number.

A test suite cannot notice either: it imports the module directly, so the module is exercised and
the assertions pass whether or not the application ever calls it. The question this asks is the one
the suite structurally cannot — *does anything but a test reach this file* — and it is asked from
the importing side, which is where the answer lives.

It is a reachability check, not a usage check. A module imported by another unwired module still
counts here; the transitive case has not been the failure, and following it would report a whole
cluster for one missing call site rather than the call site.
"""
import pathlib
import re
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
SOURCES = ROOT / "platforms/harmony/entry/src/main/ets"

# Entry points the framework loads by name out of module.json5, main_pages.json and the workers list in entry/build-profile.json5, so nothing in the source tree imports them. Everything else has to be reachable from one of these.
ENTRY_POINTS = {
    "EntryAbility",
    "KeyboardExtensionAbility",
    "Settings",
    "KeyboardView",
    "FloatingToolbar",
    "InputModeHud",
    "LocalAsrWorker",
}

IMPORT = re.compile(r"""^\s*import\s[^'"]*['"]([^'"]+)['"]""", re.MULTILINE)

# Empty, and meant to stay that way. It exists because this check was written against a tree that
# already had two unwired modules, and an allowlist was the only way to land the check without
# either deleting someone else's code in the same change or leaving the check switched off. Both
# entries were then resolved rather than kept: see the commit that emptied this.
#
# Anything added here is debt, not an exemption. The check fails if a listed name becomes reachable
# again, so the list cannot rot into a list of lies.
KNOWN_UNWIRED: set[str] = set()


def imported_stems(path: pathlib.Path) -> set[str]:
    """The basenames this file imports from a relative path, which is how it names a sibling."""
    text = path.read_text(encoding="utf-8")
    out: set[str] = set()
    for target in IMPORT.findall(text):
        if target.startswith("."):
            out.add(pathlib.PurePosixPath(target).name)
    return out


def main() -> int:
    if not SOURCES.is_dir():
        print(f"harmony unwired policies: {SOURCES} is missing", file=sys.stderr)
        return 1
    modules = sorted(p for p in SOURCES.rglob("*") if p.suffix in {".ts", ".ets"})
    if not modules:
        print("harmony unwired policies: no sources found; the extraction is wrong", file=sys.stderr)
        return 1
    reached: set[str] = set()
    for path in modules:
        reached |= imported_stems(path)
    unreachable = [p for p in modules if p.stem not in reached and p.stem not in ENTRY_POINTS]
    unwired = [p for p in unreachable if str(p.relative_to(ROOT)) not in KNOWN_UNWIRED]
    # A name on the list that has since been wired up is a stale exemption, and leaving it would
    # let the next regression hide behind it.
    unreachable_paths = {str(p.relative_to(ROOT)) for p in unreachable}
    present = {str(p.relative_to(ROOT)) for p in modules}
    stale = sorted(
        name for name in KNOWN_UNWIRED if name in present and name not in unreachable_paths
    )
    if stale:
        for name in stale:
            print(f"{name}: now reachable; remove it from KNOWN_UNWIRED", file=sys.stderr)
        return 1
    if unwired:
        for path in unwired:
            print(
                f"{path.relative_to(ROOT)}: nothing in the application imports this; "
                "if only its tests do, it is not shipped code",
                file=sys.stderr,
            )
        print(
            f"harmony unwired policies: {len(unwired)} module(s) the application never reaches. "
            "A ported policy with passing tests and no call site is the shape of #3419 and #3435.",
            file=sys.stderr,
        )
        return 1
    print(f"harmony unwired policies: all {len(modules)} host modules are reachable")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
