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
assert 'msime-shuangpin-preedit' in source
assert 'msime-wubi-code-hint' in source
print("Fcitx5 addon metadata passed")
