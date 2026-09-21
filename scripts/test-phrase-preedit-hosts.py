#!/usr/bin/env python3
"""A host either assembles a phrase in the composition or it does not - never half of it.

Picking a candidate that covers only part of the input leaves the Engine composing the rest and
hands back the piece that was picked. A host can ask the runtime to hold that piece
(`phrase_preedit` in its session options) and draw it itself (`view.phrase_prefix`), which is what
the reference does; or it can take the old behaviour, where each piece is committed as it is picked.
Both are whole answers.

Half of it is not, and the dangerous half is silent: a host that asks for the piece to be held and
never draws it shows nothing at all for text the user already chose, and the document stays empty
until the phrase ends - which, if the user gives up and presses Escape, it never does.

The rollout is per host, and this pins whichever side each host is on today rather than requiring
them all to move together. What it refuses is the half state.
"""

from __future__ import annotations

import pathlib
import re
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
REQUEST = "phrase_preedit"
FIELD = "phrase_prefix"
# Each host is its own sources, plus the shared rendering it goes through. The two are kept apart:
# a shared renderer that can draw the field says nothing about whether a given host asked for it,
# and Apple's TextClient is shared by two hosts that are not on the same side of this today.
# Tests are excluded - a test naming the field proves nothing about what a host draws.
HOSTS = {
    "macOS": (["platforms/macos/src"], ["shared/apple"]),
    "Linux": (["platforms/linux/src", "platforms/linux/fcitx5"], []),
    "Windows": (["platforms/windows/src", "platforms/windows/tsf"], []),
    "HarmonyOS": (["platforms/harmony/entry/src/main/ets"], []),
    "Android": (["platforms/android/java"], []),
    "iOS": (["platforms/ios"], ["shared/apple"]),
    "desktop shell": (["apps/desktop/src", "apps/desktop/src-tauri/src", "packages/ui/src"], []),
}
SUFFIXES = {".rs", ".mm", ".m", ".h", ".hpp", ".cpp", ".cc", ".swift", ".ts", ".tsx", ".ets", ".java", ".kt"}


def code(text: str) -> str:
    """The source with its comments removed.

    Every language here comments with `//` and `/* */`. Without this the check passes on a comment
    that merely names the field - which is exactly what a host left behind would look like after the
    rendering itself was deleted. A `//` inside a string literal is collapsed too; that costs
    nothing, because what is being asked is only whether a name appears.
    """
    without_blocks = re.sub(r"/\*.*?\*/", " ", text, flags=re.S)
    return re.sub(r"//[^\n]*", " ", without_blocks)


def mentions(roots: list[str], needle: str) -> list[str]:
    found: list[str] = []
    for root in roots:
        directory = ROOT / root
        if not directory.is_dir():
            continue
        for path in sorted(directory.rglob("*")):
            if path.suffix not in SUFFIXES or not path.is_file():
                continue
            try:
                if needle in code(path.read_text(encoding="utf-8")):
                    found.append(str(path.relative_to(ROOT)))
            except (UnicodeDecodeError, OSError):
                continue
    return found


def main() -> int:
    if not (ROOT / "crates/input-runtime/src/runtime.rs").is_file():
        print("skipped: the runtime is not present")
        return 0
    failures: list[str] = []
    holding: list[str] = []
    committing: list[str] = []
    for host, (own, shared) in HOSTS.items():
        if not any((ROOT / root).is_dir() for root in own):
            continue
        asks = mentions(own, REQUEST)
        draws = mentions(own + shared, FIELD)
        if asks and not draws:
            failures.append(
                f"{host} asks for {REQUEST} in {', '.join(asks)} and nothing it draws through reads "
                f"{FIELD}: a chosen phrase piece would be held back and drawn nowhere"
            )
        elif not asks and mentions(own, FIELD):
            failures.append(
                f"{host} reads {FIELD} in its own sources without asking for {REQUEST}: the field "
                f"is always empty there, so that rendering is dead"
            )
        elif asks:
            holding.append(host)
        else:
            committing.append(host)

    if failures:
        for failure in failures:
            print(failure, file=sys.stderr)
        return 1
    print(
        f"phrase preedit: held in the composition by {', '.join(holding) or 'no host'}; "
        f"committed piece by piece by {', '.join(committing) or 'no host'}"
    )
    return 0


if __name__ == "__main__":
    sys.exit(main())
