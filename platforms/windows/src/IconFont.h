#pragma once
#include <dwrite.h>
#include <wrl/client.h>

namespace msime::windows {
// Installed icon font, resolved once. "Segoe Fluent Icons" is Windows 11 only,
// so Windows 10 falls back to "Segoe MDL2 Assets"; neither installed means
// every icon draws its text label instead.
inline const wchar_t *icon_font_family(IDWriteFactory *factory) {
  static const wchar_t *family = [factory]() -> const wchar_t * {
    for (const wchar_t *name : {L"Segoe Fluent Icons", L"Segoe MDL2 Assets"}) {
      Microsoft::WRL::ComPtr<IDWriteFontCollection> fonts;
      UINT32 index = 0;
      BOOL exists = FALSE;
      if (factory && SUCCEEDED(factory->GetSystemFontCollection(fonts.GetAddressOf())) &&
          fonts && SUCCEEDED(fonts->FindFamilyName(name, &index, &exists)) && exists)
        return name;
    }
    return nullptr;
  }();
  return family;
}
// Does the resolved icon font actually carry this codepoint? The MDL2 build on
// an older Windows 10 may not, and DirectWrite would silently substitute some
// other font and draw a blank box rather than telling us.
inline bool icon_font_has(IDWriteFactory *factory, const wchar_t *family,
                   wchar_t codepoint) {
  if (!factory || !family || !codepoint)
    return false;
  Microsoft::WRL::ComPtr<IDWriteFontCollection> fonts;
  UINT32 index = 0;
  BOOL exists = FALSE;
  if (FAILED(factory->GetSystemFontCollection(fonts.GetAddressOf())) || !fonts ||
      FAILED(fonts->FindFamilyName(family, &index, &exists)) || !exists)
    return false;
  Microsoft::WRL::ComPtr<IDWriteFontFamily> resolved;
  Microsoft::WRL::ComPtr<IDWriteFont> font;
  if (FAILED(fonts->GetFontFamily(index, resolved.GetAddressOf())) || !resolved ||
      FAILED(resolved->GetFirstMatchingFont(
          DWRITE_FONT_WEIGHT_NORMAL, DWRITE_FONT_STRETCH_NORMAL,
          DWRITE_FONT_STYLE_NORMAL, font.GetAddressOf())) ||
      !font)
    return false;
  BOOL has = FALSE;
  return SUCCEEDED(font->HasCharacter(codepoint, &has)) && has;
}
} // namespace msime::windows
