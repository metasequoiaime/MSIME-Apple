#!/usr/bin/env python3
"""Every action the reference's user interface can ask its host to perform has a counterpart here.

`engine/contracts/webview/messages.json` is the reference's own machine-readable inventory of what
its four surfaces - settings, floating toolbar, candidate window, tray menu - are able to ask for.
It is the closest thing either product has to a complete list of user-facing capability, and unlike
a page-by-page reading it is generated rather than remembered: when the reference gains a
capability, it gains an entry here.

That is the point of checking it. `statsRequest` grew an `openDirectory` action when the reference
added its statistics page, and nothing in this repository noticed for as long as nobody happened to
reread that page. This check notices.

The comparison cannot be by name the way `test-windows-config-keys.py` compares configuration keys:
the reference's surfaces are WebView2 documents that post messages to a host, and here three of the
four are native code with no message in sight. So each action is mapped to the thing that answers
it - a token that must still be findable in this repository - or recorded as deliberately absent
with the reason. An action the reference has and this map does not is the finding: a capability
that arrived upstream while nobody was looking.

The reference checkout is optional. Without it the check reports what it would have needed and
passes, the same as every other stage that depends on something not every machine has.
"""

from __future__ import annotations

import json
import os
import pathlib
import re
import subprocess
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
CONTRACT = "engine/contracts/webview/messages.json"


def reference_root() -> pathlib.Path:
    """Where the reference checkout is.

    Beside the *main* worktree, not beside this one: development here happens in short-lived
    worktrees under `~/worktrees`, so resolving against the current checkout would make this check
    skip forever and look like it was passing. `MSIME_REFERENCE_DIR` overrides it.
    """
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
        main = pathlib.Path(common.stdout.strip()).parent
        return main.parent / "MSIME-Windows"
    return ROOT.parent / "MSIME-Windows"


REFERENCE = reference_root()

# Every client action in the reference's contract, and what answers it here.
#
# A string is a token that must still appear somewhere under the paths searched below - the
# capability's own name in this repository, not a description of it. A tuple is (reason,) for an
# action with deliberately no counterpart, and the reason has to say why the user loses nothing,
# because "handled differently" is exactly what somebody would write to make this quiet.
ANSWERED_BY: dict[str, str | tuple[str]] = {
    # Settings surface. Here the settings window is the Tauri application, and each of these is a
    # command it exposes to the shared page.
    "configRequest": "load_preferences",
    "configUpdate": "save_preferences",
    "skinCatalogRequest": "scan_skin_catalog",
    "openSkinDirectory": "open_skin_directory",
    "openHandwritingPanel": "open_handwriting_panel",
    "openKeyboardPanel": "open_keyboard_panel",
    "restartServer": "restart_input_method",
    "openExternalUrl": "openExternalUrl",
    "apiCredentialTest": "test_credential",
    "dictionaryRequest": "dictionary",
    "statsRequest": "load_typing_statistics",
    "copyText": (
        "The webview here is a full browser context with the clipboard API, and the shared page "
        "writes to it directly. The reference routes it through the host because its WebView2 "
        "surface is not given clipboard access.",
    ),
    # Window chrome. The reference draws its own title bar inside the WebView2 document and has to
    # ask the host to move, size and close the window; the Tauri window is a real window with the
    # platform's own decorations, so none of these exist to be asked for.
    "dragStart": ("The window has native decorations; the compositor moves it.",),
    "resizeStart": ("The window has native decorations; the compositor sizes it.",),
    "resizeHitTest": ("The window has native decorations; the compositor hit-tests it.",),
    "windowControl": ("The window has native decorations, including its own buttons.",),
    "maximizeButtonRect": (
        "Windows 11 snap layouts need the maximize button's rectangle only when the button is "
        "drawn by the document. A native caption button is already known to the shell.",
    ),
    "focus": ("A native window takes focus through the window manager, not through its content.",),
    # Candidate surface. Native Direct2D here, so these are code paths rather than messages.
    "candidate": "select_candidate",
    "delete": "CandidateMenuCommand::Remove",
    "pin": "CandidateMenuCommand::PinToTop",
    "fixPosition": "CandidateMenuCommand::FixAtPosition",
    "clearPosition": "CandidateMenuCommand::ClearFixedPosition",
    "candidateWheel": "candidate_wheel",
    "contextMenuResize": "candidate_menu_size",
    "contextMenuClosed": "CandidateFlyoutWindow",
    "candidatePointerArmed": (
        "Arming exists because a WebView2 candidate window cannot tell a real pointer move from "
        "the one the compositor synthesises when the window is repositioned under a still mouse. "
        "A Direct2D window receives the real messages and has nothing to disambiguate.",
    ),
    "candidatePointerMotion": (
        "Same as candidatePointerArmed: the native window gets WM_MOUSEMOVE directly.",
    ),
    "candidateFrameProbe": (
        "Instrumentation for the reference's WebView2 rendering path, reporting how long a frame "
        "took to reach the document. There is no document in this candidate window.",
    ),
    "candidatePointerProbe": (
        "Instrumentation for the same path, recording synthesised against real pointer "
        "coordinates. Nothing here synthesises them.",
    ),
    "contentTruncated": (
        "A document reports when its content overflowed the window the host sized for it. The "
        "native surfaces here measure their content before sizing, so the window is never the "
        "wrong size to begin with.",
    ),
    # Tray menu surface.
    "floatingToggle": "TrayMenuCommand::ToggleFloatingToolbar",
    "settings": "TrayMenuCommand::OpenSettings",
    "about": "TrayMenuCommand::OpenAbout",
    "emojiSymbols": "TrayMenuCommand::OpenEmojiPanel",
    "keyboardPanel": "TrayMenuCommand::OpenKeyboardPanel",
    "handwritingPanel": "TrayMenuCommand::OpenHandwritingPanel",
    "voiceInput": "TrayMenuCommand::ToggleVoiceInput",
    # Floating toolbar surface.
    "ready": (
        "A document telling its host it finished loading. The toolbar here is a native window "
        "that is created ready.",
    ),
    "openSettings": "TrayMenuCommand::OpenSettings",
    "openEmojiPanel": "TrayMenuCommand::OpenEmojiPanel",
    "changeIMEMode": "toolbar_icon",
    "changeCharMode": "floating_toolbar_fullwidth",
    "changePuncMode": "floating_toolbar_punctuation",
    "changeCharacterSet": "floating_toolbar_character_set",
    "exitEnglishInputMode": "english_mode",
}

