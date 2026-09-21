#!/usr/bin/env python3
"""Every source file the reference builds its product from has an answer here.

Three checks already cover the reference from the outside: what it can be configured to do
(`test-windows-config-keys.py`), what its windows can ask of its host (`test-reference-ui-actions.py`)
and what it has shipped (`test-reference-feature-log.py`). None of them looks at the product's own
source tree, so none can answer the only question that settles a migration: is there anything in
there that nothing here corresponds to?

This walks all 274 `.cpp`/`.h` files under the reference's `windows/` (the TSF text service),
`server/` (the process that hosts the candidate window, the toolbar, the settings app and the
dictionaries) and `ui/src` (its own Direct2D widget framework), and requires each to resolve one of
three ways:

1. A file of the same name exists here, allowing for the naming conventions the two use.
2. `ANSWERED_BY` names the file that answers it under a different name, and that file exists.
3. `DELIBERATELY_ABSENT` records why nothing here needs to answer it.

A reference file matching none of the three is the finding: a file nobody has accounted for.

Names alone would be a weak check, which is why the second form points at a path that has to exist
rather than at a sentence. The reasons in the third form are the part to read sceptically - they are
where a migration hides what it did not do - so each one says what the user gets instead.

The reference checkout is optional. Without it the check reports what it would have needed and
passes, the same as every other stage that depends on something not every machine has.
"""

from __future__ import annotations

import os
import pathlib
import re
import subprocess
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
TREES = ["windows", "server/src", "ui/src"]


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

