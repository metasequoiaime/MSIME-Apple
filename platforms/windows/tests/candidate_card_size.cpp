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
}
