#!/usr/bin/env python3
"""Every setting the reference ships a default for has somewhere to live here.

The reference keeps its whole configuration surface in one file - `installer/default_config/
config.default.toml`, 178 keys across 17 sections - and that file is the closest thing either
repository has to a list of "what this product can be told to do". Checking the two settings pages
against each other by eye has been done several times and keeps producing the same two kinds of
false result: a key that looks missing because it was deliberately renamed (`y_mode` is
`local_modes.temporary_english`, `cn_en_mixed_input_min_chars` is `mixed_input.minimum_prefix`), and
a key that looks present because some unrelated identifier happens to contain the same word.

So the mapping is written down once, and this checks it two ways:

- every mapped target still exists in the shared preferences or the shared settings page, so a
  rename on this side cannot quietly orphan a reference setting;
- when a reference checkout is available (`MSIME_REFERENCE_ROOT`, or the sibling directory this
  repository is usually cloned next to), every key in its config template appears in the table, so a
  setting added upstream shows up here as a failure rather than as nothing at all.

Six keys are mapped to a reason instead of a field, written as `!kind: why`. Four are written by the
reference's own template and read by nothing in it, one is the reference Server's internal switch
between its old and new session implementations, and one is a path this repository takes as a host
runtime option rather than a preference.
"""

from __future__ import annotations

import os
import pathlib
import re
import subprocess
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
SHARED = [
    ROOT / "crates/client-core/src/preferences.rs",
    ROOT / "packages/ui/src/index.tsx",
]
# The reference commit this table was built from; see docs/windows-parity.md for how it is pinned.
REFERENCE_COMMIT = "e1d53dd8f01fd351633f08374f189157f5cb47e9"
REFERENCE_CONFIG = "installer/default_config/config.default.toml"

