#pragma once
#include <algorithm>
#include <cstddef>
#include <optional>

namespace msime::windows {
// Floating toolbar geometry, in device independent pixels.
//
// The cell pitch and bar height used to be the literals 72 and 52, repeated at
// five call sites - the width calculation, the drawing loop, the hover hit and
// the click hit. Two consequences. The icon size setting only changed the glyph
// while the cell it sat in stayed the same size, so a larger icon crowded its
// cell instead of enlarging the bar. And four copies of the same arithmetic is
// four chances for the highlight and the click to disagree about which button
// the pointer is over.
struct ToolbarMetrics {
  double cell = 72.0;
  double height = 52.0;
  // The drag strip on the left; the only part of the window that drags.
  double handle = 8.0;
  double icon_top = 8.0;
  double icon_bottom = 44.0;
};

// Derived from the configured icon size. The shipped default of 24 reproduces
// the previous fixed 72 x 52 exactly, so nothing moves for a user who never
// touched the setting.
inline ToolbarMetrics toolbar_metrics(double font_size) {
  ToolbarMetrics metrics;
  if (!(font_size >= 8.0) || !(font_size <= 64.0))
    return metrics; // Out of range: keep the shipped geometry.
  metrics.cell = font_size * 3.0;
  metrics.height = font_size * 2.0 + 4.0;
  metrics.icon_top = metrics.height / 6.5;
  metrics.icon_bottom = metrics.height - metrics.icon_top;
  return metrics;
}

inline double toolbar_bar_width(size_t buttons, const ToolbarMetrics &metrics) {
  return metrics.handle * 2.0 + metrics.cell * static_cast<double>(buttons);
}

// Which button sits under `x`, or nothing for the drag strip and the margin
// past the last button. One implementation so drawing, hover and click cannot
// disagree.
inline std::optional<size_t> toolbar_button_at(double x, size_t buttons,
                                               const ToolbarMetrics &metrics) {
  if (buttons == 0 || metrics.cell <= 0.0 || x < metrics.handle)
    return std::nullopt;
  const auto index =
      static_cast<size_t>((x - metrics.handle) / metrics.cell);
  if (index >= buttons)
    return std::nullopt;
  return index;
}

// The cell a button occupies, as drawing uses it.
struct ToolbarCell {
  double left, top, right, bottom;
};
inline ToolbarCell toolbar_cell(size_t index, const ToolbarMetrics &metrics) {
  const double left = metrics.handle + metrics.cell * static_cast<double>(index);
  return {left, metrics.icon_top, left + metrics.cell, metrics.icon_bottom};
}
} // namespace msime::windows
