#!/usr/bin/env python3
"""Every feature the reference has shipped has been looked at.

The configuration keys say what the reference can be told to do; the interface actions say what its
windows can ask its host to do. Neither notices a feature that changes behaviour without adding a
key or a message - the candidate window that stopped strobing under load, the pinyin buffer that
grew a ceiling, the installer page that stopped putting people online without asking.

The reference's own changelog does notice those, because it is generated from its commits: a
`feat:` commit becomes a bullet. So this keeps the list of bullets that have been read, together
with where each one landed here, and fails on a bullet nobody has looked at yet. The point is not
that every feature must exist here - several deliberately do not - but that none goes unnoticed.

The reference checkout is optional. Without it the check reports what it would have needed and
passes, the same as every other stage that depends on something not every machine has.
"""

from __future__ import annotations

import pathlib
import re
import sys

from reference_source import reference_root, show_file

ROOT = pathlib.Path(__file__).resolve().parent.parent
CHANGELOG = "CHANGELOG.md"


REFERENCE = reference_root(ROOT)

# Each feature bullet the reference has shipped, and what became of it here. The text is the bullet
# with its trailing commit links stripped, exactly as the changelog writes it.
#
# Keep the answers specific. "Already supported" is the sentence that makes this check worthless;
# name the file, the constant or the decision, so the next person can check the claim rather than
# trusting it.
REVIEWED: dict[str, str] = {
    "**contracts:** sync engine product lock contract": (
        "Engine-side release plumbing. The Engine is pinned here by engine-lock.json and "
        "scripts/fetch_engine.py, which is this repository's equivalent and is checked by the "
        "vendored-engine stage of verify-local.sh."
    ),
    "**contracts:** verify shared product lock primitives": (
        "Same release plumbing as the bullet above."
    ),
    "**installer:** 首次安装时询问云候选，不再默认静默联网": (
        "platforms/windows/installer/msime_setup.iss: CreateInputOptionPage after the licence "
        "page, skipped on upgrade, writing only [general].cloud_candidates of a config.toml this "
        "install created. macOS: platforms/macos/src/input/InputController.mm activateServer: "
        "prompt (requestCloudCandidatesConsentIfNeeded) plus the MSIMEClientCloudCandidatesConsent "
        "key in platforms/macos/src/settings/AppearancePreferences.mm, asked on a fresh profile only."
    ),
    "**installer:** include release PDB symbols": (
        "Packaging. platforms/windows/installer/Prepare-PackageFiles.ps1 collects what this "
        "product ships; symbol publication is a release decision for the repository owner."
    ),
    "**langbar:** switch IME mode icons by system light/dark theme": (
        "platforms/windows/tsf/LanguageBar/LanguageBar.cpp: IsSystemDarkMode reads "
        "Personalize\\SystemUsesLightTheme and ResolveThemeIconIndex picks the icon. Assets are "
        "tsf/assets/{cn,en,jp,cap}-{light,dark}.ico - one pair more than the reference, which has "
        "no Japanese indicator."
    ),
    "**product:** keep WebView and native contracts in one locked combination": (
        "Release plumbing; see the product lock bullets above."
    ),
    "**product:** lock release inputs and share negotiated IPC contracts": (
        "Release plumbing; see the product lock bullets above."
    ),
    "**product:** lock the shared-session stack and validate dictionary formats": (
        "Dictionary format validation is crates/client-core/src/dictionary/import.rs, which is "
        "where the shared import path enforces the same rules."
    ),
    "**product:** require locked commits to be on their default branch at release": (
        "Release plumbing; see the product lock bullets above."
    ),
    "**product:** validate and lock the shared-session release combination": (
        "Release plumbing; see the product lock bullets above."
    ),
    "**release:** mark automatically built releases in the title and notes": (
        "Release process, not product behaviour."
    ),
    "**release:** separate the automatic build channel from the release channel": (
        "Release process, not product behaviour."
    ),
    "**server:** show translations in horizontal candidate windows": (
        "platforms/windows/src/candidate/CandidateWindow.cpp appends `  · <translation>` to the "
        "candidate label in both the horizontal and the flyout paths."
    ),
    "also sync double/single char status when switch windows": (
        "platforms/windows/src/input/InputQueue.cpp accepts DoubleSingleByteSwitch so ModeMailbox "
        "can publish the host's notification to the toolbar."
    ),
    "notify UI process on punctuation mode change": (
        "InputQueue.cpp routes PuncSwitch to FocusedSession::set_chinese_punctuation, and the "
        "toolbar repaints on a changed chinese_punctuation in FloatingToolbarWindow.cpp."
    ),
    "set max len limit for pinyin input": (
        "MAX_PINYIN_LENGTH in platforms/windows/tsf/Header/Define.h, applied in Key/KeyEventSink.cpp "
        "to the deferred key budget, the shadow raw input and the reported input length."
    ),
    "support exact candidate character commits": (
        "Word-to-character commits without appended punctuation: "
        "platforms/windows/tests/input/word_character_policy.cpp covers the policy."
    ),
    "sync IME status to UI on thread focus and punctuation switch": (
        "InputQueue.cpp carries the punctuation state on StatusSnapshot and FocusRestored, so a "
        "client taking focus reports it rather than the toolbar guessing."
    ),
    "synchronous tsf and server double/single char status via ipc": (
        "Same DoubleSingleByteSwitch path as the window-switch bullet above."
    ),
}


def changelog_features() -> tuple[set[str], str, str] | None:
    shown = show_file(ROOT, CHANGELOG)
    if shown is None:
        return None
    text, ref, sha = shown
    return parse(text), ref, sha


def parse(text: str) -> set[str]:
    """The bullets under every `### Features` heading, without their commit links."""
    features: set[str] = set()
    in_features = False
    for line in text.splitlines():
        if line.startswith("### "):
            in_features = line.strip() == "### Features"
            continue
        if line.startswith("## "):
            in_features = False
            continue
        if in_features and line.startswith("* "):
            # `* text ([abc1234](url))` and `* text ([#12](url)) ([abc1234](url))`
            features.add(re.sub(r"\s*\(\[.*$", "", line[2:]).strip())
    return features


def main() -> int:
    resolved = changelog_features()
    if resolved is None:
        print("skipped: no MSIME-Windows checkout beside this repository to compare against")
        print(f"  expected a git checkout at {REFERENCE} carrying {CHANGELOG}")
        return 0
    features, ref, sha = resolved

    unreviewed = sorted(feature for feature in features if feature not in REVIEWED)
    for feature in unreviewed:
        print(f"FAIL {feature}: the reference shipped this and nobody here has looked at it yet", file=sys.stderr)
    if unreviewed:
        print(
            "\nRead it against this repository, then record in REVIEWED where it landed - the "
            "file, the constant or the decision, not just that it was seen.",
            file=sys.stderr,
        )
        return 1

    gone = sorted(feature for feature in REVIEWED if feature not in features)
    print(f"reference feature log: all {len(features)} feature bullets of {ref} ({sha[:8]}) reviewed")
    if gone:
        # The changelog is append-only in practice, so this means a bullet was reworded. Worth
        # naming: a reworded entry would otherwise reappear as unreviewed and be recorded twice.
        print(f"  recorded but no longer in the changelog: {', '.join(gone)}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
