#!/usr/bin/env python3
"""Every setting the reference ships a default for has a field here that still exists.

`test-windows-config-keys.py` already asks the other half of this question - whether the reference
has a configuration key this repository's Windows template does not - and asks it against the tip of
the reference's default branch. This one does not repeat that. What it adds is the mapping that
check has no room for: which field on *this* side answers each reference setting, so a rename here
cannot quietly orphan one.

The distinction matters because the two products name almost nothing the same way. Checking the
settings pages against each other by eye has been done several times and keeps producing the same
two false results: a key that looks missing because it was deliberately renamed (`y_mode` is
`local_modes.temporary_english`, `cn_en_mixed_input_min_chars` is `mixed_input.minimum_prefix`), and
a key that looks present because some unrelated identifier happens to contain the same word. The
mapping is written down once, here, and every target is checked to still exist.

Six keys are mapped to a reason instead of a field, written as `!kind: why`. Four are written by the
reference's own template and read by nothing in it, one is the reference Server's internal switch
between its old and new session implementations, and one is a path this repository takes as a host
runtime option rather than a preference.

A field is also checked to be *named in the shared settings page*, not only present in the
preferences crate. The arrangement this client is built around puts shared behaviour and its
interface in the Tauri page, so a setting with a field and nothing on that page is supported on
paper: it exists, it round-trips, and no user can change it. `PLATFORM_LOCAL` records the ones
whose subject does not exist here at all. Finding this check's first entry also corrected a
mapping - `general.candidate_arrow_navigation` pointed at the serde alias rather than at `arrows`,
the field the page actually spells, which made a reachable setting look unreachable.
"""

from __future__ import annotations

import pathlib
import re
import sys
import tomllib

ROOT = pathlib.Path(__file__).resolve().parent.parent
SHARED = [
    ROOT / "crates/client-core/src/preferences.rs",
    ROOT / "packages/ui/src/index.tsx",
    # The typing statistics switch and retention live in their own document rather than in the preferences.
    ROOT / "crates/client-core/src/typing_statistics.rs",
]
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
    # The field is `arrows`; `candidate_arrow_navigation` is the serde alias kept for profiles
    # written before the rename, and naming the alias here hid the fact that the page spells the
    # field.
    "general.candidate_arrow_navigation": "arrows",
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
    "statistics.enabled": "enabled",
    "statistics.retention": "retention",
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


# Targets allowed to have no control on the shared settings page, and why. Each is a setting whose
# subject does not exist here rather than one this client has not got round to.
# Targets whose field name is composed at run time rather than written out, so a literal search
# cannot see the control that reaches them. The three voice polish slots are written by
# `polish_prompt_${slot}` in the 润色提示词 textarea's onChange, which is the control for all three.
COMPOSED_AT_RUNTIME: dict[str, str] = {
    "polish_prompt_custom_1": "written through `polish_prompt_${slot}` by the 润色提示词 textarea",
    "polish_prompt_custom_2": "written through `polish_prompt_${slot}` by the 润色提示词 textarea",
    "polish_prompt_custom_3": "written through `polish_prompt_${slot}` by the 润色提示词 textarea",
}

PLATFORM_LOCAL: dict[str, str] = {
    "ui_backend": (
        "Chooses between the reference's Direct2D surfaces and its WebView2 ones. The candidate "
        "window, floating toolbar and input-method menu are drawn natively by each platform here, "
        "so there is no second backend to pick."
    ),
}


def page_text() -> str:
    """The shared settings page, which is a directory rather than a file.

    `index.tsx` holds the page, but controls are extracted into components beside it - the
    candidate font controls, including the fallback-font editor, live in
    `candidate/candidate-font-controls.tsx`. Reading only `index.tsx` makes every such control
    invisible, and the first version of this check did exactly that.
    """
    root = ROOT / "packages/ui/src"
    if not root.is_dir():
        return ""
    return "\n".join(
        path.read_text(encoding="utf-8")
        for path in sorted(root.rglob("*"))
        if path.suffix in {".tsx", ".ts"} and path.is_file()
    )


# The Windows template that `test-windows-config-keys.py` holds to the reference's key set. Every key it
# ships has to be in `MAPPING`, otherwise a reference setting can sit in the template with no answer on
# this side and this check never looks at it; `[statistics]` was missing from the mapping that way.
TEMPLATE = ROOT / "platforms/windows/installer/config.default.toml"


