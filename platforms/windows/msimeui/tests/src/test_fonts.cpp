#include "tests/includes/test_framework.h"

#include "msimeui/Fonts.h"

#include <cwchar>

namespace
{
// Spelled numerically: this target is not built with /utf-8, so a literal CJK
// character in the source would not survive as the codepoint we mean to probe.
constexpr wchar_t kCjkZhong = 0x4E2D; // 中
constexpr wchar_t kCjkWen = 0x6587;   // 文

bool IsKnownIconFamily(const wchar_t *family)
{
    return family != nullptr &&
           (std::wcscmp(family, L"Segoe Fluent Icons") == 0 || std::wcscmp(family, L"Segoe MDL2 Assets") == 0);
}
} // namespace

// A codepoint no icon font carries must report "no family" rather than handing
// back a font that would render a blank box. This is the whole point of the
// probe: DirectWrite silently substitutes fonts, so absence has to be detected
// before drawing, not after.
TEST_CASE(icon_glyph_reports_missing_glyph)
{
    const msimeui::IconGlyph resolved = msimeui::ResolveIconGlyph(kCjkZhong);
    REQUIRE(resolved.family == nullptr);
    REQUIRE(resolved.codepoint == 0);
}

// The MDL2 override must not smuggle in a glyph the font does not have either.
TEST_CASE(icon_glyph_reports_missing_glyph_with_mdl2_override)
{
    const msimeui::IconGlyph resolved = msimeui::ResolveIconGlyph(kCjkZhong, kCjkWen);
    REQUIRE(resolved.family == nullptr);
    REQUIRE(resolved.codepoint == 0);
}

// Whatever the host happens to have installed, a successful resolution has to
// name one of the icon fonts we probe and keep the codepoint we asked for.
// Machines with neither font installed legitimately resolve to nothing.
TEST_CASE(icon_glyph_resolves_consistently)
{
    const msimeui::IconGlyph settings = msimeui::ResolveIconGlyph(0xE713);
    if (settings.family != nullptr)
    {
        REQUIRE(IsKnownIconFamily(settings.family));
        REQUIRE(settings.codepoint == 0xE713);
    }
    else
    {
        REQUIRE(settings.codepoint == 0);
    }
}

// Results are cached; repeated lookups must not drift.
TEST_CASE(icon_glyph_resolution_is_stable)
{
    const msimeui::IconGlyph first = msimeui::ResolveIconGlyph(0xE76E);
    const msimeui::IconGlyph second = msimeui::ResolveIconGlyph(0xE76E);
    REQUIRE(first.family == second.family);
    REQUIRE(first.codepoint == second.codepoint);
}
