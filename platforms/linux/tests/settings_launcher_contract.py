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
print("settings launcher contract: ok")
