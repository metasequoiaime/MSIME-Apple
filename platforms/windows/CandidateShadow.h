#pragma once

#include "CandidateCardSize.h"
#include <cmath>
#include <stdexcept>

namespace msime::windows {
// Transparent space around the composed candidate card. The values cover the
// two CSS-equivalent shadow passes through the same alpha threshold used by
// the Windows baseline, so neither the blur nor its right/down offset is cut
// by the popup HWND.
struct CandidateShadowInsets {
  double left = 32.0;
  double top = 20.0;
  double right = 32.0;
  double bottom = 40.0;
};

struct CandidateShadowFrame {
  double width = 0.0;
  double height = 0.0;
  double card_left = 0.0;
  double card_top = 0.0;
  double card_width = 0.0;
  double card_height = 0.0;
};

inline CandidateShadowFrame
candidate_shadow_frame(double card_width, double card_height,
                       double decoration_height,
                       CandidateShadowInsets insets = {}) {
  const auto valid = [](double value) {
    return std::isfinite(value) && value >= 0.0;
  };
  if (!valid(card_width) || !valid(card_height) || !valid(decoration_height) ||
      !valid(insets.left) || !valid(insets.top) || !valid(insets.right) ||
      !valid(insets.bottom) || card_width <= 0.0 || card_height <= 0.0)
    throw std::invalid_argument("Invalid candidate shadow frame");
  return {insets.left + card_width + insets.right,
          insets.top + decoration_height + card_height + insets.bottom,
          insets.left,
          insets.top + decoration_height,
          card_width,
          card_height};
}

struct CandidateShadowPixels {
  int left = 0;
  int top = 0;
  int right = 0;
  int bottom = 0;
};

inline CandidateBounds candidate_shadow_bounds(CandidatePlacementInput content,
                                               CandidateShadowPixels shadow) {
  if (shadow.left < 0 || shadow.top < 0 || shadow.right < 0 ||
      shadow.bottom < 0)
    throw std::invalid_argument("Invalid candidate shadow margins");
  content.work_left += shadow.left;
  content.work_top += shadow.top;
  content.work_right -= shadow.right;
  content.work_bottom -= shadow.bottom;
  if (content.work_right <= content.work_left ||
      content.work_bottom <= content.work_top)
    throw std::invalid_argument("Candidate shadow exceeds work area");
  const auto placed = candidate_card_placement(content);
  return {placed.x - shadow.left, placed.y - shadow.top,
          content.width + shadow.left + shadow.right,
          content.height + shadow.top + shadow.bottom};
}
} // namespace msime::windows
