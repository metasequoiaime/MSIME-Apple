#!/usr/bin/env python3
"""Check the Fcitx5 addon metadata without requiring a running desktop."""
from pathlib import Path
import configparser
import sys

root = Path(__file__).resolve().parents[2]
addon = configparser.ConfigParser()
addon.read(root / "fcitx5/msime.conf")
assert addon["Addon"]["Name"] == "MSIME"
assert addon["Addon"]["Type"] == "SharedLibrary"
assert addon["Addon"]["Library"] == "libmsime-fcitx5"
entry = configparser.ConfigParser()
entry.read(root / "fcitx5/msime-inputmethod.conf")
assert entry["InputMethod"]["Addon"] == "msime"
assert entry["InputMethod"]["LangCode"] == "zh_CN"
cmake = (root / "CMakeLists.txt").read_text()
assert "MSIME_ENABLE_FCITX5" in cmake
# 默认值跟着环境走而不是跟着打包开关：装了 Fcitx5 开发包的机器就构建这个并列入口，
# 打包路径仍然无条件包含它。此前默认取自 MSIME_ENABLE_PACKAGING，也就是默认关闭。
assert "find_package(Fcitx5Core" in cmake
assert "MSIME_ENABLE_PACKAGING OR Fcitx5Core_FOUND" in cmake
assert cmake.index('option(MSIME_ENABLE_FCITX5') < cmake.index('include(cmake/packaging.cmake)')
packaging = (root / "cmake/packaging.cmake").read_text()
assert "if(MSIME_ENABLE_FCITX5)" in packaging
assert "fcitx5 (>= 5.0.20)" in packaging

source = (root / "fcitx5/FcitxEngine.cpp").read_text()
assert 'tsf_preedit_style' in source
assert 'candidate_preedit_style' in source
assert 'FcitxSchemeBooleanAction' in source
assert '英文输入模式' in source
assert 'msime-shuangpin-preedit' in source
assert 'msime-wubi-code-hint' in source
assert 'msime-shuangpin-profile' in source
assert 'cycleShuangpinProfile' in source
assert 'cycleFrequencyMode' in source
assert 'msime-frequency' in source
assert 'msime-frequency-trigger' in source
assert 'msime-frequency-step' in source
assert 'msime-candidate-theme' in source
assert 'cycleCandidateTheme' in source
assert 'msime-candidate-skin' in source
assert 'cycleCandidateSkin' in source
assert 'candidate_skin_catalog' in source
assert 'msime_client_load_preferences' in source
assert 'applyContextOverrides' in source
assert 'effectiveContextSnapshot' in source
assert 'msime_client_update_preferences' in source
assert 'applyPreferenceSnapshot' in source
assert 'saveStringPreference("character_width"' in source
assert 'snapshot["preferences"]["character_width"]' in source
assert 'saveBooleanPreference("traditional_chinese_output"' in source
assert 'preferences_["traditional_chinese_output"]' in source
assert 'waitForPreferenceSave' in source
assert 'if (fixedPosition > 0) actions.push_back(make(20, "取消固定"));' in source
assert 'item->source() == 0 || item->source() == 1 || item->source() == 4' in source
assert 'source_(candidate.value("source", 0u))' in source
assert 'text_(candidate.at("text").get<std::string>())' in source
assert 'fixed_position_(candidate.value("fixed_position", 0u))' in source
assert 'item->text()))' in source
assert 'item->fixedPosition()' in source
assert 'state_.session_ != item->session()' in source
assert '!state_.ic_.hasFocus() || !state_.input_enabled_' in source
assert 'state_.privateInput() || state_.session_ != item->session()' in source
assert 'voice_cancelled_' in source
assert 'msime_voice_stream_inline_enabled(' in source
assert 'voice_preedit_' in source and 'voice_transcript_' in source
assert 'msime_voice_result_or_transcript(' in source
assert 'clipboard_generation_' in source
assert 'result.value("_path", std::string{}) == clipboard_path_' in source
assert 'result.value("_generation", uint64_t{}) == clipboard_generation_' in source
assert 'const auto generation = clipboard_generation_' in source
assert 'cloud_clipboard_generation_' in source
assert 'result.value("_socket", std::string{}) == cloud_clipboard_socket_' in source
assert 'result.value("_generation", uint64_t{}) == cloud_clipboard_generation_' in source
assert 'emoji_generation_' in source
assert 'result.value("_generation", uint64_t{}) == emoji_generation_' in source
assert 'result["_generation"] = generation' in source
assert 'item.value("source", 255u) == source' in source
assert 'Json candidates = Json::array();' in source
assert 'std::string panelPreview(const std::string &text)' in source
assert 'fcitx::utf8::nextNChar(text.begin(), 40)' in source
assert 'text.substr(0, 40)' not in source
assert 'if (voice_job_.valid()) {' in source
assert 'voice cancellation does not wait for the provider future' in (root / 'fcitx5/tests/native.cpp').read_text()
assert 'msime-helpcode-schema' in source
assert 'cycleHelpcodeSchema' in source
assert 'toggleLocalMode' in source
assert 'msime-local-unicode' in source
assert 'msime-local-temporary-japanese' in source
# The four configurable mode chords, and which host state each is read from. The
# settings page shows all four switches for this platform; this host answered none
# of them until it read `keybindings`, and a wiring that quietly went away would
# look exactly like it did before - a switch that saves and does nothing.
for name in ("mode_shift_enabled_", "mode_ctrl_enabled_",
             "mode_ctrl_alt_space_enabled_", "character_set_shortcut_enabled_"):
    assert name in source, name