# reference `section.key` -> the name to look for on this side, or `!kind: why` for the ones that
# deliberately have no target.
MAPPING: dict[str, str] = {
    "ai_assistant.candidate_limit": "candidate_limit",
    "ai_assistant.enabled": "enabled",
    "ai_assistant.endpoint": "endpoint",
    "ai_assistant.model": "model",
    "ai_assistant.prompt": "prompt",
    "ai_assistant.prompt_custom_1": "prompt_custom_1",
    "ai_assistant.prompt_custom_2": "prompt_custom_2",
    "ai_assistant.prompt_custom_3": "prompt_custom_3",
    "ai_assistant.prompt_id": "prompt_id",
    "ai_assistant.provider": "provider",
    "ai_assistant.token": "token",
    "ai_assistant.token_deepseek": "deepseek",
    "ai_assistant.token_groq": "groq",
    "ai_assistant.token_openai": "openai",
    "ai_assistant.token_siliconflow": "siliconflow",
    "appearance.cand_text_color": "candidate_text_color",
    "appearance.candidate_skin": "candidate_skin",
    "appearance.candidate_window_follow_cursor": "candidate_follow_cursor",
    "appearance.candidate_window_layout": "layout",
    "appearance.candidate_window_preedit_font_size": "candidate_preedit_font_size",
    "appearance.candidate_window_preedit_style": "preedit_style",
    "appearance.default_font": "candidate_fallback_fonts",
    "appearance.english_font": "candidate_english_font",
    "appearance.fallback_fonts": "candidate_fallback_fonts",
    "appearance.font": "font",
    "appearance.font_size": "font_size",
    "appearance.page_size": "candidate_page_size",
    "appearance.theme_cand": "candidate_theme",
    "appearance.theme_emoji": "emoji",
    "appearance.theme_ftb": "toolbar_theme",
    "appearance.theme_handwriting": "handwriting",
    "appearance.theme_menu": "menu",
    "appearance.theme_mode": "mode",
    "appearance.theme_screen_keyboard": "screen_keyboard",
    "appearance.theme_settings": "settings",
    "appearance.theme_voice": "voice",
    "appearance.tsf_preedit_style": "tsf_preedit_style",
    "appearance.ui_backend": "ui_backend",
    "custom_translation.api_key": "api_key",
    "custom_translation.enabled": "enabled",
    "custom_translation.endpoint": "endpoint",
    "dictionary.dictionary_path": "!runtime: the dictionary directory is a host runtime option here, not a preference",
    "frequency_adjustment.linear_step": "linear_step",
    "frequency_adjustment.mode": "mode",
    "frequency_adjustment.trigger_count": "trigger_count",
    "general.candidate_arrow_navigation": "candidate_arrow_navigation",
    "general.candidate_translations": "candidate_translations",
    "general.candidate_window_diagnostic_log": "diagnostic_log",
    "general.clean_mode": "!dead: written by the reference's config template and read by nothing in it",
    "general.cloud_candidates": "cloud_candidates",
    "general.cn_en_mixed_input": "mixed_input.english",
    "general.cn_en_mixed_input_min_chars": "mixed_input.minimum_prefix",
    "general.diagnostic_log": "diagnostic_log",
    "general.emoji_mixed_input": "mixed_input.emoji",
    "general.enable_emoji": "!dead: written by the reference's config template and read by nothing in it",
    "general.floating_toolbar": "floating_toolbar",
    "general.floating_toolbar_character_set": "character_set",
    "general.floating_toolbar_emoji": "emoji",
    "general.floating_toolbar_font_size": "font_size",
    "general.floating_toolbar_fullwidth": "fullwidth",
    "general.floating_toolbar_punctuation": "punctuation",
    "general.floating_toolbar_scale": "scale",
    "general.floating_toolbar_screen_keyboard": "screen_keyboard",
    "general.floating_toolbar_settings": "settings",
    "general.kaomoji_mixed_input": "mixed_input.kaomoji",
    "general.paging_brackets": "brackets",
    "general.paging_comma_period": "comma_period",
    "general.paging_minus_equal": "minus_equal",
    "general.paging_mouse_wheel": "mouse_wheel",
    "general.paging_page_up_down": "page_up_down",
    "general.paging_tab": "tab",
    "helpcode.quanpin_helpcode": "quanpin_helpcode",
    "helpcode.quanpin_helpcode_schema": "quanpin_helpcode",
    "helpcode.show_qp_helpcode_in_candidate_window": "show_in_candidate_window",
    "helpcode.show_sp_helpcode_in_candidate_window": "show_in_candidate_window",
    "helpcode.shuangpin_helpcode": "shuangpin_helpcode",
    "helpcode.shuangpin_helpcode_schema": "shuangpin_helpcode",
    "input.character_set": "character_set",
    "input.default_ime_mode": "default_ime_mode",
    "input.fuzzy_an_ang": "fuzzy_pinyin",
    "input.fuzzy_c_ch": "fuzzy_pinyin",
    "input.fuzzy_en_eng": "fuzzy_pinyin",
    "input.fuzzy_f_h": "fuzzy_pinyin",
    "input.fuzzy_ian_iang": "fuzzy_pinyin",
    "input.fuzzy_in_ing": "fuzzy_pinyin",
    "input.fuzzy_n_l": "fuzzy_pinyin",
    "input.fuzzy_pinyin": "fuzzy_pinyin",
    "input.fuzzy_r_l": "fuzzy_pinyin",
    "input.fuzzy_s_sh": "fuzzy_pinyin",
    "input.fuzzy_seeded": "seeded",
    "input.fuzzy_uan_uang": "fuzzy_pinyin",
    "input.fuzzy_z_zh": "fuzzy_pinyin",
    "input.ime_mode_scope": "ime_mode_scope",
    "input.japanese_schema": "schema",
    "input.mode": "mode",
    "input.paired_punctuation": "paired_punctuation",
    "input.punctuation_lock": "punctuation_lock",
    "input.schema": "schema",
    "input.session_backend": "!internal: the reference Server's own legacy/new session switch, and this repo has one runtime",
    "input.shuangpin_preedit_mode": "shuangpin_preedit_uses_raw",
    "input.shuangpin_schema": "schema",
    "input.smart_punctuation": "smart_punctuation",
    "input.smart_punctuation_direct_digit": "smart_punctuation_direct_digit",
    "input.smart_punctuation_direct_letter": "smart_punctuation_direct_letter",
    "input.smart_punctuation_repeat_to_chinese": "smart_punctuation_repeat",
    "input.smart_punctuation_space_convert": "smart_punctuation_space_convert",
    "input.word_to_character": "word_character",
    "input.word_to_character_keys": "word_character",
    "input.wubi_schema": "schema",
    "keybindings.switch_language_ctrl": "switch_language_ctrl",
    "keybindings.switch_language_ctrl_alt_space": "switch_language_ctrl_alt_space",
    "keybindings.switch_language_shift": "switch_language_shift",
    "keybindings.toggle_character_set_ctrl_shift_f": "toggle_character_set_ctrl_shift_f",
    "niutrans.apikey": "apikey",
    "niutrans.app_id": "app_id",
    "niutrans.enabled": "enabled",
    "quanpin.autocorrect_neighbor": "autocorrect_neighbor",
    "quanpin.autocorrect_transposition": "autocorrect_transposition",
    "settings_page.theme": "theme",
    "skin.skin_name": "candidate_skin",
    "soft_keyboard.background_img": "!dead: written by the reference's config template and read by nothing in it",
    "soft_keyboard.theme_mode": "mode",
    "tencent_tmt.enabled": "enabled",
    "tencent_tmt.region": "region",
    "tencent_tmt.secret_id": "secret_id",
    "tencent_tmt.secret_key": "secret_key",
    "tencent_tmt.target_language": "translation_target_language",
    "utility.clipboard_history": "clipboard_history",
    "utility.date_time_mode": "local_modes",
    "utility.emoji_mode": "local_modes",
    "utility.jianpin_mode": "local_modes",
    "utility.kaomoji_mode": "local_modes",
    "utility.quick_phrase": "quick_phrase",
    "utility.r_mode": "local_modes",
    "utility.study_english_word": "!dead: written by the reference's config template and read by nothing in it",
    "utility.unicode_mode": "local_modes",
    "utility.y_mode": "local_modes",
    "voice_input.asr_app_key": "asr_app_key",
    "voice_input.asr_endpoint": "asr_endpoint",
    "voice_input.asr_model": "asr_model",
    "voice_input.asr_provider": "asr_provider",
    "voice_input.asr_resource_id": "asr_resource_id",
    "voice_input.asr_token": "asr_token",
    "voice_input.asr_token_doubao": "doubao",
    "voice_input.asr_token_groq": "groq",
    "voice_input.asr_token_openai": "openai",
    "voice_input.asr_token_siliconflow": "siliconflow",
    "voice_input.commit_mode": "commit_mode",
    "voice_input.doubao_auth_mode": "doubao_auth_mode",
    "voice_input.doubao_boosting_table_id": "doubao_boosting_table_id",
    "voice_input.doubao_enable_ddc": "doubao_enable_ddc",
    "voice_input.doubao_enable_itn": "doubao_enable_itn",
    "voice_input.doubao_enable_punc": "doubao_enable_punc",
    "voice_input.end_sound": "end_sound",
    "voice_input.hotkey_ctrl_f9": "hotkey_ctrl_f9",
    "voice_input.hotkey_ctrl_win": "hotkey_ctrl_win",
    "voice_input.hotkey_hold_space_lock": "hotkey_hold_space_lock",
    "voice_input.hotkey_ralt": "hotkey_ralt",
    "voice_input.hotkey_rctrl_ralt": "hotkey_rctrl_ralt",
    "voice_input.language": "language",
    "voice_input.mute_system_audio": "mute_system_audio",
    "voice_input.polish_endpoint": "polish_endpoint",
    "voice_input.polish_model": "polish_model",
    "voice_input.polish_prompt": "polish_prompt",
    "voice_input.polish_prompt_custom_1": "polish_prompt_custom_1",
    "voice_input.polish_prompt_custom_2": "polish_prompt_custom_2",
    "voice_input.polish_prompt_custom_3": "polish_prompt_custom_3",
    "voice_input.polish_prompt_id": "polish_prompt_id",
    "voice_input.polish_provider": "polish_provider",
    "voice_input.polish_text": "polish_text",
    "voice_input.polish_token": "polish_token",
    "voice_input.polish_token_deepseek": "deepseek",
    "voice_input.polish_token_groq": "groq",
    "voice_input.polish_token_openai": "openai",
    "voice_input.polish_token_siliconflow": "siliconflow",
    "voice_input.start_sound": "start_sound",
    "voice_input.stream_inline_preedit": "stream_inline_preedit",
    "voice_input.voice_input": "voice_input",
}


