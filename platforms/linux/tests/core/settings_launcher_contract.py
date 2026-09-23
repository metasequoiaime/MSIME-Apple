#!/usr/bin/env python3
"""Static contract checks for desktop settings panel aliases."""
import os
import subprocess
import tempfile
from pathlib import Path

root = Path(__file__).resolve().parents[2]
launcher = (root / "data/msime-client-settings.in").read_text()
desktop = (root / "data/msime-client.desktop.in").read_text()
engine = (root / "src/core/ClientEngine.cpp").read_text()
assert "settings|about|help|feedback|dictionary|" in launcher
assert 'MSIME_CLIENT_PANEL:-}" = "dictionary"' in launcher
assert "Desktop Action Dictionary" in desktop
assert "--panel dictionary" in desktop
assert '"MSIME_CLIENT_ROUTE"' in engine
# A settings section must travel as "settings:<category>". The bare section name
# is not a route head, so the shared parser would reject it and the desktop shell
# would fall back to its default page.
assert 'MSIME_CLIENT_ROUTE=settings:$MSIME_CLIENT_SETTINGS_PAGE' in launcher
assert '"--route=$MSIME_CLIENT_ROUTE"' in launcher
# The host builds the route rather than spelling each one out, so the literal to
# look for is the prefix it prepends. The assertion here named a whole route
# ("settings:about") that no version of this file has ever contained - and with
# the test unable to resolve its own paths, nothing ever said so.
assert 'std::string("settings:")' in engine
assert 'MSIME_CLIENT_ROUTE=${MSIME_CLIENT_SETTINGS_PAGE:-$MSIME_CLIENT_PANEL}' not in launcher
for property_name in ("Learning", "FrequencyMode", "FrequencyTriggerCount", "FrequencyLinearStep"):
    assert f'"{property_name}"' in engine
assert "MenuPreference::Learning" in engine
assert "MenuPreference::FrequencyTriggerCount" in engine
assert "MenuPreference::FrequencyLinearStep" in engine
assert '"ShuangpinPreedit"' in engine
assert "MenuPreference::ShuangpinPreedit" in engine
assert 'shuangpin_preedit_uses_raw' in engine
assert '"WubiCodeHint"' in engine
assert 'wubi_code_hint' in engine
assert "MenuPreference::WubiCodeHint" in engine

# Without a prepared file the launcher still opens the window, which shows the first-run page for the user locator; an installed system configuration keeps precedence over that page.
with tempfile.TemporaryDirectory() as scratch:
    scratch = Path(scratch)
    system_config = scratch / "system/runtime-options.json"
    script = scratch / "bin/msime-client-settings"
    script.parent.mkdir()
    script.write_text(launcher.replace("@MSIME_SETTINGS_SYSTEM_CONFIG@", str(system_config)))
    desktop_binary = scratch / "bin/msime-client-desktop"
    desktop_binary.write_text('#!/bin/sh\nprintf %s "$MSIME_CLIENT_HOST_OPTIONS"\n')
    for path in (script, desktop_binary):
        path.chmod(0o755)
    environment = {
        key: value
        for key, value in os.environ.items()
        if key not in ("MSIME_CLIENT_HOST_OPTIONS", "MSIME_IBUS_OPTIONS", "MSIME_CLIENT_PANEL")
    }
    environment["XDG_CONFIG_HOME"] = str(scratch / "config")

    def launched() -> str:
        return subprocess.run([str(script)], env=environment, check=True, capture_output=True, text=True).stdout

    assert launched() == str(scratch / "config/msime-client/runtime-options.json")
    system_config.parent.mkdir()
    system_config.write_text("{}")
    assert launched() == str(system_config)

    # About, Help and Feedback each open their own settings section. Unlisted in the --panel case they exit 2, and passed through bare they would not parse as a route, leaving the window on its home page.
    desktop_binary.write_text('#!/bin/sh\nprintf "%s|%s|%s|%s" "$*" "$MSIME_CLIENT_PANEL" "${MSIME_CLIENT_SETTINGS_PAGE:-}" "$MSIME_CLIENT_ROUTE"\n')
    for key in ("MSIME_CLIENT_SETTINGS_PAGE", "MSIME_CLIENT_ROUTE"):
        environment.pop(key, None)

    def launched_panel(panel: str) -> str:
        return subprocess.run([str(script), "--panel", panel], env=environment, check=True, capture_output=True, text=True).stdout

    for page in ("about", "help", "feedback", "dictionary"):
        assert launched_panel(page) == f"--route=settings:{page}|settings|{page}|settings:{page}", page
    assert launched_panel("handwriting") == "--route=handwriting|handwriting||handwriting"
    usage = subprocess.run([str(script), "--help"], env=environment, check=True, capture_output=True, text=True).stdout
    assert "|help|feedback|" in usage

print("settings launcher contract: ok")
