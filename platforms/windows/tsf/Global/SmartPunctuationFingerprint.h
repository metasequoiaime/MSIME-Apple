#pragma once

namespace Global
{
// Does the document still look the way it did when the smart-punctuation
// rewrite was armed?
//
// Arming records the character that sat immediately before the punctuation.
// Before rewriting, the two characters left of the caret are read back: the
// punctuation itself, and before it the one compared here. Checking only that
// the caret is preceded by the expected punctuation is not enough, because the
// same punctuation usually appears more than once - a click onto an earlier
// one in the same window keeps the focus session and the foreground window, so
// nothing else in the armed state notices, and the rewrite lands on the wrong
// character.
//
// `readCount` is how many characters came back and `firstChar` is the earlier
// of the two. Both undecidable cases read as a match rather than a mismatch:
//
//   readCount == 0  a shallow text store (terminals, some Electron hosts)
//                   accepts the shift and returns nothing. There is no
//                   evidence either way, and refusing here would disable the
//                   feature in those hosts entirely.
//   beforeChar == 0 nothing was recorded at commit time, usually because the
//                   punctuation opened the document.
//
// readCount == 1 is a real mismatch: only the punctuation exists, so it is at
// the very start of the document, which is not where it was armed.
constexpr bool SmartPunctuationFingerprintMatches(int readCount, wchar_t firstChar, wchar_t beforeChar)
{
    if (beforeChar == 0 || readCount == 0)
    {
        return true;
    }
    if (readCount == 1)
    {
        return false;
    }
    return firstChar == beforeChar;
}
} // namespace Global