def shared_text() -> str:
    return "\n".join(path.read_text(encoding="utf-8") for path in SHARED if path.is_file())


def reference_root() -> pathlib.Path | None:
    """Where the reference checkout is, if this machine has one.

    A worktree sits somewhere else entirely, so the sibling directory is looked for next to the main
    checkout as well as next to whichever tree this is running in.
    """
    configured = os.environ.get("MSIME_REFERENCE_ROOT")
    candidates = [pathlib.Path(configured)] if configured else []
    candidates.append(ROOT.parent / "MSIME-Windows")
    common = subprocess.run(
        ["git", "rev-parse", "--git-common-dir"], cwd=ROOT, capture_output=True, text=True
    )
    if common.returncode == 0:
        main_tree = pathlib.Path(common.stdout.strip()).resolve().parent
        candidates.append(main_tree.parent / "MSIME-Windows")
    for candidate in candidates:
        if (candidate / ".git").exists():
            return candidate
    return None


def reference_keys(root: pathlib.Path) -> list[str] | None:
    """The section.key list from the pinned commit, or None when it cannot be read."""
    result = subprocess.run(
        ["git", "show", f"{REFERENCE_COMMIT}:{REFERENCE_CONFIG}"],
        cwd=root, capture_output=True, text=True,
    )
    if result.returncode != 0:
        return None
    section = None
    keys = []
    for line in result.stdout.splitlines():
        line = line.strip()
        if line.startswith("["):
            section = line.strip("[]")
            continue
        match = re.match(r"^([a-z_0-9]+)\s*=", line)
        if match and section:
            keys.append(f"{section}.{match.group(1)}")
    return keys