# Reference file stem -> the path here that answers it. The path must exist; a rename that is not
# also a move gets caught by rule 1 and never reaches this table.
ANSWERED_BY: dict[str, str] = {
    # Cloud and translation. The request logic is shared because no part of it is Windows-specific;
    # only the worker that runs it on the input queue stayed native.
    "cloud_ime": "platforms/windows/src/candidate/CloudCandidateWorker.cpp",
    "tencent_tmt": "crates/client-core/src/credential/translation.rs",
    "cloud_translation": "crates/client-core/src/credential/translation.rs",
    "custom_translation": "crates/client-core/src/translation.rs",
    "translation_gloss": "crates/client-core/src/translation.rs",
    "ai_assistant": "apps/desktop/src-tauri/src/ai.rs",
    "api_credential_test": "apps/desktop/src-tauri/src/ai.rs",
    # Statistics. Eleven files in the reference's Server, one shared document here plus the Windows
    # recording site; the aggregation the reference does in SQLite is done over the document.
    "stats_types": "crates/client-core/src/typing_statistics.rs",
    "stats_store": "crates/client-core/src/typing_statistics.rs",
    "stats_aggregate": "crates/client-core/src/typing_statistics.rs",
    "stats_overview": "packages/ui/src/settings/typing-statistics.tsx",
    "stats_frames": "packages/ui/src/settings/typing-statistics.tsx",
    "stats_pipe": "platforms/windows/src/input/TypingStatistics.h",
    "stats_collector": "platforms/windows/src/input/TypingStatistics.h",
    "stats_passthrough": "platforms/windows/src/input/TypingStatistics.h",
    "char_classify": "crates/client-core/src/typing_statistics.rs",
    # Dictionaries.
    "dictionary_manager": "crates/client-core/src/dictionary/import.rs",
    "dictionary_validation": "crates/client-core/src/dictionary/import.rs",
    "dictionary_page": "crates/engine-bridge/src/lib.rs",
    # Settings application. A Tauri window here, so the reference's Win32 host, its splash and its
    # launcher become the shell, the window background and the host-side launcher respectively.
    "settings_app": "apps/desktop/src-tauri/src/lib.rs",
    "settings_splash": "apps/desktop/src-tauri/src/lib.rs",
    "emoji_panel_splash": "apps/desktop/src-tauri/src/panel_window.rs",
    "settings_launcher": "platforms/windows/src/system/ShellLauncher.cpp",
    "ime_config": "crates/client-core/src/preferences.rs",
    # Candidate window, floating toolbar and tray menu: native here as they are there.
    "candidate_presenter": "platforms/windows/src/candidate/CandidateWindow.cpp",
    "candidate_view_model": "platforms/windows/src/candidate/CandidatePresentation.h",
    "candidate_size_estimator": "platforms/windows/src/candidate/CandidateCardSize.h",
    "candidate_wheel_paging": "platforms/windows/src/candidate/CandidateWheel.h",
    "candidate_selection_policy": "crates/input-runtime/src/runtime.rs",
    "candidate_skin_catalog": "crates/client-core/src/skin/catalog.rs",
    "floating_toolbar_presenter": "platforms/windows/src/candidate/FloatingToolbarWindow.cpp",
    "tray_menu_presenter": "platforms/windows/src/candidate/TrayMenuWindow.cpp",
    "ime_windows": "platforms/windows/src/candidate/CandidateWindow.cpp",
    "window_hook": "platforms/windows/src/input/MaintenanceHotkey.cpp",
    "surface_theme_config": "platforms/windows/src/voice/VoiceTheme.h",
    "svg_path_geometry": "platforms/windows/msimeui/src/Controls.cpp",
    # The document side of the reference's second candidate renderer. Its markup is vendored in
    # packages/ui/src/upstream/candidate-themes/; these two are the contracts that fill it.
    "candidate_window_template": "crates/client-core/src/candidate_document.rs",
    "inline_protocol": "crates/client-core/src/candidate_document.rs",
    # Third-party skin CSS reaching a webview document is the same policy question on both sides.
    # The shared layer parses it into a constructed stylesheet, scopes it, drops declarations whose
    # resources did not resolve, and discards @import along the way.
    "skin_css_policy": "packages/ui/src/skin/skin-toolbar-css.ts",
    # Voice input.
    "voice_batch_protocol": "platforms/windows/src/voice/VoiceControlMessage.cpp",
    "voice_control_dispatch": "platforms/windows/src/voice/VoiceControllerDispatch.h",
    "voice_input_overlay_utils": "platforms/windows/src/voice/WaveOverlayUtils.cpp",
    "mvi_utils": "platforms/windows/src/voice/VoiceProviders.h",
    # Sessions and the pipe. The reference's policy headers land on this repository's own
    # decomposition of the same protocol rather than one-for-one.
    "input_session": "platforms/windows/src/input/FocusedSession.h",
    "engine_input_session": "platforms/windows/src/ipc/ServerSession.cpp",
    "session_factory": "platforms/windows/src/ipc/SessionController.cpp",
    "event_listener": "platforms/windows/src/ipc/PipeListener.cpp",
    "active_client_state": "platforms/windows/src/ipc/SessionController.h",
    "candidate_ui_owner": "platforms/windows/src/candidate/CandidateMailbox.h",
    "focus_session_policy": "platforms/windows/src/input/FocusedSession.h",
    "outbound_session_state": "platforms/windows/src/ipc/ReplyComposer.h",
    "pipe_write_policy": "platforms/windows/src/ipc/PipeIo.h",
    "async_request_origin": "platforms/windows/src/ipc/PipeTicket.h",
    "ipc_protocol_limits": "platforms/windows/src/ipc/PipeMetadata.h",
    # Diagnostics.
    "candidate_diag_log": "platforms/windows/src/ipc/DiagnosticBatch.h",
    "ftb_diag_log": "platforms/windows/src/ipc/DiagnosticBatch.h",
    # Utilities that kept their job but not their name.
    "ime_paths": "platforms/windows/src/ipc/ServerResources.h",
    "ime_utils": "platforms/windows/src/entrypoints/server_main.cpp",
    "window_utils": "platforms/windows/src/candidate/WindowShadow.h",
    "single_instance": "platforms/windows/src/entrypoints/server_main.cpp",
    "chinese_converter": "platforms/windows/src/input/ChineseTextConversion.cpp",
    "base_structures": "platforms/windows/src/ipc/PipeMetadata.h",
    "defines": "platforms/windows/src/ipc/PipeMetadata.h",
    "client_fallback": "platforms/windows/tests/runtime/server_launch.cpp",
}

