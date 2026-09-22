#!/usr/bin/env python3
"""Stop the alternative-segmentation slot from overwriting a rank the user earned by typing.

`xian` can be read `xian` or `xi'an`, and the Engine keeps one slot near the top of the list for
the best word of the other reading so that 西安 - which sits at position 16 on weight alone - is
reachable without paging. The slot was claimed by any such word ranked below index 1, which is
every one of them except a word already first or second.

That is the defect the reference fixed in `1ea01d5e`: frequency also ranks by weight, so a word the
user has promoted rises until it becomes the heaviest word of its own reading group, at which point
the slot recognises it and drags it back to index 1. The user sees "picking it once jumps it to
second place, and nothing I do after that moves it" - the fixed slot has overwritten everything
frequency wrote. The slot should only lift a word that cannot be seen at all, so it now applies to
words outside the first page.

This is a port of that commit's Engine hunk, not a local invention; the lock's Engine is the commit
before it and the standalone Engine repository is frozen, so an overlay is the only way it can
arrive. `kAlternativeSegmentationFirstPageSize` is the default `page_size` of 6, and the setting
ranges over 3..9: a longer page means at most that a word or two already visible is not lifted,
never that one needing the lift misses it.

Measured against the shipped dictionary on 2026-09-21, scanning 58 ambiguous syllables: four first
pages change, all of them by letting a common character back into the place a rare re-segmentation
had taken. `tian` showed 天 提案 田 and now shows 天 田 提案; `shuan`, `zuan` and `niao` move
熟谙, 祖安 and 尼奥 down by one or two in the same way. `xian` is unchanged - 西安 sits at position
16 on weight alone, outside the first page, so the slot still lifts it, which is the case the slot
was built for.
"""
from pathlib import Path

CONSTANT_BEFORE = "constexpr size_t kBestAlternativeSegmentationMaxIndex = 1;\n"
CONSTANT_AFTER = (
    "constexpr size_t kBestAlternativeSegmentationMaxIndex = 1;\n"
    "// The slot only lifts a reading that cannot be seen at all. Anything already on the first page\n"
    "// keeps the position its weight earned, and frequency writes weight: pinning such a word again\n"
    "// overwrites the rank the user just typed for. The default page_size is 6.\n"
    "constexpr size_t kAlternativeSegmentationFirstPageSize = 6;\n"
)

CONDITION_BEFORE = """    if (promote_alternative && best_alternative != merged_full.end() &&
        static_cast<size_t>(std::distance(merged_full.begin(), best_alternative)) >
            kBestAlternativeSegmentationMaxIndex)
"""

CONDITION_AFTER = """    const size_t best_alternative_index =
        best_alternative == merged_full.end()
            ? 0
            : static_cast<size_t>(std::distance(merged_full.begin(), best_alternative));
    if (promote_alternative && best_alternative != merged_full.end() &&
        best_alternative_index >= kAlternativeSegmentationFirstPageSize)
"""

APPLIED = "kAlternativeSegmentationFirstPageSize"


def apply(root: Path) -> None:
    path = root / "quanpin/quanpin_dictionary.cpp"
    text = path.read_text(encoding="utf-8")
    if APPLIED in text:
        return
    for before in (CONSTANT_BEFORE, CONDITION_BEFORE):
        if before not in text:
            raise RuntimeError(f"Engine overlay did not match: {path}")
    text = text.replace(CONSTANT_BEFORE, CONSTANT_AFTER, 1)
    text = text.replace(CONDITION_BEFORE, CONDITION_AFTER, 1)
    path.write_text(text, encoding="utf-8")


if __name__ == "__main__":
    import sys

    apply(Path(sys.argv[1]))