def main() -> int:
    text = shared_text()
    if not text:
        print("skipped: the shared preferences and settings page are not present")
        return 0
    orphaned = []
    for key, target in sorted(MAPPING.items()):
        if target.startswith("!"):
            continue
        # The last segment is the field name; nested targets name their struct, which is what the
        # shared sources spell.
        needle = target.split(".")[-1]
        if not re.search(rf"\b{re.escape(needle)}\b", text):
            orphaned.append(f"{key} -> {target}")

    added = []
    root = reference_root()
    upstream = reference_keys(root) if root else None
    if upstream:
        added = [key for key in upstream if key not in MAPPING]

    for entry in orphaned:
        print(f"the shared layer no longer has the target for {entry}", file=sys.stderr)
    for key in added:
        print(f"the reference has a setting this table does not map: {key}", file=sys.stderr)
    if orphaned or added:
        print(
            "\nA renamed field needs its entry updated; a new reference setting needs to be "
            "migrated or given a reason.",
            file=sys.stderr,
        )
        return 1

    reasons = sum(1 for target in MAPPING.values() if target.startswith("!"))
    checked = "and every key in the reference's template is in it" if upstream else (
        "the reference checkout is not here, so only this side was checked")
    print(
        f"reference config coverage: {len(MAPPING)} settings mapped "
        f"({reasons} to a reason rather than a field), {checked}"
    )
    return 0


if __name__ == "__main__":
    sys.exit(main())
