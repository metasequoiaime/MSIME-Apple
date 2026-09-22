#!/usr/bin/env python3
"""The signing entitlements must stay free of restricted keys, and install.sh must refuse them.

Restricted entitlements are the ones a provisioning profile has to vouch for, and the whole
com.apple.developer.* family is restricted. A Developer ID signature cannot vouch for them, so AMFI rejects
the binary at exec: the input method never launches, never registers as an input source, and the only
symptom is an input method missing from the input menu. The signature verifies, codesign is happy, and
nothing in the build says why.

The tempting one is com.apple.developer.applesignin. Native Apple sign-in is unavailable to a Developer ID
input method, and adding a provisioning profile does not change that, so an account feature that reaches for
it takes the whole input method down with it.

Two halves, because either alone rots: the checked-in file has to be clean, and the script that signs with it
has to reject a dirty one. The second half runs install.sh for real against a poisoned file rather than
grepping it for the check, and asserts it bails before touching anything.
"""

import json
import os
import plistlib
import subprocess
import sys
import tempfile
from pathlib import Path

RESTRICTED_PREFIX = "com.apple.developer."


def poisoned_run(install: Path, entitlements: Path) -> int:
    """Run install.sh with restricted entitlements; return 0 when it refused without touching anything."""
    failures = 0
    # A list, an empty list and a false: an entitlement is restricted because of its key, whatever it is set
    # to. "We turned it off" is not a reason for AMFI to let the binary run.
    for value in (["Default"], [], False):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            bundle = root / "水杉输入法.app"
            (bundle / "Contents/MacOS").mkdir(parents=True)
            destination = root / "Input Methods"
            destination.mkdir()
            sentinel = destination / "水杉输入法.app"
            sentinel.mkdir()
            (sentinel / "installed").write_text("previous installation")

            entitlements.write_bytes(plistlib.dumps({RESTRICTED_PREFIX + "applesignin": value}))
            environment = os.environ.copy()
            environment.update({
                "MSIME_VOICE_ENTITLEMENTS": str(entitlements),
                "MSIME_INPUT_METHODS_DIR": str(destination),
                "MSIME_SIGNING_IDENTITY": "Developer ID Application: Test",
            })
            result = subprocess.run(["bash", str(install), str(bundle)], env=environment,
                                    capture_output=True, text=True)

            if result.returncode == 0:
                print(f"install.sh accepted restricted entitlements set to {value!r}", file=sys.stderr)
                failures += 1
            if "restricted entitlements" not in result.stderr:
                print(f"install.sh did not say why it refused {value!r}: {result.stderr.strip()}",
                      file=sys.stderr)
                failures += 1
            if sorted(p.name for p in destination.iterdir()) != ["水杉输入法.app"]:
                print(f"install.sh left {list(destination.iterdir())} behind for {value!r}", file=sys.stderr)
                failures += 1
            if (sentinel / "installed").read_text() != "previous installation":
                print(f"install.sh disturbed the existing installation for {value!r}", file=sys.stderr)
                failures += 1
    return failures


def main() -> int:
    if len(sys.argv) != 3:
        print("usage: entitlements_guard.py <entitlements> <install.sh>", file=sys.stderr)
        return 2
    shipped, install = Path(sys.argv[1]), Path(sys.argv[2])
    failures = 0

    for path in (shipped, install):
        if not path.is_file():
            print(f"missing {path}", file=sys.stderr)
            return 1

    lint = subprocess.run(["/usr/bin/plutil", "-lint", str(shipped)], capture_output=True, text=True)
    if lint.returncode != 0:
        print(f"{shipped.name} is not a valid plist: {lint.stdout.strip()}", file=sys.stderr)
        return 1

    # Read it the way the signing path does rather than with plistlib, so a file codesign would accept and
    # this check would not cannot slip through.
    declared = json.loads(subprocess.run(["/usr/bin/plutil", "-convert", "json", "-o", "-", str(shipped)],
                                         capture_output=True, text=True, check=True).stdout)
    restricted = sorted(key for key in declared if key.startswith(RESTRICTED_PREFIX))
    if restricted:
        print(f"{shipped.name} declares restricted entitlements: {', '.join(restricted)}", file=sys.stderr)
        print("a Developer ID signature cannot carry them and the input method would not launch",
              file=sys.stderr)
        failures += 1

    with tempfile.TemporaryDirectory() as directory:
        failures += poisoned_run(install, Path(directory) / "VoiceInput.entitlements")

    if failures:
        return 1
    print(f"{shipped.name} carries {len(declared)} unrestricted entitlements and install.sh rejects the rest")
    return 0


if __name__ == "__main__":
    sys.exit(main())
