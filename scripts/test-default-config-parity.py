"""Keep platform factory configuration aligned with shared client defaults."""

import re
import tomllib
from pathlib import Path


ROOT = Path(__file__).resolve().parent.parent
CORE_PREFERENCES = ROOT / "crates/client-core/src/preferences.rs"
WINDOWS_DEFAULTS = ROOT / "platforms/windows/installer/config.default.toml"

core_source = CORE_PREFERENCES.read_text(encoding="utf-8")
mixed_input_default = re.search(
    r"impl Default for MixedInputPreferences\s*\{.*?minimum_prefix:\s*(\d+)",
    core_source,
    re.DOTALL,
)
assert mixed_input_default, "MixedInputPreferences default was not found"

with WINDOWS_DEFAULTS.open("rb") as config_file:
    windows_defaults = tomllib.load(config_file)

shared_minimum_prefix = int(mixed_input_default.group(1))
windows_minimum_prefix = windows_defaults["general"]["cn_en_mixed_input_min_chars"]
assert windows_minimum_prefix == shared_minimum_prefix, (
    "Windows cn_en_mixed_input_min_chars does not match "
    f"MixedInputPreferences::default(): {windows_minimum_prefix} != {shared_minimum_prefix}"
)

print(f"Windows mixed-input minimum prefix matches the shared default: {shared_minimum_prefix}")

voice_auth_default = re.search(
    r'impl Default for VoiceInputPreferences\s*\{.*?doubao_auth_mode:\s*"([^"]+)"\.into\(\)',
    core_source,
    re.DOTALL,
)
assert voice_auth_default, "VoiceInputPreferences Doubao auth default was not found"

shared_voice_auth_mode = voice_auth_default.group(1)
windows_voice_auth_mode = windows_defaults["voice_input"]["doubao_auth_mode"]
assert windows_voice_auth_mode == shared_voice_auth_mode, (
    "Windows doubao_auth_mode does not match VoiceInputPreferences::default(): "
    f"{windows_voice_auth_mode} != {shared_voice_auth_mode}"
)

print(f"Windows Doubao auth mode matches the shared default: {shared_voice_auth_mode}")

fallback_fonts_default = re.search(
    r"fn default_candidate_fallback_fonts\(\)\s*->\s*Vec<String>\s*\{(.*?)\}",
    core_source,
    re.DOTALL,
)
assert fallback_fonts_default, "candidate fallback font defaults were not found"

shared_fallback_fonts = re.findall(
    r'"([^"]+)"\.to_owned\(\)', fallback_fonts_default.group(1)
)
windows_fallback_fonts = windows_defaults["appearance"]["fallback_fonts"]
assert windows_fallback_fonts == shared_fallback_fonts, (
    "Windows fallback_fonts do not match the shared candidate font defaults: "
    f"{windows_fallback_fonts} != {shared_fallback_fonts}"
)

print(f"Windows fallback fonts match the shared defaults: {shared_fallback_fonts}")

translation_target_default = re.search(
    r"pub enum TranslationTargetLanguage\s*\{.*?#\[default\]\s*([A-Za-z0-9_]+)",
    core_source,
    re.DOTALL,
)
assert translation_target_default, "translation target language default was not found"

shared_translation_target = translation_target_default.group(1).lower()
windows_translation_target = windows_defaults["tencent_tmt"]["target_language"]
assert windows_translation_target == shared_translation_target, (
    "Windows target_language does not match TranslationTargetLanguage::default(): "
    f"{windows_translation_target} != {shared_translation_target}"
)

custom_translation_default = re.search(
    r"#\[derive\([^)]*Default[^)]*\)\]\s*"
    r"pub struct CustomTranslationPreferences\s*\{(.*?)\}",
    core_source,
    re.DOTALL,
)
assert custom_translation_default, "CustomTranslationPreferences derived default was not found"

custom_fields = re.findall(
    r"pub\s+([A-Za-z0-9_]+):\s*(bool|String),", custom_translation_default.group(1)
)
all_custom_fields = re.findall(
    r"pub\s+[A-Za-z0-9_]+\s*:", custom_translation_default.group(1)
)
assert len(custom_fields) == len(all_custom_fields), (
    "CustomTranslationPreferences has a field whose derived default is not supported"
)
shared_custom_translation = {
    name: False if field_type == "bool" else "" for name, field_type in custom_fields
}
windows_custom_translation = windows_defaults["custom_translation"]
assert windows_custom_translation == shared_custom_translation, (
    "Windows custom_translation does not match CustomTranslationPreferences::default(): "
    f"{windows_custom_translation} != {shared_custom_translation}"
)

print(
    "Windows translation target and custom provider match the shared defaults: "
    f"{shared_translation_target}, {shared_custom_translation}"
)

mouse_wheel_default = re.search(
    r"impl Default for NavigationPreferences\s*\{.*?mouse_wheel:\s*(true|false)",
    core_source,
    re.DOTALL,
)
assert mouse_wheel_default, "NavigationPreferences mouse-wheel default was not found"

shared_mouse_wheel = mouse_wheel_default.group(1) == "true"
windows_mouse_wheel = windows_defaults["general"]["paging_mouse_wheel"]
assert windows_mouse_wheel == shared_mouse_wheel, (
    "Windows paging_mouse_wheel does not match NavigationPreferences::default(): "
    f"{windows_mouse_wheel} != {shared_mouse_wheel}"
)

print(f"Windows mouse-wheel paging matches the shared default: {shared_mouse_wheel}")
