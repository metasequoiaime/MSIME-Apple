#pragma once

#include <d2d1_1.h>
#include <d2d1effects.h>
#include <wrl/client.h>

#include <algorithm>

namespace msime::windows {
// The Win11-style drop shadow upstream casts under its popups.
//
// Three blurred passes rather than one: a wide faint ambient pass for the
// sense of elevation, a mid pass, and a tight dark contact pass right under
// the edge. A single blur reads as a grey halo instead of a shadow.
//
// The caller must have grown the window by ToolbarShadow's margins first -
// a shadow drawn inside the window it belongs to is clipped by it.
namespace detail {
inline bool draw_gaussian_shadow(ID2D1RenderTarget *target,
                                 const D2D1_RECT_F &bounds, float radius,
                                 float scale) {
  Microsoft::WRL::ComPtr<ID2D1DeviceContext> context;
  if (FAILED(target->QueryInterface(IID_PPV_ARGS(context.GetAddressOf()))))
    return false;
  const float width = bounds.right - bounds.left;
  const float height = bounds.bottom - bounds.top;
  const float amount = (std::max)(scale, 0.15f);

  auto pass = [&](float deviation, float alpha, float offset_y) -> bool {
    const float pad = deviation * 3.0f + 4.0f;
    const D2D1_SIZE_F size{width + pad * 2.0f, height + pad * 2.0f};
    if (size.width < 2.0f || size.height < 2.0f)
      return false;
    Microsoft::WRL::ComPtr<ID2D1BitmapRenderTarget> surface;
    if (FAILED(target->CreateCompatibleRenderTarget(size,
                                                    surface.GetAddressOf())))
      return false;
    surface->BeginDraw();
    surface->Clear(D2D1::ColorF(0, 0.0f));
    Microsoft::WRL::ComPtr<ID2D1SolidColorBrush> fill;
    if (FAILED(surface->CreateSolidColorBrush(D2D1::ColorF(0, 0, 0, alpha),
                                              fill.GetAddressOf()))) {
      surface->EndDraw();
      return false;
    }
    surface->FillRoundedRectangle(
        D2D1::RoundedRect(D2D1::RectF(pad, pad, pad + width, pad + height),
                          radius, radius),
        fill.Get());
    if (FAILED(surface->EndDraw()))
      return false;
    Microsoft::WRL::ComPtr<ID2D1Bitmap> bitmap;
    if (FAILED(surface->GetBitmap(bitmap.GetAddressOf())))
      return false;
    Microsoft::WRL::ComPtr<ID2D1Effect> blur;
    if (FAILED(context->CreateEffect(CLSID_D2D1GaussianBlur,
                                     blur.GetAddressOf())))
      return false;
    blur->SetInput(0, bitmap.Get());
    blur->SetValue(D2D1_GAUSSIANBLUR_PROP_STANDARD_DEVIATION, deviation);
    blur->SetValue(D2D1_GAUSSIANBLUR_PROP_BORDER_MODE, D2D1_BORDER_MODE_SOFT);
#ifdef __MINGW32__
    // MinGW omits the optimization enum. Windows SDK / windows 0.61.3
    // defines QUALITY as 2; the effect property is a UINT32 enum value.
    blur->SetValue(D2D1_GAUSSIANBLUR_PROP_OPTIMIZATION, UINT32{2});
#else
    blur->SetValue(D2D1_GAUSSIANBLUR_PROP_OPTIMIZATION,
                   D2D1_GAUSSIANBLUR_OPTIMIZATION_QUALITY);
#endif
    context->DrawImage(blur.Get(),
                       D2D1::Point2F(bounds.left - pad,
                                     bounds.top - pad + offset_y));
    // The effect holds a reference to the bitmap, which is backed by the
    // compatible target going out of scope here.
    blur->SetInput(0, nullptr);
    return true;
  };

  const bool ambient = pass(11.0f * amount, 0.42f, 3.0f * amount);
  const bool mid = pass(6.0f * amount, 0.30f, 4.0f * amount);
  const bool contact = pass(2.8f * amount, 0.48f, 3.0f * amount);
  // Any one pass landing still reads as a shadow; all three failing does not.
  return ambient || mid || contact;
}

// No device context, no blur effect, or a driver that would not give us a
// compatible target. Stacking translucent rounded rectangles approximates the
// same falloff without either.
inline void draw_layered_shadow(ID2D1RenderTarget *target,
                                const D2D1_RECT_F &bounds, float radius,
                                float scale) {
  const float amount = (std::max)(scale, 0.15f);
  for (int i = 1; i <= 20; ++i) {
    const float step = static_cast<float>(i) / 20.0f;
    const float spread = 1.15f * static_cast<float>(i) * amount;
    const float offset_y = 0.4f * static_cast<float>(i) * amount;
    // Quadratic falloff, so the stack reads as a blur rather than 20 rings.
    const float alpha = 0.14f * (1.0f - step) * (1.0f - step);
    Microsoft::WRL::ComPtr<ID2D1SolidColorBrush> brush;
    if (FAILED(target->CreateSolidColorBrush(D2D1::ColorF(0, 0, 0, alpha),
                                             brush.GetAddressOf())))
      continue;
    target->FillRoundedRectangle(
        D2D1::RoundedRect(
            D2D1::RectF(bounds.left - spread, bounds.top - spread + offset_y,
                        bounds.right + spread,
                        bounds.bottom + spread + offset_y),
            radius + spread, radius + spread),
        brush.Get());
  }
}
} // namespace detail

inline void draw_window_shadow(ID2D1RenderTarget *target,
                               const D2D1_RECT_F &bounds, float radius,
                               float scale) {
  if (!target || scale <= 0.0f || bounds.right <= bounds.left ||
      bounds.bottom <= bounds.top)
    return;
  if (!detail::draw_gaussian_shadow(target, bounds, radius, scale))
    detail::draw_layered_shadow(target, bounds, radius, scale);
}
} // namespace msime::windows
