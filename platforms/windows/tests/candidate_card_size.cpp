#include "CandidateCardSize.h"
#include <cmath>
#include <limits>
#include <stdexcept>

using namespace msime::windows;
void require(bool value) {
  if (!value)
    throw std::runtime_error("Candidate card size validation failed");
}
bool near(double value, double expected) {
  return std::fabs(value - expected) < 0.001;
}
bool rejected(CandidateCardInput input) {
  try {
    candidate_card_size(input);
  } catch (const std::invalid_argument &) {
    return true;
  }
  return false;
}
int main() {
  // Vertical list: the card follows the widest row and one row per candidate.
  CandidateCardInput vertical;
  vertical.preedit_width = 40.0;
  vertical.item_widths = {60.0, 120.0, 80.0};
  const auto stacked = candidate_card_size(vertical);
  require(near(stacked.width, 120.0 + 16.0 + 8.0 + 12.0 + 14.0));
  require(near(stacked.height, 8.0 + 10.0 + (16.0 * 1.4 + 6.0) +
                                   (16.0 * 1.45 + 6.0) * 3.0));

  // The same candidates on one line widen the card and keep a single row.
  CandidateCardInput horizontal = vertical;
  horizontal.horizontal = true;
  const auto inline_card = candidate_card_size(horizontal);
  require(near(inline_card.width, (60.0 + 120.0 + 80.0) + (16.0 + 8.0) * 3.0 +
                                      8.0 * 3.0 + 12.0 + 14.0));
  require(near(inline_card.height,
               8.0 + 10.0 + (16.0 * 1.4 + 6.0) + (16.0 * 1.45 + 6.0)));
  require(inline_card.width > stacked.width &&
          inline_card.height < stacked.height);

  // Hiding the preedit drops its row without touching the candidate rows.
  CandidateCardInput hidden = vertical;
  hidden.preedit_visible = false;
  const auto without_preedit = candidate_card_size(hidden);
  require(near(without_preedit.height,
               stacked.height - (16.0 * 1.4 + 6.0)));
  require(near(without_preedit.width, stacked.width));

  // A wide preedit drives the width once it passes the widest candidate.
  CandidateCardInput long_preedit = vertical;
  long_preedit.preedit_width = 400.0;
  require(near(candidate_card_size(long_preedit).width,
               400.0 + 6.0 + 12.0 + 14.0));

  // Zero-width entries are measured as hidden and reserve no row.
  CandidateCardInput sparse = vertical;
  sparse.item_widths = {60.0, 0.0, 0.0};
  require(near(candidate_card_size(sparse).height,
               stacked.height - (16.0 * 1.45 + 6.0) * 2.0));

  // An empty list still reserves one candidate row, and the floor applies.
  CandidateCardInput empty;
  empty.preedit_visible = false;
  const auto collapsed = candidate_card_size(empty);
  require(near(collapsed.width, 16.0 * 7.0));
  require(near(collapsed.height, 8.0 + 10.0 + (16.0 * 1.45 + 6.0)));

  // Work area caps clamp both axes; a cap of at most one pixel is no cap.
  CandidateCardInput capped = vertical;
  capped.max_width = 100.0;
  capped.max_height = 30.0;
  const auto clamped = candidate_card_size(capped);
  require(near(clamped.width, 100.0) && near(clamped.height, 30.0));
  capped.max_width = 1.0;
  capped.max_height = 0.0;
  require(near(candidate_card_size(capped).width, stacked.width) &&
          near(candidate_card_size(capped).height, stacked.height));

  // Font size scales every constant, including the minimum width.
  CandidateCardInput large = vertical;
  large.font_size = 24.0;
  large.preedit_font_size = 24.0;
  const auto scaled = candidate_card_size(large);
  require(scaled.width > stacked.width && scaled.height > stacked.height);
  require(near(scaled.width, 120.0 + 24.0 + 8.0 + 12.0 + 14.0));

  // Rows come from the same metrics the sizing used, so drawing and hit
  // testing cannot drift apart.
  const auto metrics = candidate_card_metrics(16.0, 16.0, true);
  require(near(metrics.candidate_row, 16.0 * 1.45 + 6.0) &&
          near(metrics.preedit_row, 16.0 * 1.4 + 6.0) &&
          near(metrics.number_and_bar, 16.0 + 8.0));
  require(near(candidate_card_metrics(16.0, 16.0, false).preedit_row, 0.0));
  for (double font : {11.0, 33.0}) {
    bool caught = false;
    try {
      candidate_card_metrics(font, 16.0, true);
    } catch (const std::invalid_argument &) {
      caught = true;
    }
    require(caught);
  }

  const double card_width = stacked.width;
  const auto first = candidate_row_bounds(0, 3, card_width, metrics, false);
  const auto second = candidate_row_bounds(1, 3, card_width, metrics, false);
  require(near(first.top, metrics.pad_y + metrics.preedit_row));
  require(near(first.bottom, first.top + metrics.candidate_row));
  require(near(second.top, first.bottom) && near(second.left, first.left));
  require(near(first.right, card_width - metrics.pad_x / 2.0));
  const auto column = candidate_row_bounds(1, 3, card_width, metrics, true);
  require(near(column.top, first.top) && near(column.bottom, first.bottom));
  require(near(column.right - column.left,
               (card_width - metrics.pad_x) / 3.0));
  for (auto invalid : {std::make_pair(size_t{3}, size_t{3}),
                       std::make_pair(size_t{0}, size_t{10})}) {
    bool caught = false;
    try {
      candidate_row_bounds(invalid.first, invalid.second, card_width, metrics,
                           false);
    } catch (const std::invalid_argument &) {
      caught = true;
    }
    require(caught);
  }

  // Clicks land on the row that was drawn; the preedit band selects nothing.
  const double card_height = stacked.height;
  auto row_of = [&](double x, double y) {
    return candidate_card_hit(x, y, card_width, card_height, 3, metrics, false);
  };
  require(row_of(20.0, first.top + 1.0) == std::optional<size_t>(0));
  require(row_of(20.0, second.top + 1.0) == std::optional<size_t>(1));
  require(!row_of(20.0, metrics.pad_y + 1.0));
  require(!row_of(20.0, card_height - 1.0));
  require(!row_of(-1.0, first.top + 1.0) && !row_of(card_width, first.top + 1.0));
  require(!candidate_card_hit(20.0, first.top + 1.0, card_width, card_height, 0,
                              metrics, false));
  require(candidate_card_hit(column.left + 1.0, column.top + 1.0, card_width,
                             card_height, 3, metrics,
                             true) == std::optional<size_t>(1));

  // Untrusted measurements and font sizes are rejected before any arithmetic.
  CandidateCardInput invalid;
  invalid.item_widths.assign(10, 10.0);
  require(rejected(invalid));
  invalid = vertical;
  invalid.preedit_width = -1.0;
  require(rejected(invalid));
  invalid = vertical;
  invalid.item_widths = {60.0, std::nan("")};
  require(rejected(invalid));
  invalid = vertical;
  invalid.max_width = std::numeric_limits<double>::infinity();
  require(rejected(invalid));
  for (double font : {11.0, 33.0, std::nan("")}) {
    invalid = vertical;
    invalid.font_size = font;
    require(rejected(invalid));
    invalid = vertical;
    invalid.preedit_font_size = font;
    require(rejected(invalid));
  }

  // Placement. A 1920x1040 work area, caret two thirds down the screen.
  CandidatePlacementInput place;
  place.work_left = 0;
  place.work_top = 0;
  place.work_right = 1920;
  place.work_bottom = 1040;
  place.anchor_x = 400;
  place.anchor_y = 700;
  place.width = 300;
  place.height = 120;
  place.decision_height = 120;

  // Room below: the card sits under the line, one 3 DIP caret gap down.
  auto below = candidate_card_placement(place);
  require(!below.above);
  require(below.x == 400 && below.y == 703);

  // No room below: it flips above the line rather than being slid up over the
  // text. anchor_y is the line's bottom, so the card's lower edge lands one
  // line height above it - and crucially the card no longer covers anchor_y.
  place.anchor_y = 1000;
  auto above = candidate_card_placement(place);
  require(above.above);
  require(above.y == 1000 - 120 - 24);
  require(above.y + place.height < 1000);

  // The old behaviour was pure clamping, which is exactly what must not happen:
  // clamping would have parked it at work_bottom - height = 920, on top of the
  // line at 1000. Guard against a regression to that.
  require(above.y != 1040 - 120);

  // Horizontal edges are padded by 2 DIP, both sides.
  place.anchor_y = 700;
  place.anchor_x = 1900;
  require(candidate_card_placement(place).x == 1920 - 300 - 2);
  place.anchor_x = -50;
  require(candidate_card_placement(place).x == 2);

  // A caret above the work area is pushed down to the padded top edge.
  place.anchor_x = 400;
  place.anchor_y = -500;
  require(candidate_card_placement(place).y == 2);

  // Hysteresis: a short list that would fit below still flips when the tallest
  // list this composition would not, so a growing list does not jump sides.
  place.anchor_y = 880;
  place.height = 60;
  place.decision_height = 60;
  require(!candidate_card_placement(place).above); // 880+3+60 <= 1040
  place.decision_height = 300;                     // ...but the full list would not
  const auto sticky = candidate_card_placement(place);
  require(sticky.above);
  // Placed with its CURRENT height, not the decision height, so the card hugs
  // the line instead of leaving a 300px hole under a 60px card.
  require(sticky.y == 880 - 60 - 24);

  // decision_height below the real height cannot shrink the decision.
  place.decision_height = 0;
  place.height = 600;
  place.anchor_y = 1000;
  require(candidate_card_placement(place).above);

  // A card taller than the screen still lands inside the work area rather than
  // off the top, even flipped.
  place.height = 2000;
  place.decision_height = 2000;
  require(candidate_card_placement(place).y == 2);

  // Scale moves the DIP offsets with the display: gaps are 3 and 24 DIP.
  place.height = 120;
  place.decision_height = 120;
  place.anchor_y = 700;
  place.anchor_x = 400;
  place.scale = 2.0;
  require(candidate_card_placement(place).y == 700 + 6);
  place.anchor_y = 1000;
  require(candidate_card_placement(place).y == 1000 - 120 - 48);
  // A nonsense scale falls back to 1.0 rather than collapsing the gaps to zero.
  place.scale = 0.0;
  place.anchor_y = 700;
  require(candidate_card_placement(place).y == 703);
}
