#!/usr/bin/env python3
"""Whether the HarmonyOS settings bundle still matches the UI it was built from.

The HarmonyOS settings window is a WebView over `$rawfile('settings/index.html')`, and that file is
a generated artefact committed to the repository: one 1.3 MB document with the script, the styles
and every asset inlined, because a resource:// document has a null origin and the webview will not
fetch anything across it. Nothing rebuilds it. It was produced by hand once and then sat there while
the shared UI it is built from moved on — by the time this check was written, fifty-two commits had
touched `packages/ui/src` and the bundle had not been regenerated once, so the HarmonyOS settings
page was rendering a UI that no longer existed anywhere else. Every capability-gated control added
in that window was invisible on HarmonyOS and there was no error to see, because a stale bundle is a
working bundle.

A generated file under version control needs something that notices when it stops matching its
source, or it drifts silently and indefinitely. The build is byte-for-byte reproducible, so that
something can simply be the build: rebuild into a scratch directory and compare.
"""

import hashlib
import shutil
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
BUNDLE = ROOT / "platforms/harmony/entry/src/main/resources/rawfile/settings/index.html"
REBUILD = ["pnpm", "--filter", "@msime/harmony", "build"]


def digest(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def main() -> int:
    if not BUNDLE.exists():
        print(f"missing: {BUNDLE.relative_to(ROOT)}")
        print("  the settings window would load nothing at all")
        return 1
    if shutil.which("pnpm") is None:
        print("skipped: pnpm not on PATH, cannot rebuild the bundle to compare against")
        return 0
    if not (ROOT / "node_modules").exists():
        print("skipped: dependencies not installed, run pnpm install at the repository root")
        return 0

    committed = digest(BUNDLE)
    # The build writes over the tracked file in place, so keep the bytes to put back: this check
    # reports drift, it does not silently resolve it. A developer who wanted the rebuild would have
    # run the rebuild. The restore is in `finally` so a Ctrl-C mid-build puts it back too.
    original = BUNDLE.read_bytes()
    try:
        try:
            result = subprocess.run(REBUILD, cwd=ROOT, capture_output=True, text=True)
        except OSError as error:
            print(f"skipped: could not run the bundle build ({error})")
            return 0
        if result.returncode != 0:
            print("the settings bundle does not build")
            print(result.stdout[-2000:])
            print(result.stderr[-2000:])
            return 1
        rebuilt = digest(BUNDLE)
    finally:
        # emptyOutDir clears the directory before the build writes it, so it may be gone.
        BUNDLE.parent.mkdir(parents=True, exist_ok=True)
        BUNDLE.write_bytes(original)

    if rebuilt == committed:
        print("harmony settings bundle: matches the shared UI it is built from")
        return 0
    print("harmony settings bundle is stale")
    print(f"  committed: {committed[:16]}")
    print(f"  rebuilt:   {rebuilt[:16]}")
    print("  the HarmonyOS settings window is rendering an older UI than every other host")
    print("  regenerate with: pnpm --filter @msime/harmony build")
    return 1


if __name__ == "__main__":
    sys.exit(main())
