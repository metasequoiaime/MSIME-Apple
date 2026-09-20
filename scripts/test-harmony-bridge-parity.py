#!/usr/bin/env python3
"""Check that every bridge method the HarmonyOS settings page calls is one the host registers.

The page reaches the host through a single injected object, and ArkTS decides what that object
exposes twice over: the method has to exist on the bridge class in `Settings.ets`, and its *name*
has to appear in the list handed to `registerJavaScriptProxy`. Only the second one is what the page
actually sees.

Nothing catches a mismatch. The TypeScript side declares the method on its `NativeBridge` interface
and type-checks fine; the ArkTS side compiles fine; the settings bundle builds fine. The failure is
at runtime on a device, as `msimeHarmony.<name> is not a function` — a section that simply does not
work, on the one platform nobody can run here.

That is exactly what happened when the named custom skin library was added: the method was written
and the name was not registered, and three separate green gates said nothing.
"""
import pathlib
import re
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
PAGE = ROOT / "apps/harmony/src/main.tsx"
HOST = ROOT / "platforms/harmony/entry/src/main/ets/pages/Settings.ets"


def called() -> set[str]:
    """The members of the page's `NativeBridge` interface, which is everything it may call."""
    text = PAGE.read_text()
    start = text.index("interface NativeBridge {")
    body = text[start : text.index("\n}", start)]
    # `name(args): type;` at one level of indentation, skipping comment lines.
    names = set(re.findall(r"^  ([A-Za-z][A-Za-z0-9]*)\(", body, re.MULTILINE))
    if not names:
        raise SystemExit(f"no bridge members found in {PAGE.name}; the extraction is wrong")
    return names


def registered() -> set[str]:
    """The names passed to `registerJavaScriptProxy`, which is what the page can reach."""
    text = HOST.read_text()
    start = text.index("registerJavaScriptProxy(")
    body = text[start : text.index("[]", start)]
    names = set(re.findall(r"'([A-Za-z][A-Za-z0-9]*)'", body))
    names.discard("msimeHarmony")
    if not names:
        raise SystemExit(f"no registered names found in {HOST.name}; the extraction is wrong")
    return names


def defined() -> set[str]:
    """Methods on the bridge class, so a registered name that has no method is also caught."""
    text = HOST.read_text()
    start = text.index("class SettingsBridge")
    body = text[start : text.index("\n@Entry", start) if "\n@Entry" in text[start:] else len(text)]
    return set(re.findall(r"^  (?:async )?([A-Za-z][A-Za-z0-9]*)\(", body, re.MULTILINE))


def main() -> int:
    page = called()
    host = registered()
    methods = defined()
    problems = []
    missing = sorted(page - host)
    if missing:
        problems.append(
            "the page calls these, and registerJavaScriptProxy does not list them, so on a device "
            f"they are not functions: {', '.join(missing)}"
        )
    unbacked = sorted(host - methods)
    if unbacked:
        problems.append(
            f"these names are registered but no method on the bridge answers them: "
            f"{', '.join(unbacked)}"
        )
    if problems:
        for problem in problems:
            print(f"harmony bridge parity: {problem}", file=sys.stderr)
        return 1
    # An extra registered name the page does not call is not a failure: a host may expose something
    # before the page uses it, and the reverse is the direction that breaks.
    print(f"harmony bridge parity: {len(page)} page calls, all registered and backed")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
