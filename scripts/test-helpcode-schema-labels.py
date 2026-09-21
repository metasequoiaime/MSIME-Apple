#!/usr/bin/env python3
"""Every surface that names a helpcode scheme names it the way the reference does.

A scheme's name is its own, not a description of it, so there is exactly one right spelling and the
reference owns it. Five places here spell them out - the shared settings page, the macOS settings
window, the macOS backend page, and the two Linux menus, which now share one table - and until this
check existed they did not agree: both Linux menus wrote 首右 as 搜狗, naming a different company's
input method in a menu that switches helpcode schemes. Nothing noticed, because no check here had
ever looked at a user-visible name; the config-key, UI-action and settings-coverage checks all
compare identifiers, and the identifier (`shouyou2_0`) was right in every copy.

So this compares the labels, and compares them against the reference rather than against each
other: five copies agreeing on the wrong name is exactly the state this is meant to catch. The
reference's own dropdown is the source, and the identifiers pair the two sides up.

The reference checkout is optional. Without it the check reports what it would have needed and
passes, the same as every other stage that depends on something not every machine has - but the
copies here are still compared with each other, which is the part that does not need a network.
"""

from __future__ import annotations

import os
import pathlib
import re
import subprocess
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
PARTIAL = "ui-html/webview2/settings/ime-settings/src/partials/helpcode.html"


def reference_root() -> pathlib.Path:
    """Where the reference checkout is: beside the *main* worktree, not beside this one."""
    override = os.environ.get("MSIME_REFERENCE_DIR")
    if override:
        return pathlib.Path(override)
    common = subprocess.run(
        ["git", "rev-parse", "--path-format=absolute", "--git-common-dir"],
        cwd=ROOT,
        capture_output=True,
        text=True,
    )
    if common.returncode == 0 and common.stdout.strip():
        return pathlib.Path(common.stdout.strip()).parent.parent / "MSIME-Windows"
    return ROOT.parent / "MSIME-Windows"


REFERENCE = reference_root()


def reference_labels() -> tuple[dict[str, str], str, str] | None:
    """The reference's own dropdown, at the tip of its default branch."""
    if not (REFERENCE / ".git").exists():
        return None
    symref = subprocess.run(
        ["git", "ls-remote", "--symref", "origin", "HEAD"],
        cwd=REFERENCE,
        capture_output=True,
        text=True,
        timeout=30,
    )
    candidates = []
    if symref.returncode == 0:
        match = re.search(r"^ref:\s+refs/heads/(\S+)\s+HEAD$", symref.stdout, re.M)
        if match:
            candidates.append(f"origin/{match.group(1)}")
    candidates += ["origin/develop", "origin/HEAD"]
    for ref in candidates:
        revision = subprocess.run(
            ["git", "rev-parse", ref], cwd=REFERENCE, capture_output=True, text=True
        )
        if revision.returncode != 0:
            continue
        sha = revision.stdout.strip()
        shown = subprocess.run(
            ["git", "show", f"{sha}:{PARTIAL}"], cwd=REFERENCE, capture_output=True, text=True
        )
        if shown.returncode != 0:
            continue
        found = re.findall(
            r'<div class="dropdown-item" data-value="([^"]+)">([^<]+)</div>', shown.stdout
        )
        # The partial repeats the same list once per scheme it applies to; both copies are the same
        # dropdown, so a disagreement between them is the reference's own problem to report.
        labels: dict[str, str] = {}
        for value, label in found:
            if value in labels and labels[value] != label:
                print(
                    f"FAIL the reference itself spells {value} both {labels[value]} and {label}",
                    file=sys.stderr,
                )
                return None
            labels[value] = label
        if labels:
            return labels, ref, sha
    return None


def shared_ui() -> dict[str, str]:
    source = (ROOT / "packages/ui/src/index.tsx").read_text(encoding="utf-8")
    block = re.search(
        r"const helpcodeSchemas: \[HelpcodeSchema, string\]\[\] = \[(.*?)\];", source, re.S
    )
    assert block, "the shared settings page no longer declares helpcodeSchemas"
    return dict(re.findall(r'\["([^"]+)",\s*"([^"]+)"\]', block.group(1)))


