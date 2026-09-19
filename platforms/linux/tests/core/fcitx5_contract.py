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
assert '${MSIME_ENABLE_PACKAGING}' in cmake
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
print("Fcitx5 addon metadata passed")
