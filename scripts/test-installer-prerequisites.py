#!/usr/bin/env python3
"""The Windows installer must say what is missing before it installs.

Neither the WebView2 Runtime nor the Visual C++ redistributable ships in the
package: the first has its own evergreen update channel, the second is a
system-wide shared component. Without either one the input method is broken
*after* a successful install — the Server will not start, or the settings
window opens onto nothing — and the user has no way to know why.

The check lives in Inno Setup's Pascal Script, which nothing on a non-Windows
host can compile. So this pins the parts that are easy to get wrong and that a
later edit could quietly drop, while a Windows run is still what proves it
compiles and behaves.
"""

from __future__ import annotations

import pathlib
import re
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
SETUP = ROOT / "platforms/windows/installer/msime_setup.iss"


def main() -> int:
    script = SETUP.read_text(encoding="utf-8")
    failures: list[str] = []

    def require(condition: bool, message: str) -> None:
        if not condition:
            failures.append(message)

    require("function InitializeSetup: Boolean;" in script,
            "no InitializeSetup: nothing runs before the first wizard page")

    # Registry, not the filesystem. Setup.exe is a 32-bit process and Pascal
    # Script's FileExists is redirected to SysWOW64, so probing for
    # vcruntime140.dll reports the x86 runtime and calls an x64-only machine
    # unequipped. Both registry views are named explicitly instead.
    require("Software\\Microsoft\\VisualStudio\\14.0\\VC\\Runtimes\\x64" in script,
            "VC runtime is not read from its x64 registry key")
    require("EdgeUpdate\\Clients\\{F3017226-FE2A-4295-8BDF-00C3A9A7E4C5}" in script,
            "WebView2 is not read from the EdgeUpdate client key")
    require(re.search(r"FileExists\([^)]*vcruntime", script, re.I) is None,
            "VC runtime probed through the filesystem, which WOW64 redirects")
    for view in ("HKLM32", "HKLM64"):
        require(view in script, f"{view} registry view is never consulted")

    # Installed=1 is true on a machine with only the 2015/2017 redistributable,
    # which lacks vcruntime140_1.dll and still cannot start the Server.
    require(re.search(r"Minor\s*>=\s*20", script) is not None,
            "VC runtime accepted without requiring 14.20 or newer")
    require("'Installed'" in script, "VC runtime Installed value is not read")

    # A silent install is CI or a fleet deployment; a modal dialog there is a
    # hang. Default to continuing, with the missing component in the log.
    require("SuppressibleMsgBox" in script,
            "prerequisite prompt would block a silent install")
    require(re.search(r"SuppressibleMsgBox\([^;]*IDNO\)", script, re.S) is not None,
            "silent install does not default to continuing")
    require(script.count("Log('Prerequisite missing:") == 2,
            "both missing prerequisites must be recorded in the install log")

    # The install is not blocked: a user may be about to fetch the component.
    require("MB_YESNO" in script, "prerequisite prompt is not a yes/no choice")

    for url in ("https://developer.microsoft.com/zh-cn/microsoft-edge/webview2",
                "https://learn.microsoft.com/zh-cn/cpp/windows/latest-supported-vc-redist"):
        require(url in script, f"missing download page: {url}")
    require(re.search(r"'http://", script) is None,
            "a download page is offered over plain http")

    for failure in failures:
        print(f"FAIL {failure}", file=sys.stderr)
    if failures:
        return 1
    print("installer prerequisites: WebView2 and the VC runtime are checked before install")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