# Where a counterpart may be found. Not the whole repository: a token that only appears in a test or
# in this file's own map is not an implementation.
SEARCH_PATHS = [
    "apps/desktop/src",
    "apps/desktop/src-tauri/src",
    "crates",
    "packages/ui/src",
    "platforms",
]


def contract_actions() -> tuple[dict[str, list[str]], str, str] | None:
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
    # Offline, or a remote that does not advertise one. `origin/HEAD` is a symbolic ref written once
    # at clone time and can point at a release branch that lags; it is the last resort and the ref
    # actually used is always printed.
    candidates += ["origin/develop", "origin/HEAD"]
    for ref in candidates:
        revision = subprocess.run(
            ["git", "rev-parse", ref], cwd=REFERENCE, capture_output=True, text=True
        )
        if revision.returncode != 0:
            continue
        sha = revision.stdout.strip()
        shown = subprocess.run(
            ["git", "show", f"{sha}:{CONTRACT}"], cwd=REFERENCE, capture_output=True, text=True
        )
        if shown.returncode != 0:
            continue
        contract = json.loads(shown.stdout)
        actions = {
            name: body.get("surfaces", []) for name, body in contract.get("client", {}).items()
        }
        return actions, ref, sha
    return None


def implemented(token: str) -> bool:
    found = subprocess.run(
        ["git", "grep", "--fixed-strings", "-l", token, "--", *SEARCH_PATHS],
        cwd=ROOT,
        capture_output=True,
        text=True,
    )
    return bool(found.stdout.strip())


def main() -> int:
    resolved = contract_actions()
    if resolved is None:
        print("skipped: no MSIME-Windows checkout beside this repository to compare against")
        print(f"  expected a git checkout at {REFERENCE} carrying {CONTRACT}")
        return 0
    actions, ref, sha = resolved

    unmapped = sorted(name for name in actions if name not in ANSWERED_BY)
    for name in unmapped:
        surfaces = ", ".join(actions[name]) or "no surface"
        print(
            f"FAIL {name} ({surfaces}): the reference's interface can ask for this and nothing "
            f"here answers it",
            file=sys.stderr,
        )

    missing = sorted(
        (name, token)
        for name, token in ANSWERED_BY.items()
        if name in actions and isinstance(token, str) and not implemented(token)
    )
    for name, token in missing:
        print(
            f"FAIL {name}: answered by `{token}`, which no longer appears in this repository",
            file=sys.stderr,
        )

    if unmapped or missing:
        print(
            "\nMigrate the capability, or record in ANSWERED_BY why this repository needs nothing "
            "for it - with the reason, not just an entry.",
            file=sys.stderr,
        )
        return 1

    deliberate = sum(
        1 for name, token in ANSWERED_BY.items() if name in actions and isinstance(token, tuple)
    )
    stale = sorted(name for name in ANSWERED_BY if name not in actions)
    print(
        f"reference ui actions: all {len(actions)} client actions of {ref} ({sha[:8]}) are "
        f"answered, {deliberate} of them deliberately without a counterpart"
    )
    if stale:
        # Not a failure: the reference dropping an action is its decision, and this repository is
        # allowed to keep whatever it built. Naming them keeps the map from silently growing.
        print(f"  the reference no longer has: {', '.join(stale)}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
