#!/usr/bin/env python3
"""Preserve explicit full-pinyin segmentation at the cloud-query boundary.

MSIME-Windows fixed this in 837af70b.  The shared Engine uses the same
``normalized_segmentation`` field, so every Linux host gets the same query
identity without duplicating the rule in IBus or Fcitx5.
"""
from pathlib import Path


def replace_once(path: Path, before: str, after: str, marker: str) -> None:
    text = path.read_text(encoding="utf-8")
    if marker in text:
        return
    if text.count(before) != 1:
        raise RuntimeError(f"Engine overlay expected one match in {path}")
    path.write_text(text.replace(before, after, 1), encoding="utf-8")


def apply(root: Path) -> None:
    path = root / "core/input_session_composition.cpp"
    text = path.read_text(encoding="utf-8")
    if "const std::string &segmentation = request().normalized_segmentation.empty()" in text:
        return
    if text.count("    state.query_text = request().normalized_input;\n") == 1:
        old = "    state.query_text = request().normalized_input;\n"
        new = "    // Explicit apostrophes are user segmentation, not punctuation to discard.\n"
        new += "    // Keep them in the decoder request so qi'e'huan is not re-cut as qie'huan.\n"
        new += "    const std::string &segmentation = request().normalized_segmentation.empty()\n"
        new += "                                             ? request().normalized_input\n"
        new += "                                             : request().normalized_segmentation;\n"
        new += "    state.query_text = segmentation;\n"
    elif text.count("    state.query_text = quanpin::to_google_spelling(request().normalized_input);\n") == 1:
        old = "    state.query_text = quanpin::to_google_spelling(request().normalized_input);\n"
        new = "    // Preserve explicit segmentation before applying Google spelling conversion.\n"
        new += "    const std::string &segmentation = request().normalized_segmentation.empty()\n"
        new += "                                             ? request().normalized_input\n"
        new += "                                             : request().normalized_segmentation;\n"
        new += "    state.query_text = quanpin::to_google_spelling(segmentation);\n"
    else:
        raise RuntimeError(f"Engine overlay expected cloud query assignment in {path}")
    path.write_text(text.replace(old, new, 1), encoding="utf-8")


if __name__ == "__main__":
    import sys

    apply(Path(sys.argv[1]))
