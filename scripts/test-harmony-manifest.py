#!/usr/bin/env python3
"""Check the HarmonyOS module manifest for the two mistakes JSON will not report.

`module.json5` is read by hvigor against a schema, and it passed that schema while carrying both of
the faults below, because neither is a schema violation a parser can see.

A duplicate key. `"abilities"` was declared twice, verbatim, from `bdb801b63` — the commit that added
the settings application — until this check was written. JSON says the last one wins, so the first
block was dead text that looked exactly like the live one; editing the wrong copy would have changed
nothing and given no clue why. Python's `json` silently keeps the last value too, which is why this
counts the keys in the text rather than parsing and looking at the result.

An element that draws no icon. The schema says `icon` on an extension "must be configured" when the
extension is the `mainElement`, but says it as prose in a description rather than as `required`, so
nothing enforced it. This module's `mainElement` is `KeyboardExtensionAbility`, and without an icon
the keyboard sat in the system's input-method list with a name and a blank space. The same goes for
an ability carrying `entity.system.home`: it is what the launcher draws.

The packaged manifest is where the answer really lives — a `$media:` reference that does not resolve
is dropped rather than failing the build — so this also checks the built `module.json` when one is
there, which is where `iconId` appears.
"""
import json
import pathlib
import re
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
SOURCE = ROOT / "platforms/harmony/entry/src/main/module.json5"
PACKAGED = ROOT / "platforms/harmony/entry/build/default/outputs/default"


def without_comments(text: str) -> str:
    """JSON5 minus the two things that stop `json` reading it: comments and trailing commas."""
    stripped = re.sub(r"^\s*//.*$", "", text, flags=re.M)
    return re.sub(r",(\s*[\]}])", r"\1", stripped)


def main() -> int:
    if not SOURCE.is_file():
        print(f"no HarmonyOS manifest at {SOURCE}", file=sys.stderr)
        return 1
    text = SOURCE.read_text(encoding="utf-8")
    failures: list[str] = []

    # Module-level keys, counted in the text: a duplicate is invisible once parsed.
    for key in ("abilities", "extensionAbilities", "mainElement", "requestPermissions"):
        found = len(re.findall(rf'^    "{key}":', text, flags=re.M))
        if found > 1:
            failures.append(
                f'"{key}" is declared {found} times at module level; JSON keeps the last, '
                f"so the earlier one is dead text that reads like live configuration"
            )

    module = json.loads(without_comments(text))["module"]
    main_element = module.get("mainElement")
    elements = module.get("abilities", []) + module.get("extensionAbilities", [])
    by_name = {element["name"]: element for element in elements}

    if main_element and main_element in by_name and not by_name[main_element].get("icon"):
        failures.append(
            f"{main_element} is the mainElement and declares no icon, so the system lists it "
            f"with a name and a blank space"
        )
    for element in elements:
        home = any(
            "entity.system.home" in skill.get("entities", [])
            for skill in element.get("skills", [])
        )
        if home and not element.get("icon"):
            failures.append(f"{element['name']} is a launcher entry and declares no icon")

    # The build is where a $media: reference is resolved, and an unresolved one is simply dropped.
    built = PACKAGED / "module.json"
    if not built.is_file():
        candidates = sorted(PACKAGED.glob("*.hap"))
        built = None if not candidates else built
    if built is not None and built.is_file():
        packaged = json.loads(built.read_text(encoding="utf-8"))["module"]
        for element in packaged.get("abilities", []) + packaged.get("extensionAbilities", []):
            if element.get("icon") and not element.get("iconId"):
                failures.append(
                    f"{element['name']} names an icon the packaged manifest could not resolve"
                )

    if failures:
        print("HarmonyOS manifest:", file=sys.stderr)
        for failure in failures:
            print(f"  {failure}", file=sys.stderr)
        return 1

    named = ", ".join(sorted(by_name))
    print(f"harmony manifest: {len(by_name)} elements, all launcher-facing ones named ({named})")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
