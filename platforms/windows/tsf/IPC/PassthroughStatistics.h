#pragma once

// A key this tip does not consume is inserted by the host itself, so half-width digits, the symbols outside the punctuation table and English-mode letters never reach a commit path and were never counted. This rule decides which of those keys count; it stays pure so it can be tested without a TSF host.
//
// The count is a key-time prediction, not an edit confirmation: a read-only document or an application shortcut still counts. That approximation is the reference's product decision; the filter only drops keys that certainly are not a character the user typed.
inline bool ShouldCountPassthroughChar(wchar_t wch, bool keyboardDisabled, bool ctrlDown, bool altDown, bool winDown)
{
    // Shift stays allowed on purpose: it is what makes uppercase letters and the shifted symbol row their own characters. Functional and dead keys produce no printable character, so the range check keeps Enter, Tab and Backspace out; 0x7F is DEL. A lone surrogate cannot be classified and would be rejected by the Server's UTF-8 conversion anyway.
    return !keyboardDisabled && !ctrlDown && !altDown && !winDown && wch >= 0x20 && wch != 0x7F &&
           !(wch >= 0xD800 && wch <= 0xDFFF);
}
