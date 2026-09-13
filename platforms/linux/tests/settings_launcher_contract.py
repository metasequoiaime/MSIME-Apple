#!/usr/bin/env python3
"""Static contract checks for desktop settings panel aliases."""
from pathlib import Path

root = Path(__file__).resolve().parents[1]
launcher = (root / "msime-client-settings.in").read_text()
desktop = (root / "data/msime-client.desktop.in").read_text()
engine = (root / "ClientEngine.cpp").read_text()
assert "settings|about|dictionary|" in launcher
assert 'MSIME_CLIENT_PANEL:-}" = "dictionary"' in launcher
assert "Desktop Action Dictionary" in desktop
assert "--panel dictionary" in desktop
assert '"MSIME_CLIENT_ROUTE"' in engine
# A settings section must travel as "settings:<category>". The bare section name
# is not a route head, so the shared parser would reject it and the desktop shell
# would fall back to its default page.
assert 'MSIME_CLIENT_ROUTE=settings:$MSIME_CLIENT_SETTINGS_PAGE' in launcher
assert '"--route=$MSIME_CLIENT_ROUTE"' in launcher
assert '"settings:about"' in engine
assert 'MSIME_CLIENT_ROUTE=${MSIME_CLIENT_SETTINGS_PAGE:-$MSIME_CLIENT_PANEL}' not in launcher
for property_name in ("Learning", "FrequencyMode", "FrequencyTriggerCount", "FrequencyLinearStep"):
    assert f'"{property_name}"' in engine
assert "MenuPreference::Learning" in engine
assert "MenuPreference::FrequencyTriggerCount" in engine
assert "MenuPreference::FrequencyLinearStep" in engine
assert '"ShuangpinPreedit"' in engine
assert "MenuPreference::ShuangpinPreedit" in engine
assert 'shuangpin_preedit_uses_raw' in engine
print("settings launcher contract: ok")