def linux_menus() -> dict[str, str]:
    source = (ROOT / "platforms/linux/src/core/HelpcodeSchemaNames.h").read_text(encoding="utf-8")
    block = re.search(r"kHelpcodeSchemaNames\{\{(.*?)\}\};", source, re.S)
    assert block, "the Linux table no longer declares kHelpcodeSchemaNames"
    return dict(re.findall(r'\{"([^"]+)",\s*"([^"]+)"\}', block.group(1)))


def ordered(identifiers: list[str], labels: list[str]) -> dict[str, str]:
    """Pair an identifier order with a label order, for the surfaces that keep the two apart."""
    assert len(identifiers) == len(labels), (identifiers, labels)
    return dict(zip(identifiers, labels))


def macos_settings() -> dict[str, str]:
    source = (ROOT / "platforms/macos/src/settings/AppearancePreferences.mm").read_text(
        encoding="utf-8"
    )
    identifiers = re.search(
        r"static NSArray<NSString \*> \*HelpcodeSchemas\(\) \{ return @\[(.*?)\]; \}", source
    )
    assert identifiers, "the macOS settings window no longer declares HelpcodeSchemas()"
    labels = re.search(r"\[schemas addItemsWithTitles:@\[(.*?)\]\];", source)
    assert labels, "the macOS settings window no longer titles the helpcode menu"
    return ordered(
        re.findall(r'@"([^"]+)"', identifiers.group(1)),
        re.findall(r'@"([^"]+)"', labels.group(1)),
    )


def macos_backend() -> dict[str, str]:
    source = (ROOT / "platforms/macos/src/backend/settings/BackendSettingsView.swift").read_text(
        encoding="utf-8"
    )
    labels = re.search(r'helpcode_schema":\s*names = \[([^\]]*)\]', source)
    assert labels, "the macOS backend page no longer names the helpcode schemes"
    # The backend page indexes its names by the stored integer, and that order is the C++ one.
    identifiers = (ROOT / "platforms/macos/src/settings/HelpcodeSchemaPreference.h").read_text(
        encoding="utf-8"
    )
    cases = re.findall(r'case (\d+): return "([^"]+)"', identifiers)
    default = re.search(r'default: return "([^"]+)"', identifiers)
    assert cases and default, "HelpcodeSchemaPreference.h no longer maps indices to identifiers"
    by_index = {int(index): value for index, value in cases}
    by_index[0] = default.group(1)
    return ordered(
        [by_index[index] for index in sorted(by_index)],
        re.findall(r'"([^"]+)"', labels.group(1)),
    )


SURFACES = {
    "the shared settings page": shared_ui,
    "the macOS settings window": macos_settings,
    "the macOS backend page": macos_backend,
    "the Linux menus": linux_menus,
}


def main() -> int:
    copies = {name: read() for name, read in SURFACES.items()}
    failures = 0

    # Every surface offers the same schemes. A surface missing one offers the user fewer schemes
    # than the product has; a surface with an extra one offers a scheme nothing else knows.
    identifiers = {name: set(labels) for name, labels in copies.items()}
    first = next(iter(identifiers))
    for name, found in identifiers.items():
        if found != identifiers[first]:
            missing = sorted(identifiers[first] - found)
            extra = sorted(found - identifiers[first])
            print(
                f"FAIL {name} offers a different set of schemes than {first}: "
                f"missing {missing}, extra {extra}",
                file=sys.stderr,
            )
            failures += 1

    resolved = reference_labels()
    if resolved is None:
        print("skipped the reference comparison: no MSIME-Windows checkout beside this repository")
        print(f"  expected a git checkout at {REFERENCE} carrying {PARTIAL}")
        truth, source = copies[first], first
    else:
        truth, ref, sha = resolved
        source = f"the reference ({ref} {sha[:8]})"
        for name, found in identifiers.items():
            unknown = sorted(found - set(truth))
            if unknown:
                print(
                    f"FAIL {name} offers schemes the reference does not have: {unknown}",
                    file=sys.stderr,
                )
                failures += 1

    for name, labels in copies.items():
        for value, label in sorted(labels.items()):
            expected = truth.get(value)
            if expected is not None and label != expected:
                print(
                    f"FAIL {name} calls {value} 「{label}」 where {source} calls it 「{expected}」",
                    file=sys.stderr,
                )
                failures += 1

    if failures:
        return 1
    print(
        f"helpcode schema labels: {len(copies)} surfaces name the same "
        f"{len(copies[first])} schemes, matching {source}"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
