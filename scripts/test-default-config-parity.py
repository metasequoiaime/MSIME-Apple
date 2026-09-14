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
