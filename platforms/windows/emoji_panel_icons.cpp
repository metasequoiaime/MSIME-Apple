#include "emoji_panel_icons.h"

#include "msimeui/DeviceResources.h"
#include "msimeui/Fonts.h"
#include "msimeui/Types.h"

#include <cwchar>
#include <d2d1.h>
#include <dwrite.h>
#include <wrl/client.h>

namespace msimeui
{
namespace
{
constexpr float kIconFontSize = 28.0f;
constexpr float kFallbackFontSize = 14.0f;

// Windows emoji panel tab glyphs, in navigation order. "Segoe Fluent Icons"
// ships with Windows 11 only, and the Windows 10 build of "Segoe MDL2 Assets"
// is older than the one we can check here, so each tab also carries a text
// label for the case where neither font has the glyph (issue #232).
struct TabIcon
{
    wchar_t codepoint;
    const wchar_t *fallbackText;
};

constexpr TabIcon kTabIcons[] = {
    {0xF6B8, L"最近"},   // Expressive Input Entry
    {0xE76E, L"表情"},   // Emoji
    {0xF4AA, L"贴纸"},   // Sticker
    {0xF4A9, L"GIF"},    // GIF
    {0xED59, L"颜文字"}, // Emoji Tab Text Smiles
    {0xF6BA, L"符号"},   // Emoji Tab More Symbols
    {0xE77F, L"剪贴板"}, // Paste
};

static_assert(sizeof(kTabIcons) / sizeof(kTabIcons[0]) == static_cast<size_t>(EmojiPanelIcons::Tab::Count),
              "tab icon table must cover every tab");

D2D1_COLOR_F IconFillColor(bool lightTheme)
{
    return lightTheme ? D2D1::ColorF(0x686873) : D2D1::ColorF(1.0f, 1.0f, 1.0f);
}
} // namespace

bool EmojiPanelIcons::DrawTabIcon(DeviceResources &resources, Tab tab, const RectF &designRect, bool lightTheme) const
{
    const auto index = static_cast<size_t>(tab);
    if (index >= static_cast<size_t>(Tab::Count))
    {
        return false;
    }

    const TabIcon &icon = kTabIcons[index];
    const IconGlyph resolved = ResolveIconGlyph(icon.codepoint);
    const bool useGlyph = resolved.family != nullptr;

    ID2D1RenderTarget *target = resources.GetRenderTarget();
    IDWriteFactory *factory = resources.GetDWriteFactory();
    IDWriteTextFormat *format = resources.GetTextFormat(
        useGlyph ? resolved.family : UiFontFamily(), useGlyph ? kIconFontSize : kFallbackFontSize,
        DWRITE_FONT_WEIGHT_NORMAL, DWRITE_TEXT_ALIGNMENT_CENTER, DWRITE_PARAGRAPH_ALIGNMENT_CENTER,
        DWRITE_WORD_WRAPPING_NO_WRAP);
    ID2D1SolidColorBrush *brush = resources.GetSolidColorBrush(IconFillColor(lightTheme));
    if (!target || !factory || !format || !brush)
    {
        return false;
    }

    const wchar_t glyph[] = {resolved.codepoint, L'\0'};
    const wchar_t *text = useGlyph ? glyph : icon.fallbackText;
    const UINT32 length = static_cast<UINT32>(std::wcslen(text));
    Microsoft::WRL::ComPtr<IDWriteTextLayout> layout;
    if (FAILED(factory->CreateTextLayout(text, length, format, designRect.width, designRect.height, &layout)))
    {
        return false;
    }

    target->DrawTextLayout(D2D1::Point2F(designRect.x, designRect.y), layout.Get(), brush, D2D1_DRAW_TEXT_OPTIONS_CLIP);
    return true;
}
} // namespace msimeui

