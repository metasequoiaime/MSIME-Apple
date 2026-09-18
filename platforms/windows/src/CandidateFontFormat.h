#pragma once
#include <dwrite_2.h>
#include <wrl/client.h>

namespace msime::windows {
// DeviceResources caches formats independently of fallback. Set it explicitly
// for both measurement and drawing, including null to restore system fallback.
inline void set_candidate_font_fallback(IDWriteTextFormat *format,
                                        IDWriteFontFallback *fallback) {
  if (!format)
    return;
  Microsoft::WRL::ComPtr<IDWriteTextFormat1> typed;
  if (SUCCEEDED(format->QueryInterface(IID_PPV_ARGS(&typed))) && typed)
    typed->SetFontFallback(fallback);
}
} // namespace msime::windows
