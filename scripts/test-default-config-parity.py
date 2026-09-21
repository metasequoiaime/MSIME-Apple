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
# This asserted 5 and called it the Windows baseline. The reference's own factory configuration
# (MSIME-Windows, installer/default_config/config.default.toml) has said 2 since the file was added
# and has never said 5, and 2 is also the shared default - so shipping 5 here meant English
# candidates appeared after five letters out of the box where the reference shows them after two,
# with this assertion standing in the way of noticing.
assert windows_minimum_prefix == shared_minimum_prefix, (
    "Windows cn_en_mixed_input_min_chars must match the shared default "
    f"({shared_minimum_prefix}): {windows_minimum_prefix}"
)

print(
    "Windows mixed-input minimum prefix matches the reference and the shared default: "
    f"{windows_minimum_prefix}"
)

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

fuzzy_rule_enum = re.search(
    r"pub enum FuzzyPinyinRule\s*\{(.*?)\n\}", core_source, re.DOTALL
)
assert fuzzy_rule_enum, "FuzzyPinyinRule identifiers were not found"
shared_fuzzy_rule_ids = re.findall(
    r'#\[serde\(rename = "([^"]+)"\)\]', fuzzy_rule_enum.group(1)
)
assert shared_fuzzy_rule_ids, "FuzzyPinyinRule has no serialized identifiers"

fuzzy_preferences_default = re.search(
    r"#\[derive\([^)]*Default[^)]*\)\]\s*"
    r"#\[serde\(deny_unknown_fields\)\]\s*"
    r"pub struct FuzzyPinyinPreferences\s*\{(.*?)\}",
    core_source,
    re.DOTALL,
)
assert fuzzy_preferences_default, "FuzzyPinyinPreferences derived default was not found"
fuzzy_fields = fuzzy_preferences_default.group(1)
assert re.search(r"pub enabled:\s*bool", fuzzy_fields)
assert re.search(r"pub rules:\s*BTreeSet<FuzzyPinyinRule>", fuzzy_fields)
assert re.search(r"pub seeded:\s*bool", fuzzy_fields)

windows_input = windows_defaults["input"]
assert windows_input["fuzzy_pinyin"] is False, "Windows fuzzy-pinyin default must be disabled"
assert windows_input["fuzzy_seeded"] is False, "Windows fuzzy-pinyin seed marker must be false"
windows_fuzzy_rules = {
    key.removeprefix("fuzzy_").replace("_", "-"): value
    for key, value in windows_input.items()
    if key.startswith("fuzzy_") and key not in {"fuzzy_pinyin", "fuzzy_seeded"}
}
assert set(windows_fuzzy_rules) == set(shared_fuzzy_rule_ids), (
    "Windows fuzzy-pinyin rule keys do not match shared rule identifiers: "
    f"{sorted(windows_fuzzy_rules)} != {sorted(shared_fuzzy_rule_ids)}"
)
assert not any(windows_fuzzy_rules.values()), "Windows fuzzy-pinyin rules must default to off"

print(
    "Windows fuzzy-pinyin factory keys match the shared disabled default: "
    f"{len(shared_fuzzy_rule_ids)} rules"
)

# Smart punctuation rewrites a character the user already saw land, so the
# Windows baseline ships all five switches off. The installed TOML is only a
# template — the running Server reads the shared preferences document — so the
# two have to be checked against each other rather than assumed to agree.
smart_punctuation_default = re.search(
    r"fn smart_punctuation_default\(\) -> bool \{\s*(.+?)\s*\}",
    core_source,
    re.DOTALL,
)
assert smart_punctuation_default, "smart_punctuation_default was not found"
assert smart_punctuation_default.group(1) == "!cfg!(windows)", (
    "the shared first-run default for smart punctuation must be off on Windows "
    f"and unchanged elsewhere, not: {smart_punctuation_default.group(1)}"
)

windows_smart_punctuation = {
    key: value
    for key, value in windows_defaults["input"].items()
    if key.startswith("smart_punctuation")
}
assert len(windows_smart_punctuation) == 5, (
    "the Windows template must ship all five smart-punctuation switches: "
    f"{sorted(windows_smart_punctuation)}"
)
assert not any(windows_smart_punctuation.values()), (
    "Windows smart-punctuation switches must default to off: "
    f"{sorted(key for key, value in windows_smart_punctuation.items() if value)}"
)
# The space rewrite has no equivalent in the reference and changes a character the user already saw
# land, so it is off until asked for. The two halves of 智能标点 follow the parent instead: the
# reference has one switch there and this page shows its description verbatim - ASCII after a letter
# or a digit - so halves that were off on their own left the parent on and doing nothing. Following
# the parent keeps a fresh Windows profile with the whole family off, which is what the template
# above ships and what this check exists for.
assert re.search(
    r"#\[serde\(default\)\]\s*pub smart_punctuation_space_convert: bool", core_source
), "smart_punctuation_space_convert must default to off on every host, matching the template"
for field in ("smart_punctuation_direct_digit", "smart_punctuation_direct_letter"):
    assert re.search(
        rf'#\[serde\(default = "smart_punctuation_default"\)\]\s*(?:///[^\n]*\n\s*)*pub {field}: bool',
        core_source,
    ), f"{field} must follow the 智能标点 default, which is off on Windows"

print(
    "Windows smart punctuation is off on a fresh profile, as its template ships: "
    f"{len(windows_smart_punctuation)} switches"
)

# Statistics count what a person types, so the template and the shared default have to agree that
# they start off. The reference says so in its own feature list, and a template that shipped them
# on would turn them on for every fresh profile regardless of what the shared code says.
statistics = windows_defaults["statistics"]
assert statistics["enabled"] is False, "the statistics template must ship them off"
assert re.search(
    r"fn enabled_by_default\(\) -> bool \{\s*(?:///[^\n]*\n\s*)*false\s*\}",
    (ROOT / "crates/client-core/src/typing_statistics.rs").read_text(encoding="utf-8"),
), "the shared statistics default must be off, matching the template"

# An unrecognised retention is read as forever. The template must name one the code knows, or the
# value it ships would silently mean something other than what it says.
retentions = {"forever", "30d", "90d", "180d", "365d"}
assert statistics["retention"] in retentions, (
    f"unknown statistics retention {statistics['retention']!r}; "
    f"the shared store understands {sorted(retentions)}"
)
statistics_source = (ROOT / "crates/client-core/src/typing_statistics.rs").read_text(
    encoding="utf-8"
)
for spelling in retentions - {"forever"}:
    assert f'"{spelling}" =>' in statistics_source, (
        f"the template offers {spelling} but the shared store does not parse it"
    )

print(f"Windows statistics ship off with retention {statistics['retention']!r}")
