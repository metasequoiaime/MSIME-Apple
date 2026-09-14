#pragma once
#include "ToolbarLayout.h"
#include <cmath>

namespace msime::windows {
// Win32 events and window sizes are pixels; Direct2D already applies system
// DPI to its DIPs. Only the user scale belongs in the drawing coordinates.
inline double toolbar_pixel_unit(unsigned dpi, double scale) {
  return static_cast<double>(dpi ? dpi : 96) / 96.0 * scale;
}
inline std::optional<size_t> toolbar_button_at_pixel(
    double x, double y, unsigned dpi, double scale, size_t buttons,
    const ToolbarMetrics &metrics) {
  const double unit = toolbar_pixel_unit(dpi, scale);
  if (!(unit > 0.0) || !std::isfinite(unit) || !std::isfinite(x) || !std::isfinite(y))
    return std::nullopt;
  y /= unit;
  if (y < metrics.shadow.top || y >= metrics.shadow.top + metrics.height)
    return std::nullopt;
  return toolbar_button_at(x / unit, buttons, metrics);
}
inline bool toolbar_drag_at_pixel(double x, double y, unsigned dpi, double scale,
                                  const ToolbarMetrics &metrics) {
  const double unit = toolbar_pixel_unit(dpi, scale);
  return unit > 0.0 && std::isfinite(unit) && std::isfinite(x) && std::isfinite(y) &&
         y / unit >= metrics.shadow.top &&
         y / unit < metrics.shadow.top + metrics.height &&
         toolbar_is_drag_strip(x / unit, metrics);
}
} // namespace msime::windows
