#include "../src/CandidateFontFormat.h"
#include <cassert>

int main() {
  using Microsoft::WRL::ComPtr;
  using msime::windows::set_candidate_font_fallback;
  ComPtr<IDWriteFactory2> factory;
  assert(SUCCEEDED(DWriteCreateFactory(
      DWRITE_FACTORY_TYPE_SHARED, __uuidof(IDWriteFactory2),
      reinterpret_cast<IUnknown **>(factory.GetAddressOf()))));
  ComPtr<IDWriteTextFormat> format;
  assert(SUCCEEDED(factory->CreateTextFormat(
      L"Segoe UI", nullptr, DWRITE_FONT_WEIGHT_NORMAL, DWRITE_FONT_STYLE_NORMAL,
      DWRITE_FONT_STRETCH_NORMAL, 18.0f, L"en-us", &format)));
  ComPtr<IDWriteTextFormat1> typed;
  assert(SUCCEEDED(format.As(&typed)));
  ComPtr<IDWriteFontFallbackBuilder> builder;
  assert(SUCCEEDED(factory->CreateFontFallbackBuilder(&builder)));
  ComPtr<IDWriteFontFallback> fallback;
  assert(SUCCEEDED(builder->CreateFontFallback(&fallback)));
  set_candidate_font_fallback(nullptr, fallback.Get());
  set_candidate_font_fallback(format.Get(), fallback.Get());
  ComPtr<IDWriteFontFallback> actual;
  assert(SUCCEEDED(typed->GetFontFallback(&actual)));
  assert(actual.Get() == fallback.Get());
  // Layout must inherit the chain even before any drawing has occurred.
  ComPtr<IDWriteTextLayout> layout;
  assert(SUCCEEDED(factory->CreateTextLayout(L"Sample", 6, format.Get(), 500,
                                             100, &layout)));
  ComPtr<IDWriteTextLayout2> layout2;
  assert(SUCCEEDED(layout.As(&layout2)));
  actual.Reset();
  assert(SUCCEEDED(layout2->GetFontFallback(&actual)));
  assert(actual.Get() == fallback.Get());
  // A reused cached format must not keep an earlier custom chain.
  set_candidate_font_fallback(format.Get(), nullptr);
  actual.Reset();
  assert(SUCCEEDED(typed->GetFontFallback(&actual)));
  assert(!actual);
}
