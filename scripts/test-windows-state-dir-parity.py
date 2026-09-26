#!/usr/bin/env python3
"""Keep the Windows state-directory names in step between C++ and Rust.

The TSF DLL and the Server resolve their state root through `platforms/windows/common/StateDirectory.h`. The Rust host (`crates/host-windows`, `server_state_directory`) keeps its own copy of the same order, and the shell it serves has to land on the directory the Server chose. A renamed environment variable, registry key, value or folder on one side would split state silently, so this compares the names and the registry flags and fails on any drift. It also fails when the TSF or the Server grows its own copy of the lookup again instead of calling the shared header.
"""

from __future__ import annotations

import pathlib
import re
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
HEADER = ROOT / "platforms/windows/common/StateDirectory.h"
RUST = ROOT / "crates/host-windows/src/lib.rs"
CALLERS = [
    ROOT / "platforms/windows/tsf/HostOptionsPaths.cpp",
    ROOT / "platforms/windows/src/entrypoints/server_main.cpp",
]


def header_constant(source: str, name: str) -> str:
    match = re.search(rf'inline constexpr wchar_t {name}\[\] = L"((?:[^"\\]|\\.)*)";', source)
    if not match:
        raise SystemExit(f"{HEADER.relative_to(ROOT)}: {name} not found")
    return match.group(1)


def rust_body(source: str, name: str) -> str:
    match = re.search(rf"\bfn {name}\b.*?\n\}}\n", source, re.DOTALL)
    if not match:
        raise SystemExit(f"{RUST.relative_to(ROOT)}: fn {name} not found")
    return match.group(0)


def main() -> int:
    header = HEADER.read_text(encoding="utf-8")
    rust = RUST.read_text(encoding="utf-8")
    resolver = rust_body(rust, "server_state_directory")
    registry = rust_body(rust, "installed_data_directory")
    failures: list[str] = []

    environment = header_constant(header, "state_directory_environment_variable")
    if f'std::env::var_os("{environment}")' not in resolver:
        failures.append(f"server_state_directory does not read {environment}")
    folder = header_constant(header, "state_directory_folder_name")
    if f'.join("{folder}")' not in resolver:
        failures.append(f"server_state_directory does not fall back to {folder}")
    if "installed_data_directory()" not in resolver:
        failures.append("server_state_directory does not consult the installer's DataDir")
    # Rust string literals escape backslashes the same way C++ does, so the source text compares directly.
    key = header_constant(header, "state_directory_registry_key")
    if f'"{key}\\0"' not in registry:
        failures.append(f"installed_data_directory does not open {key}")
    value = header_constant(header, "state_directory_registry_value")
    if f'"{value}\\0"' not in registry:
        failures.append(f"installed_data_directory does not read {value}")
    for flag in ("HKEY_LOCAL_MACHINE", "RRF_RT_REG_SZ", "RRF_SUBKEY_WOW6464KEY"):
        if header.count(flag) < 1:
            failures.append(f"{HEADER.relative_to(ROOT)} no longer uses {flag}")
        if flag not in registry:
            failures.append(f"installed_data_directory no longer uses {flag}")

    for caller in CALLERS:
        text = caller.read_text(encoding="utf-8")
        relative = caller.relative_to(ROOT)
        if "resolve_state_directory()" not in text:
            failures.append(f"{relative} no longer calls msime::windows::resolve_state_directory")
        for literal in (environment, value):
            if f'"{literal}"' in text:
                failures.append(f"{relative} spells {literal} itself instead of using common/StateDirectory.h")

    if failures:
        for failure in failures:
            print(f"state-directory parity: {failure}", file=sys.stderr)
        return 1
    shown_key = key.replace("\\\\", "\\")
    print(f"Windows state-directory names match between C++ and Rust: {environment}, HKLM\\{shown_key}\\{value}, {folder}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
