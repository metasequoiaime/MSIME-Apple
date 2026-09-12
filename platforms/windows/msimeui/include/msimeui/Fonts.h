#pragma once

#include <dwrite.h>

namespace msimeui
{
const wchar_t *UiFontFamily();
const wchar_t *UiFontFallbackFamily();
void ApplyUiFontFallback(IDWriteFactory *factory, IDWriteTextFormat *format);

// Resolved icon font/codepoint pair. `family` is null when no installed icon
// font can actually render the requested glyph, in which case the caller must
// fall back to plain text instead of drawing tofu.
struct IconGlyph
{
    const wchar_t *family = nullptr;
    wchar_t codepoint = 0;
};

// Picks the first installed icon font that really contains the glyph:
// "Segoe Fluent Icons" (Windows 11) first, then "Segoe MDL2 Assets"
// (Windows 10). `mdl2Codepoint` overrides the codepoint used when probing
// Segoe MDL2 Assets; pass 0 when both fonts share the same codepoint.
IconGlyph ResolveIconGlyph(wchar_t fluentCodepoint, wchar_t mdl2Codepoint = 0);
} // namespace msimeui
