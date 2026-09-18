#pragma once

#include <d2d1_1.h>
#include <d2d1effects.h>
#include <wrl/client.h>

#include <algorithm>
#include <cstddef>
#include <iterator>

namespace msime::windows {
struct WindowShadowPass {
  float sigma = 0.0f;
  float alpha = 0.0f;
  float offset_x = 0.0f;
  float offset_y = 0.0f;
};
// The Win11-style drop shadow upstream casts under its popups.
//
// Three blurred passes rather than one: a wide faint ambient pass for the
// sense of elevation, a mid pass, and a tight dark contact pass right under
// the edge. A single blur reads as a grey halo instead of a shadow.
//
// The caller must have grown the window by ToolbarShadow's margins first -
// a shadow drawn inside the window it belongs to is clipped by it.
namespace detail {
inline bool draw_gaussian_shadow_pass(ID2D1RenderTarget *target,
                                      ID2D1DeviceContext *context,
                                      const D2D1_RECT_F &bounds, float radius,
                                      const WindowShadowPass &pass,
                                      float scale) {
  const float width = bounds.right - bounds.left;
  const float height = bounds.bottom - bounds.top;
  const float amount = (std::max)(scale, 0.15f);
  const float deviation = pass.sigma * amount;
  const float pad = deviation * 3.0f + 4.0f;
  const D2D1_SIZE_F size{width + pad * 2.0f, height + pad * 2.0f};
  if (size.width < 2.0f || size.height < 2.0f || pass.alpha <= 0.0f)
    return false;
  Microsoft::WRL::ComPtr<ID2D1BitmapRenderTarget> surface;
  if (FAILED(
          target->CreateCompatibleRenderTarget(size, surface.GetAddressOf())))
    return false;
  surface->BeginDraw();
  surface->Clear(D2D1::ColorF(0, 0.0f));
  Microsoft::WRL::ComPtr<ID2D1SolidColorBrush> fill;
  if (FAILED(surface->CreateSolidColorBrush(D2D1::ColorF(0, 0, 0, pass.alpha),
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
  if (FAILED(
          context->CreateEffect(CLSID_D2D1GaussianBlur, blur.GetAddressOf())))
    return false;
  blur->SetInput(0, bitmap.Get());
  blur->SetValue(D2D1_GAUSSIANBLUR_PROP_STANDARD_DEVIATION, deviation);
  blur->SetValue(D2D1_GAUSSIANBLUR_PROP_BORDER_MODE, D2D1_BORDER_MODE_SOFT);
#ifdef __MINGW32__
  blur->SetValue(D2D1_GAUSSIANBLUR_PROP_OPTIMIZATION, UINT32{2});
#else
  blur->SetValue(D2D1_GAUSSIANBLUR_PROP_OPTIMIZATION,
                 D2D1_GAUSSIANBLUR_OPTIMIZATION_QUALITY);
#endif
  context->DrawImage(blur.Get(),
                     D2D1::Point2F(bounds.left - pad + pass.offset_x * amount,
                                   bounds.top - pad + pass.offset_y * amount));
  blur->SetInput(0, nullptr);
  return true;
}

inline bool draw_gaussian_shadow(ID2D1RenderTarget *target,
                                 const D2D1_RECT_F &bounds, float radius,
                                 float scale) {
  Microsoft::WRL::ComPtr<ID2D1DeviceContext> context;
  if (FAILED(target->QueryInterface(IID_PPV_ARGS(context.GetAddressOf()))))
    return false;
  const bool ambient = draw_gaussian_shadow_pass(
      target, context.Get(), bounds, radius, {11.0f, 0.42f, 0.0f, 3.0f}, scale);
  const bool mid = draw_gaussian_shadow_pass(
      target, context.Get(), bounds, radius, {6.0f, 0.30f, 0.0f, 4.0f}, scale);
  const bool contact = draw_gaussian_shadow_pass(
      target, context.Get(), bounds, radius, {2.8f, 0.48f, 0.0f, 3.0f}, scale);
  // Any one pass landing still reads as a shadow; all three failing does not.
  return ambient || mid || contact;
}

// No device context, no blur effect, or a driver that would not give us a
// compatible target. Stacking translucent rounded rectangles approximates the
// same falloff without either.
inline void draw_layered_shadow(ID2D1RenderTarget *target,
                                const D2D1_RECT_F &bounds, float radius,
                                float scale, float opacity = 1.0f) {
  const float amount = (std::max)(scale, 0.15f);
  for (int i = 1; i <= 20; ++i) {
    const float step = static_cast<float>(i) / 20.0f;
    const float spread = 1.15f * static_cast<float>(i) * amount;
    const float offset_y = 0.4f * static_cast<float>(i) * amount;
    // Quadratic falloff, so the stack reads as a blur rather than 20 rings.
    const float alpha = 0.14f * (1.0f - step) * (1.0f - step) * opacity;
    Microsoft::WRL::ComPtr<ID2D1SolidColorBrush> brush;
    if (FAILED(target->CreateSolidColorBrush(D2D1::ColorF(0, 0, 0, alpha),
                                             brush.GetAddressOf())))
      continue;
    target->FillRoundedRectangle(
        D2D1::RoundedRect(D2D1::RectF(bounds.left - spread,
                                      bounds.top - spread + offset_y,
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

inline void draw_window_shadow_passes(ID2D1RenderTarget *target,
                                      const D2D1_RECT_F &bounds, float radius,
                                      const WindowShadowPass *passes,
                                      std::size_t count) {
  if (!target || !passes || count == 0 || bounds.right <= bounds.left ||
      bounds.bottom <= bounds.top)
    return;
  Microsoft::WRL::ComPtr<ID2D1DeviceContext> context;
  if (FAILED(target->QueryInterface(IID_PPV_ARGS(context.GetAddressOf())))) {
    // Keep a soft fallback on older render targets, scaled to the strongest
    // requested pass instead of reverting to the much darker toolbar shadow.
    float strongest = 0.0f;
    for (std::size_t i = 0; i < count; ++i)
      strongest = (std::max)(strongest, passes[i].alpha);
    detail::draw_layered_shadow(target, bounds, radius, 1.0f,
                                std::clamp(strongest / 0.42f, 0.0f, 1.0f));
    return;
  }
  bool drew = false;
  for (std::size_t i = 0; i < count; ++i)
    drew = detail::draw_gaussian_shadow_pass(target, context.Get(), bounds,
                                             radius, passes[i], 1.0f) ||
           drew;
  if (!drew)
    detail::draw_layered_shadow(target, bounds, radius, 1.0f, 0.35f);
}
} // namespace msime::windows
