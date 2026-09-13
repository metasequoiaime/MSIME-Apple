#pragma once
#include <algorithm>
#include <cmath>
#include <cstddef>
#include <optional>
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
// Screen pixels, including negative monitor origins.
struct CandidateBounds {
  int x, y, width, height;
};
// One source for the card's spacing, so sizing, drawing and hit testing cannot
// drift apart. Rows are laid out from the top padding downwards.
struct CandidateCardMetrics {
  double pad_x = 12.0, pad_y = 8.0, slack_x = 14.0, slack_y = 10.0;
  double number_and_bar = 0.0, preedit_row = 0.0, candidate_row = 0.0,
         min_width = 0.0;
};
inline CandidateCardMetrics candidate_card_metrics(double font_size,
                                                   double preedit_font_size,
                                                   bool preedit_visible) {
  if (!std::isfinite(font_size) || font_size < 12.0 || font_size > 32.0 ||
      !std::isfinite(preedit_font_size) || preedit_font_size < 12.0 ||
      preedit_font_size > 32.0)
    throw std::invalid_argument("Invalid candidate card font size");
  CandidateCardMetrics metrics;
  // Selection number column plus the separator bar before the candidate text.
  metrics.number_and_bar = font_size * 0.8 + font_size * 0.2 + 8.0;
  metrics.min_width = font_size * 7.0;
  metrics.preedit_row = preedit_visible ? preedit_font_size * 1.4 + 6.0 : 0.0;
  metrics.candidate_row = font_size * 1.45 + 6.0;
  return metrics;
}
// Row rectangle in card coordinates. Horizontal lists share one row and split
// the width; the caller supplies the card width it actually got.
struct CandidateRowBounds {
  double left, top, right, bottom;
};
inline CandidateRowBounds candidate_row_bounds(size_t index, size_t count,
                                               double width,
                                               const CandidateCardMetrics &metrics,
                                               bool horizontal) {
  if (index >= count || count > 9 || !std::isfinite(width) || width <= 0.0)
    throw std::invalid_argument("Invalid candidate row");
  const double top = metrics.pad_y + metrics.preedit_row;
  if (!horizontal)
    return {metrics.pad_x / 2.0, top + metrics.candidate_row * static_cast<double>(index),
            width - metrics.pad_x / 2.0,
            top + metrics.candidate_row * static_cast<double>(index + 1)};
  const double column =
      (width - metrics.pad_x) / static_cast<double>(count);
  return {metrics.pad_x / 2.0 + column * static_cast<double>(index), top,
          metrics.pad_x / 2.0 + column * static_cast<double>(index + 1),
          top + metrics.candidate_row};
}
// Hit testing runs on the same rows the renderer drew.
inline std::optional<size_t>
candidate_card_hit(double x, double y, double width, double height,
                   size_t count, const CandidateCardMetrics &metrics,
                   bool horizontal) {
  if (count == 0 || count > 9 || !std::isfinite(x) || !std::isfinite(y) ||
      !std::isfinite(width) || !std::isfinite(height) || width <= 0.0 ||
      height <= 0.0 || x < 0.0 || y < 0.0 || x >= width || y >= height)
    return std::nullopt;
  for (size_t index = 0; index < count; ++index) {
    const auto row = candidate_row_bounds(index, count, width, metrics, horizontal);
    if (x >= row.left && x < row.right && y >= row.top && y < row.bottom)
      return index;
  }
  return std::nullopt;
}
inline CandidateCardSize candidate_card_size(const CandidateCardInput &input) {
  auto measured = [](double value) {
    return std::isfinite(value) && value >= 0.0;
  };
  if (input.item_widths.size() > 9 || !measured(input.preedit_width) ||
      !measured(input.max_width) || !measured(input.max_height))
    throw std::invalid_argument("Invalid candidate card measurement");
  for (double width : input.item_widths)
    if (!measured(width))
      throw std::invalid_argument("Invalid candidate card measurement");
  const auto shape = candidate_card_metrics(input.font_size,
                                            input.preedit_font_size,
                                            input.preedit_visible);
  const double number_and_bar = shape.number_and_bar;
  const double pad_x = shape.pad_x, pad_y = shape.pad_y,
               slack_x = shape.slack_x, slack_y = shape.slack_y;
  const double min_width = shape.min_width;
  const double preedit_row = shape.preedit_row;
  const double candidate_row = shape.candidate_row;

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
// Where the card sits relative to the caret. All values are physical pixels
// except scale, which is dpi/96; the design offsets below are DIPs so the gaps
// stay visually stable at 150% and 200%.
struct CandidatePlacementInput {
  // The line's bottom-left, as TSF reports the text extent.
  int anchor_x = 0;
  int anchor_y = 0;
  int width = 0;
  int height = 0;
  // The height the flip decision is made with. For a vertical list this is the
  // tallest the list has been this composition, not its current height, so a
  // list that grows as the user types does not jump below-to-above mid-word.
  // The card is still *placed* with its current height.
  int decision_height = 0;
  int work_left = 0, work_top = 0, work_right = 0, work_bottom = 0;
  double scale = 1.0;
};
struct CandidatePlacement {
  int x = 0;
  int y = 0;
  bool above = false;
};
// Position the card against the caret, flipping above the input line when a
// full list would not fit below it. Clamping alone is not enough: near the
// bottom of a screen it slides the card up over the very text being composed.
inline CandidatePlacement
candidate_card_placement(const CandidatePlacementInput &input) {
  const double scale = input.scale > 0.0 ? input.scale : 1.0;
  const int caret_gap = static_cast<int>(std::lround(3.0 * scale));
  const int edge_pad = static_cast<int>(std::lround(2.0 * scale));
  CandidatePlacement placement{input.anchor_x, input.anchor_y + caret_gap,
                               false};
  if (placement.x + input.width > input.work_right - edge_pad)
    placement.x = input.work_right - input.width - edge_pad;
  if (placement.x < input.work_left + edge_pad)
    placement.x = input.work_left + edge_pad;
  if (placement.y < input.work_top + edge_pad)
    placement.y = input.work_top + edge_pad;
  const int decision = (std::max)(input.decision_height, input.height);
  if (placement.y + decision > input.work_bottom) {
    // anchor_y is the line's bottom, so stepping back one line height puts the
    // card's lower edge at the line's top. A fixed gap instead of a line height
    // leaves a hole under short cards.
    const int line_height = static_cast<int>(std::lround(24.0 * scale));
    placement.y = input.anchor_y - input.height - line_height;
    placement.above = true;
    if (placement.y < input.work_top + edge_pad)
      placement.y = input.work_top + edge_pad;
  }
  return placement;
}
} // namespace msime::windows
