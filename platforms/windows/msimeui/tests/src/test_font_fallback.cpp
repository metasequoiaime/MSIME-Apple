#include "tests/includes/test_framework.h"
#include "msimeui/Fonts.h"
#include "msimeui/Layout.h"
#include <dwrite_2.h>
#include <wrl/client.h>
#include <cwchar>

using Microsoft::WRL::ComPtr;

namespace
{
class TextSource : public IDWriteTextAnalysisSource
{
  public:
    explicit TextSource(const wchar_t *text) : text_(text)
    {
    }
    HRESULT STDMETHODCALLTYPE QueryInterface(REFIID iid, void **object) override
    {
        *object = nullptr;
        if (iid != __uuidof(IUnknown) && iid != __uuidof(IDWriteTextAnalysisSource))
            return E_NOINTERFACE;
        *object = this;
        return S_OK;
    }
    ULONG STDMETHODCALLTYPE AddRef() override
    {
        return 1;
    }
    ULONG STDMETHODCALLTYPE Release() override
    {
        return 1;
    }
    HRESULT STDMETHODCALLTYPE GetTextAtPosition(UINT32 position, const WCHAR **text, UINT32 *length) override
    {
        *length = position < text_.size() ? static_cast<UINT32>(text_.size()) - position : 0;
        *text = *length ? text_.c_str() + position : nullptr;
        return S_OK;
    }
    HRESULT STDMETHODCALLTYPE GetTextBeforePosition(UINT32 position, const WCHAR **text, UINT32 *length) override
    {
        *length = position <= text_.size() ? position : 0;
        *text = *length ? text_.c_str() : nullptr;
        return S_OK;
    }
    DWRITE_READING_DIRECTION STDMETHODCALLTYPE GetParagraphReadingDirection() override
    {
        return DWRITE_READING_DIRECTION_LEFT_TO_RIGHT;
    }
    HRESULT STDMETHODCALLTYPE GetLocaleName(UINT32 position, UINT32 *length, const WCHAR **name) override
    {
        *length = static_cast<UINT32>(text_.size()) - position;
        *name = L"en-us";
        return S_OK;
    }
    HRESULT STDMETHODCALLTYPE GetNumberSubstitution(UINT32 position, UINT32 *length,
                                                    IDWriteNumberSubstitution **substitution) override
    {
        *length = static_cast<UINT32>(text_.size()) - position;
        *substitution = nullptr;
        return S_OK;
    }

  private:
    std::wstring text_;
};

std::wstring MappedFamily(const wchar_t *text, const std::vector<std::wstring> &families)
{
    ComPtr<IDWriteFactory> factory;
    REQUIRE(SUCCEEDED(DWriteCreateFactory(DWRITE_FACTORY_TYPE_SHARED, __uuidof(IDWriteFactory),
                                          reinterpret_cast<IUnknown **>(factory.GetAddressOf()))));
    ComPtr<IDWriteTextFormat> format;
    REQUIRE(
        SUCCEEDED(factory->CreateTextFormat(L"Segoe UI", nullptr, DWRITE_FONT_WEIGHT_NORMAL, DWRITE_FONT_STYLE_NORMAL,
                                            DWRITE_FONT_STRETCH_NORMAL, 16, L"en-us", &format)));
    msimeui::ApplyFontFallback(factory.Get(), format.Get(), families);
    ComPtr<IDWriteTextFormat1> format1;
    REQUIRE(SUCCEEDED(format.As(&format1)));
    ComPtr<IDWriteFontFallback> fallback;
    REQUIRE(SUCCEEDED(format1->GetFontFallback(&fallback)));
    REQUIRE(fallback != nullptr);
    TextSource source(text);
    UINT32 mapped = 0;
    FLOAT scale = 0;
    ComPtr<IDWriteFont> font;
    REQUIRE(SUCCEEDED(fallback->MapCharacters(&source, 0, static_cast<UINT32>(wcslen(text)), nullptr, L"Segoe UI",
                                              DWRITE_FONT_WEIGHT_NORMAL, DWRITE_FONT_STYLE_NORMAL,
                                              DWRITE_FONT_STRETCH_NORMAL, &mapped, &font, &scale)));
    REQUIRE(mapped > 0);
    REQUIRE(font != nullptr);
    ComPtr<IDWriteFontFamily> family;
    REQUIRE(SUCCEEDED(font->GetFontFamily(&family)));
    ComPtr<IDWriteLocalizedStrings> names;
    REQUIRE(SUCCEEDED(family->GetFamilyNames(&names)));
    UINT32 index = 0;
    BOOL exists = FALSE;
    names->FindLocaleName(L"en-us", &index, &exists);
    if (!exists)
        index = 0;
    WCHAR name[256]{};
    REQUIRE(SUCCEEDED(names->GetString(index, name, 256)));
    return name;
}
} // namespace

TEST_CASE(font_fallback_respects_order_missing_fonts_and_system_fallback)
{
    REQUIRE(MappedFamily(L"A", {L"MSIME nonexistent font", L"Arial", L"Courier New"}) == L"Arial");
    REQUIRE(MappedFamily(L"A", {L"Courier New", L"Arial"}) == L"Courier New");
    REQUIRE(MappedFamily(L"\U0001F600", {L"Arial"}) == L"Segoe UI Emoji");
    REQUIRE(!MappedFamily(L"\u0627", {}).empty());

    // MapCharacters evaluates fallback mappings. Text layout itself checks the primary font first.
    msimeui::TextBlock text(L"WWWiii", 16, D2D1::ColorF(0));
    text.SetFontFamily(L"Segoe UI");
    text.SetFallbackFontFamilies({});
    const auto primarySize = text.Measure({1000, 1000});
    text.SetFallbackFontFamilies({L"Courier New"});
    REQUIRE(text.Measure({1000, 1000}).width == primarySize.width);
}
