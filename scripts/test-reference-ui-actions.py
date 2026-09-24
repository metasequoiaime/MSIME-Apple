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
import pathlib
import re
import subprocess
import sys

from reference_source import reference_root, show_file

ROOT = pathlib.Path(__file__).resolve().parent.parent
CONTRACT = "engine/contracts/webview/messages.json"


REFERENCE = reference_root(ROOT)

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
    "dictionaryRequest": "dictionary_request",
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
    "candidateWheel": "consume_candidate_wheel_delta",
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
    # The 中/英, 全/半 and punctuation buttons are turned into explicit mode requests by one function, and a click on 中/英 while dedicated English mode is on leaves that mode instead.
    "changeIMEMode": "toolbar_mode_command",
    "changeCharMode": "toolbar_mode_command",
    "changePuncMode": "toolbar_mode_command",
    "changeCharacterSet": "character_set_action_",
    "exitEnglishInputMode": "exit_dedicated_english",
}

# Where a counterpart may be found. Not the whole repository: a token that only appears in a test, in configuration, in documentation or in this file's own map is not an implementation. The native surfaces are Windows ones, so only the Windows platform tree counts; the settings surface is the shared Tauri application and page.
SEARCH_PATHS = [
    "apps/desktop/src",
    "apps/desktop/src-tauri/src",
    "crates",
    "packages/ui/src",
    "platforms/windows",
]
CODE_SUFFIXES = {".c", ".cc", ".cpp", ".h", ".hpp", ".rs", ".ts", ".tsx"}
# A match in any of these is a test or another platform's code, not the Windows implementation.
EXCLUDED_DIRS = {"tests", "test", "__tests__", "android", "ios", "linux", "macos", "harmony"}


def counts_as_implementation(path: str) -> bool:
    pure = pathlib.PurePosixPath(path)
    return (
        pure.suffix in CODE_SUFFIXES
        and pure.stem != "tests"
        and not EXCLUDED_DIRS & set(pure.parts[:-1])
    )


def contract_actions() -> tuple[dict[str, list[str]], str, str] | None:
    shown = show_file(ROOT, CONTRACT)
    if shown is None:
        return None
    text, ref, sha = shown
    contract = json.loads(text)
    actions = {
        name: body.get("surfaces", []) for name, body in contract.get("client", {}).items()
    }
    return actions, ref, sha


def implemented(token: str) -> bool:
    # Whole-word match: `dictionary_request` must not be satisfied by `cloud_dictionary_request`, nor `candidate_wheel` by `candidate_wheel_paging`.
    found = subprocess.run(
        ["git", "grep", "--fixed-strings", "--word-regexp", "-l", token, "--", *SEARCH_PATHS],
        cwd=ROOT,
        capture_output=True,
        text=True,
    )
    return any(counts_as_implementation(path) for path in found.stdout.splitlines())


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
