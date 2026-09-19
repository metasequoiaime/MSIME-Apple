#!/usr/bin/env python3
"""Every TCC-protected API the input method calls must have its purpose string.

TCC does not answer "denied" when a bundle asks for a protected resource it has declared no purpose for -
it terminates the process. For an input method that means the user's typing stops, mid-sentence, the first
time they try the feature, and the crash names a privacy key rather than the feature they used.

So the check is driven by the sources rather than by a fixed list: if the host calls the API, the plist has
to carry the key. Adding a recognizer or a camera and forgetting the string fails here instead of on a user's
machine.
"""

import plistlib
import re
import sys
from pathlib import Path

# Each entry pairs the symbols that reach a TCC gate with the key that has to be declared before they do.
GATES = (
    (("SFSpeechRecognizer",), "NSSpeechRecognitionUsageDescription"),
    (("AVCaptureDevice", "AVAudioEngine"), "NSMicrophoneUsageDescription"),
    (("AVCaptureDeviceTypeBuiltInWideAngleCamera",), "NSCameraUsageDescription"),
)

SOURCE_SUFFIXES = {".h", ".m", ".mm", ".cpp", ".swift"}


def main() -> int:
    if len(sys.argv) != 3:
        print("usage: info_plist_usage.py <Info.plist> <source directory>", file=sys.stderr)
        return 2
    plist_path, source_root = Path(sys.argv[1]), Path(sys.argv[2])

    # The template is configure_file'd, and @VAR@ placeholders are not valid plist content on their own.
    text = plist_path.read_text(encoding="utf-8")
    declared = set(re.findall(r"<key>(NS\w*UsageDescription)</key>\s*<string>([^<]*)</string>", text))
    if plist_path.suffix == ".plist" and "@" not in text:
        with plist_path.open("rb") as handle:
            declared = {(key, value) for key, value in plistlib.load(handle).items()
                        if key.endswith("UsageDescription")}

    sources = "\n".join(
        path.read_text(encoding="utf-8", errors="ignore")
        for path in source_root.rglob("*")
        if path.is_file() and path.suffix in SOURCE_SUFFIXES
    )

    failures = []
    for symbols, key in GATES:
        used = [symbol for symbol in symbols if symbol in sources]
        if not used:
            continue
        value = next((value for name, value in declared if name == key), None)
        if value is None:
            failures.append(f"{key} is missing; {', '.join(used)} reaches it from {source_root}")
        elif not value.strip():
            failures.append(f"{key} is empty; TCC shows this string to the user")

    for key, value in sorted(declared):
        if not value.strip():
            failures.append(f"{key} is declared with an empty purpose string")

    if failures:
        for failure in failures:
            print(failure, file=sys.stderr)
        return 1
    print(f"{len(declared)} usage descriptions cover every TCC gate reached from {source_root}.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