for key in ("switch_language_shift", "switch_language_ctrl",
            "switch_language_ctrl_alt_space", "toggle_character_set_ctrl_shift_f"):
    assert key in source, key
# A bare modifier is measured on its release, and only when nothing else was typed
# while it was held; the press half only arms it.
assert "pure_shift_candidate_" in source and "pure_ctrl_candidate_" in source
assert "modifier_toggle_deadline_" in source
assert "event.isRelease()" in source
# Ctrl+Space and Ctrl+Alt+Space must be able to return from English passthrough.
# The old gate sat above the chord and made the switch one-way.
assert source.index("return toggleInputMode();") < source.index(
    "if (!input_enabled_) return false;"
)
# The startup mode belongs to the input context, not to each Engine session, or
# refocusing would put the default back over the mode the user chose.
assert "ime_mode_chosen_" in source
assert 'preferences_.value("default_ime_mode", "chinese")' in source
assert 'voicePreferences.value("hotkey_hold_space_lock", voice_hotkey_hold_space_lock_)' in source
assert 'voice_options_.value("asr_provider", std::string{"doubao"})' in source
assert 'fcitx_system_dark_theme()' in source
assert 'refreshSystemTheme()' in source
assert 'system_theme_probe_due_' in source
assert 'pkg_check_modules(GIO REQUIRED IMPORTED_TARGET gio-2.0)' in (root / "fcitx5/CMakeLists.txt").read_text()
assert 'fcitx_system_dark_theme' in (root / "fcitx5/SystemTheme.cpp").read_text()

# Native Fcitx5 sessions use the same non-focus-stealing X11/Wayland voice
# surface as IBus when one is available, while the auxiliary panel remains the
# explicit fallback for headless or unsupported desktops.
for marker in ("WaveOverlayModel", "WaveOverlaySurface", "WaveOverlayX11Surface",
               "WaveOverlayWaylandSurface", "create_fcitx_wave_overlay_surface",
               "MSIME_WAVE_OVERLAY_BACKEND", "updateVoiceOverlay", "hideVoiceOverlay",
               "wave_overlay_.set_input_level", "wave_overlay_.actions_visible = true"):
    assert marker in source, marker
assert "WaveOverlayX11Surface.cpp" in (root / "fcitx5/CMakeLists.txt").read_text()
assert "WaveOverlayWaylandSurface.cpp" in (root / "fcitx5/CMakeLists.txt").read_text()

# The floating toolbar's eight component switches decide what the "工具栏" submenu
# contains. They decided nothing here before, while the settings page showed all of
# them for this platform, so each switch is pinned to the entry it governs.
assert "msime-toolbar" in source
assert "rebuildToolbarMenu" in source and "refreshToolbar" in source
for key, default in (("english_mode", "true"), ("fullwidth", "true"),
                     ("punctuation", "true"), ("character_set", "true"),
                     ("emoji", "true"), ("screen_keyboard", "false"),
                     ("settings", "true")):
    assert f'toolbar.value("{key}", {default})' in source, key
# The entries are the existing actions, not copies: a toolbar entry that behaved
# differently from the status-area action beside it would be a second
# implementation of the same toggle.
for action in ("input_mode_action_", "english_action_", "width_action_",
               "chinese_punctuation_action_", "traditional_action_",
               "desktop_emoji_action_", "keyboard_action_", "settings_action_"):
    assert f"append(" in source and action in source, action
# A rebuild removes exactly what it added; the menu is shared across contexts.
assert "toolbar_entries_" in source

print("Fcitx5 addon metadata passed")
