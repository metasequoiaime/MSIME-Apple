#!/usr/bin/env python3
"""Accept ``yo`` as one complete syllable in every shuangpin profile.

MSIME-Windows fixed this in 5e641fb5. The locked standalone Engine still
contains the older compatibility exclusion, so apply the upstream one-token
change without widening any of the other historical shuangpin spellings.
"""

from pathlib import Path


def apply(root: Path) -> None:
    path = root / "shuangpin/shuangpin_utils.cpp"
    text = path.read_text(encoding="utf-8")
    before = '"qve", "xve", "yo", "yve", "zhei"'
    after = '"qve", "xve", "yve", "zhei"'
    if after in text:
        return
    if text.count(before) != 1:
        raise RuntimeError(f"Engine overlay expected one yo exclusion in {path}")
    path.write_text(text.replace(before, after, 1), encoding="utf-8")


if __name__ == "__main__":
    import sys

    apply(Path(sys.argv[1]))
