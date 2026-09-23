#!/usr/bin/env python3
"""Keep quote alternation and book-title nesting when paired completion is off, as the reference does.

The reference's `CCompositionProcessorEngine::GetPunctuation` (MSIME-Windows `windows/src/Composition/CompositionProcessorEngine.cpp`) always flips `_isPairToggle` for the quote keys, so `"` gives “ and the next one ”, and always counts `_nestCount` for `<` and `>`, so they give 《 〈 〉 》. Neither depends on the paired-punctuation setting. The setting only changes what the host does around that result: `KeyHandler.cpp` rewrites a closing quote back to an opening one and appends the closing half only when pairing is on and the host is not excluded, and says so - an excluded host falls back to the ordinary left/right alternation.

The locked Engine's `PunctuationPolicy::translate` instead returns the opening mark for every quote press and the outer 《 / 》 without nesting whenever pairing is off. That is exactly the case - pairing switched off, or an excluded host such as Excel - in which nothing else supplies the closing half, so quotes could only ever open and nested titles came out as 《《》》.

The rewrite drops the `paired_enabled_` gate from both branches and nothing else: with pairing on the result is unchanged, the state still lives for the session and is never reset by toggling the setting (the reference's toggle and count live for the composition engine and are only initialised when the pairs are set up), and `balance_after_auto_close` keeps its gate because it is only ever called by a host that has just auto-closed a pair, which means pairing is on.
"""
from pathlib import Path

BEFORE = """    if (const auto *mapping = alternating_mapping(character))
    {
        if (!paired_enabled_)
            return mapping->opening;
        const bool opening"""

AFTER = """    // Quotes alternate and book title marks nest whether or not the host completes pairs, as in the reference's GetPunctuation: without pairing this alternation is the only way to type a closing quote, and a host that does complete pairs rewrites the closing quote itself.
    if (const auto *mapping = alternating_mapping(character))
    {
        const bool opening"""

NESTING_BEFORE = """    if (character == nested_opening_input)
        return paired_enabled_ ? (book_title_nesting_++ == 0 ? nested_opening : nested_opening_inner) : nested_opening;
    if (character == nested_closing_input)
    {
        if (!paired_enabled_)
            return nested_closing;
        if (book_title_nesting_ > 0)"""

NESTING_AFTER = """    if (character == nested_opening_input)
        return book_title_nesting_++ == 0 ? nested_opening : nested_opening_inner;
    if (character == nested_closing_input)
    {
        if (book_title_nesting_ > 0)"""


def apply(root: Path) -> None:
    path = root / "core/punctuation_policy.cpp"
    text = path.read_text(encoding="utf-8")
    if AFTER in text and NESTING_AFTER in text:
        return
    if text.count(BEFORE) != 1 or text.count(NESTING_BEFORE) != 1:
        raise RuntimeError(f"Engine overlay did not match: {path}")
    text = text.replace(BEFORE, AFTER, 1).replace(NESTING_BEFORE, NESTING_AFTER, 1)
    path.write_text(text, encoding="utf-8")


if __name__ == "__main__":
    import sys

    apply(Path(sys.argv[1]))
