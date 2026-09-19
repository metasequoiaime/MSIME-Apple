#!/usr/bin/env python3
"""What the built input method actually ships, checked against the bundle rather than the sources.

The template plist, the resources directory and the CMake source lists are each checked on their own
elsewhere. None of that says the bundle came out right: a resource can be declared and not staged, a
localisation can exist in the tree and not be copied, and a provider can be compiled into a library that
the executable was never linked against. Every one of those is invisible until someone installs the thing.

Usage: bundle_contents.py <path/to/App.app> [--languages zh-Hans,en]
"""

import argparse
import plistlib
import re
import struct
import subprocess
import sys
from pathlib import Path

REQUIRED_MENU_PAGES = {(16, 16), (32, 32)}
ICON_KEYS = (
    "CFBundleIconFile",
    "tsInputMethodIconFileKey",
    "tsInputModeMenuIconFileKey",
    "tsInputModePaletteIconFileKey",
)


def tiff_pages(path: Path) -> set[tuple[int, int]]:
    data = path.read_bytes()
    endian = "<" if data[:2] == b"II" else ">"
    (offset,) = struct.unpack_from(endian + "I", data, 4)
    pages: set[tuple[int, int]] = set()
    seen: set[int] = set()
    while offset and offset not in seen:
        seen.add(offset)
        (count,) = struct.unpack_from(endian + "H", data, offset)
        size = {}
        for index in range(count):
            entry = offset + 2 + index * 12
            tag, kind = struct.unpack_from(endian + "HH", data, entry)
            if tag in (256, 257):
                (size[tag],) = struct.unpack_from(endian + ("H" if kind == 3 else "I"), data, entry + 8)
        if 256 in size and 257 in size:
            pages.add((size[256], size[257]))
        (offset,) = struct.unpack_from(endian + "I", data, offset + 2 + count * 12)
    return pages


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("bundle", type=Path)
    # The languages the build stages. Without this a bundle that shipped none of them would pass by
    # having nothing left to check.
    parser.add_argument("--languages", default="")
    arguments = parser.parse_args()
    bundle = arguments.bundle
    contents = bundle / "Contents"
    resources = contents / "Resources"
    failures: list[str] = []

    if not (contents / "Info.plist").is_file():
        print(f"{bundle} has no Contents/Info.plist", file=sys.stderr)
        return 1
    with (contents / "Info.plist").open("rb") as handle:
        plist = plistlib.load(handle)

    executable = resources.parent / "MacOS" / plist["CFBundleExecutable"]
    if not executable.is_file():
        failures.append(f"CFBundleExecutable names {executable.name}, which is not in Contents/MacOS")

    # The per-mode icons live inside ComponentInputModeDict, which is where the input menu reads them from;
    # the bundle-level one sits at the top. Collect both rather than assuming a shape.
    declared_icons: dict[str, str] = {key: plist[key] for key in ICON_KEYS if key in plist}
    for mode in (plist.get("ComponentInputModeDict", {}).get("tsInputModeListKey", {}) or {}).values():
        for key in ICON_KEYS:
            if key in mode:
                declared_icons[key] = mode[key]

    # Declared and staged are different things; the menu draws whatever is actually in the bundle.
    for key in ICON_KEYS:
        name = declared_icons.get(key)
        if not name:
            failures.append(f"{key} is not declared")
            continue
        icon = resources / name
        if not icon.is_file():
            failures.append(f"{key} names {name}, which was not staged into Resources")
        elif key != "CFBundleIconFile":
            missing = REQUIRED_MENU_PAGES - tiff_pages(icon)
            if missing:
                failures.append(
                    f"{name} ships without the {', '.join(f'{w}x{h}' for w, h in sorted(missing))} page"
                )

    # A localisation that exists in the tree but was not copied leaves the user reading the plist's language.
    usage = {key: value for key, value in plist.items() if key.endswith("UsageDescription")}
    lprojs = sorted(resources.glob("*.lproj"))
    expected = [name for name in arguments.languages.split(",") if name]
    for name in expected:
        if not (resources / f"{name}.lproj").is_dir():
            failures.append(f"{name}.lproj was not staged; that language falls back to the plist")
    if not lprojs:
        failures.append("no .lproj directories were staged")
    for lproj in lprojs:
        strings = lproj / "InfoPlist.strings"
        if not strings.is_file():
            failures.append(f"{lproj.name} has no InfoPlist.strings")
            continue
        # Staged .strings are binary plists, not the UTF-8 source.
        try:
            with strings.open("rb") as handle:
                localised = plistlib.load(handle)
        except Exception:
            localised = dict(re.findall(r'"([^"]+)"\s*=\s*"([^"]*)"', strings.read_text(encoding="utf-8")))
        for key in usage:
            if not localised.get(key, "").strip():
                failures.append(f"{key} is not localised in {lproj.name}")

    # The on-device recogniser is a build option. Compiled into a library the executable never links, the
    # host accepts the provider in its settings and then recognises somewhere else - which is the state this
    # bundle shipped in before the provider was wired up.
    if executable.is_file():
        symbols = subprocess.run(["nm", "-a", str(executable)], capture_output=True, text=True).stdout
        if "whisper" not in symbols:
            failures.append("the executable carries no local Whisper recogniser; the 本地 Whisper provider would fall back silently")

    if failures:
        for failure in failures:
            print(failure, file=sys.stderr)
        return 1
    print(f"{bundle.name}: icons staged, {len(usage)} usage descriptions localised in "
          f"{len(lprojs)} languages, local recogniser linked.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