# Reference file stem -> why nothing here answers it. Each reason says what the user gets instead,
# because "handled differently" is the sentence that would make this check worthless.
DELIBERATELY_ABSENT: dict[str, str] = {
    # The WebView2 candidate backend. The reference can render its candidate window either with
    # Direct2D or with a WebView2 document; this repository has only the Direct2D one, and
    # `ui_backend` survives as a configuration contract (registered RUST_ONLY in the field-drift
    # gate) so a profile carrying it still loads.
    "windows_webview2": "The candidate window has one renderer here, Direct2D. See docs/windows-parity.md.",
    "ui_backend_policy": (
        "Chooses between the two renderers per surface. With one renderer there is nothing to "
        "choose, and the key is inert here (registered RUST_ONLY in the field-drift gate). What "
        "the policy also carries - that `d2d`, `webview` and `web` are spellings this product has "
        "written - is migrated into UiBackend's serde aliases, so a profile written by either side "
        "is read rather than rejected."
    ),
    "webview_utils": "WebView2 host helpers. The webview here is Tauri's, which brings its own.",
    # Engine-owned. These call into the Engine's own tables; the Engine is vendored whole, so the
    # calling code lives in the shared runtime rather than being reimplemented per platform.
    "emoji_ime": "Emoji lookup belongs to the Engine; the runtime asks it through the shared session.",
    "kaomoji_ime": "Kaomoji lookup belongs to the Engine, as above.",
    "english_ime": "English candidates belong to the Engine, as above.",
    # Infrastructure with no counterpart because the surrounding design differs.
    "serial_task_queue": (
        "Serialises the reference settings window's background work onto one thread. The settings "
        "window here is a Tauri application whose commands already run on its async runtime."
    ),
}


def reference_sources() -> tuple[list[str], str, str] | None:
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
        listing = subprocess.run(
            ["git", "ls-tree", "-r", "--name-only", sha, *TREES],
            cwd=REFERENCE,
            capture_output=True,
            text=True,
        )
        if listing.returncode != 0:
            continue
        sources = [
            path
            for path in listing.stdout.split()
            if path.endswith((".cpp", ".h", ".hpp"))
        ]
        return sources, ref, sha
    return None


def local_stems() -> set[str]:
    listing = subprocess.run(
        ["git", "ls-files"], cwd=ROOT, capture_output=True, text=True, check=True
    )
    return {pathlib.Path(path).stem.lower() for path in listing.stdout.split()}


def pascal(name: str) -> str:
    return "".join(part[:1].upper() + part[1:] for part in name.split("_"))


def main() -> int:
    resolved = reference_sources()
    if resolved is None:
        print("skipped: no MSIME-Windows checkout beside this repository to compare against")
        print(f"  expected a git checkout at {REFERENCE}")
        return 0
    sources, ref, sha = resolved
    stems = local_stems()

    by_name: list[str] = []
    renamed: list[str] = []
    absent: list[str] = []
    unaccounted: list[str] = []
    broken: list[tuple[str, str]] = []

    for path in sources:
        stem = pathlib.Path(path).stem
        if {stem.lower(), pascal(stem).lower(), stem.replace("_", "").lower()} & stems:
            by_name.append(path)
        elif stem in ANSWERED_BY:
            answer = ROOT / ANSWERED_BY[stem]
            (renamed if answer.exists() else broken).append(
                path if answer.exists() else (path, ANSWERED_BY[stem])
            )
        elif stem in DELIBERATELY_ABSENT:
            absent.append(path)
        else:
            unaccounted.append(path)

    for path in sorted(unaccounted):
        print(f"FAIL {path}: nothing here is recorded as answering this file", file=sys.stderr)
    for path, answer in sorted(broken):
        print(f"FAIL {path}: recorded as answered by `{answer}`, which does not exist", file=sys.stderr)
    if unaccounted or broken:
        print(
            "\nName the file here that answers it, or record why nothing needs to - saying what "
            "the user gets instead, not that it is handled differently.",
            file=sys.stderr,
        )
        return 1

    print(
        f"reference source inventory: all {len(sources)} sources of {ref} ({sha[:8]}) accounted for"
    )
    print(
        f"  {len(by_name)} by name, {len(renamed)} under a different name, "
        f"{len(absent)} deliberately absent"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
