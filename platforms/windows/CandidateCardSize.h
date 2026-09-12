#pragma once
#include <algorithm>
#include <cmath>
#include <cstddef>
#include <stdexcept>
#include <vector>

namespace msime::windows {
// Card geometry ported from the shipped Windows presenter. Widths arrive
// already measured in device independent pixels; this header only composes
// them, so it stays free of DirectWrite and is exercised without a renderer.
struct CandidateCardInput {
  double preedit_width = 0.0;
  // One measured width per candidate. A zero width hides that row.
  std::vector<double> item_widths;
  bool horizontal = false;
  bool preedit_visible = true;
  double font_size = 16.0;
  double preedit_font_size = 16.0;
  // Work area caps. At most one pixel means the axis stays uncapped.
  double max_width = 0.0;
  double max_height = 0.0;
};
struct CandidateCardSize {
  double width, height;
};
inline CandidateCardSize candidate_card_size(const CandidateCardInput &input) {
  auto measured = [](double value) {
    return std::isfinite(value) && value >= 0.0;
  };
  if (input.item_widths.size() > 9 || !measured(input.preedit_width) ||
      !measured(input.max_width) || !measured(input.max_height))
    throw std::invalid_argument("Invalid candidate card measurement");
  if (!std::isfinite(input.font_size) || input.font_size < 12.0 ||
      input.font_size > 32.0 || !std::isfinite(input.preedit_font_size) ||
      input.preedit_font_size < 12.0 || input.preedit_font_size > 32.0)
    throw std::invalid_argument("Invalid candidate card font size");
  for (double width : input.item_widths)
    if (!measured(width))
      throw std::invalid_argument("Invalid candidate card measurement");
  const double font = input.font_size;
  // Selection number column plus the separator bar before the candidate text.
  const double number_and_bar = font * 0.8 + font * 0.2 + 8.0;
  constexpr double pad_x = 12.0, pad_y = 8.0, slack_x = 14.0, slack_y = 10.0;
  const double min_width = font * 7.0;
  const double preedit_row =
      input.preedit_visible ? input.preedit_font_size * 1.4 + 6.0 : 0.0;
  const double candidate_row = font * 1.45 + 6.0;

  double width = 0.0;
  double height = pad_y + slack_y;
  if (input.preedit_visible) {
    width = (std::max)(width, input.preedit_width + 6.0);
    height += preedit_row;
  }
  size_t rows = 0;
  double row_width_sum = 0.0, row_width_max = 0.0;
  for (double item : input.item_widths) {
    if (item <= 0.0)
      continue;
    ++rows;
    const double row = item + number_and_bar;
    row_width_sum += row + 8.0;
    row_width_max = (std::max)(row_width_max, row);
  }
  if (input.horizontal) {
    width = (std::max)(width, row_width_sum);
    height += candidate_row;
  } else {
    // An empty list still reserves one row so the card cannot collapse.
    width = (std::max)(width, row_width_max);
    height += candidate_row * static_cast<double>((std::max)(rows, size_t{1}));
  }
  width = (std::max)(width + pad_x + slack_x, min_width);
  auto clamp = [](double value, double cap) {
    value = (std::max)(value, 1.0);
    return cap > 1.0 ? (std::min)(value, cap) : value;
  };
  return {clamp(width, input.max_width), clamp(height, input.max_height)};
}
} // namespace msime::windows
