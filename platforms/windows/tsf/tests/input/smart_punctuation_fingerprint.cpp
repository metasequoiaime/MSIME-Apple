#include "SmartPunctuationFingerprint.h"
#include <cassert>

int main()
{
    using Global::SmartPunctuationFingerprintMatches;

    // "你，" armed after 你; the same two characters read back.
    assert(SmartPunctuationFingerprintMatches(2, L'你', L'你'));

    // The caret was moved onto an identical punctuation elsewhere: the
    // punctuation still matches, the character before it does not.
    assert(!SmartPunctuationFingerprintMatches(2, L'好', L'你'));

    // Only the punctuation exists, so it is at the very start of the document
    // and cannot be the one that armed after a character.
    assert(!SmartPunctuationFingerprintMatches(1, L'，', L'你'));

    // A text store that exposes no text (terminals, proxy stores) offers no
    // evidence; refusing would disable the feature there outright.
    assert(SmartPunctuationFingerprintMatches(0, L'\0', L'你'));

    // Nothing recorded at commit time - the punctuation opened the document.
    assert(SmartPunctuationFingerprintMatches(2, L'x', 0));
    assert(SmartPunctuationFingerprintMatches(1, L'\0', 0));
    assert(SmartPunctuationFingerprintMatches(0, L'\0', 0));

    // ASCII and non-BMP-adjacent characters take the same path.
    assert(SmartPunctuationFingerprintMatches(2, L'a', L'a'));
    assert(!SmartPunctuationFingerprintMatches(2, L'a', L'b'));
}