def template_keys() -> set[str]:
    if not TEMPLATE.is_file():
        return set()
    keys: set[str] = set()

    def walk(prefix: list[str], value: object) -> None:
        if isinstance(value, dict):
            for key, child in value.items():
                walk(prefix + [key], child)
        else:
            keys.add(".".join(prefix))

    walk([], tomllib.loads(TEMPLATE.read_text(encoding="utf-8")))
    return keys


def shared_text() -> str:
    return "\n".join(path.read_text(encoding="utf-8") for path in SHARED if path.is_file())


def main() -> int:
    text = shared_text()
    if not text:
        print("skipped: the shared preferences and settings page are not present")
        return 0
    unmapped = sorted(template_keys() - MAPPING.keys())
    for key in unmapped:
        print(
            f"{key} is in the Windows template but not in MAPPING: record the field that answers it, "
            f"or `!kind: why` if nothing does.",
            file=sys.stderr,
        )
    if unmapped:
        return 1

    orphaned = []
    for key, target in sorted(MAPPING.items()):
        if target.startswith("!"):
            continue
        # The last segment is the field name; nested targets name their struct, which is what the
        # shared sources spell.
        needle = target.split(".")[-1]
        if not re.search(rf"\b{re.escape(needle)}\b", text):
            orphaned.append(f"{key} -> {target}")

    # And a field alone is not the setting. This client's arrangement is that shared behaviour and
    # its interface both live in the Tauri settings page, so a reference setting with a field here
    # and no mention at all on that page is supported on paper only. The check above is satisfied
    # by `preferences.rs` on its own, which is exactly the state that hides such a setting.
    #
    # What this can see is the field's name appearing in the page's source, which is weaker than
    # "a control is rendered for it": a type declaration alone would satisfy it. It catches the
    # failure that actually happens - a preference added to the crate and nothing done in the page
    # - and not a control deleted while its type stays. Reported wording says only that much.
    unreachable = []
    for key, target in sorted(MAPPING.items()):
        if target.startswith("!") or target in PLATFORM_LOCAL:
            continue
        needle = target.split(".")[-1]
        if not re.search(rf"\b{re.escape(needle)}\b", page_text()):
            unreachable.append(f"{key} -> {target}")

    # A declaration is not code. A field can be added to the page's types and defaults and then
    # touched by nothing, which looks the same to a name search as a setting that works.
    #
    # This says "nothing reads or writes it", not "no control renders it", and the difference is
    # real: deleting the fallback-font editor from its component leaves this quiet, because
    # `candidate-font-family.ts` and `resolved-candidate-fonts.ts` still read the field for
    # validation and font resolution. Measured, not assumed. Telling a control apart from a helper
    # needs the JSX parsed, which is more machinery than this check is worth; what it catches is a
    # field declared and wired to nothing at all.
    declaration_only = []
    page = page_text().splitlines()
    for key, target in sorted(MAPPING.items()):
        name = target.split(".")[-1]
        if target.startswith("!") or target in PLATFORM_LOCAL or name in COMPOSED_AT_RUNTIME:
            continue
        mentions = [line for line in page if re.search(rf"\b{re.escape(name)}\b", line)]
        if mentions and all(
            re.fullmatch(rf"{re.escape(name)}\??:\s*[^=]+;", line.strip())
            or re.fullmatch(rf"{re.escape(name)}:\s*.+,", line.strip())
            for line in mentions
        ):
            declaration_only.append(f"{key} -> {target}")

    for entry in orphaned:
        print(f"the shared layer no longer has the target for {entry}", file=sys.stderr)
    for entry in declaration_only:
        print(
            f"{entry} appears in the shared settings page only as a declaration or a default: "
            f"nothing in the shared tree reads or writes it.",
            file=sys.stderr,
        )
    unreachable += declaration_only
    for entry in unreachable:
        print(
            f"{entry} has a field but its name appears nowhere in the shared settings page, so "
            f"nothing there can be reaching it. Add the control, or record it in PLATFORM_LOCAL "
            f"with the reason.",
            file=sys.stderr,
        )
    if unreachable:
        return 1
    if orphaned:
        print(
            "\nA renamed field needs its entry updated. A setting the reference has *added* is "
            "test-windows-config-keys.py's half of this question, not this one's.",
            file=sys.stderr,
        )
        return 1

    reasons = sum(1 for target in MAPPING.values() if target.startswith("!"))
    print(
        f"reference config coverage: {len(MAPPING)} settings mapped "
        f"({reasons} to a reason rather than a field), every target present"
    )
    print(
        f"  and named in the shared settings page, bar {len(PLATFORM_LOCAL)} recorded as "
        f"platform-local"
    )
    return 0


if __name__ == "__main__":
    sys.exit(main())
