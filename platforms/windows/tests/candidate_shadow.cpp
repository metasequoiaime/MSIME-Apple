#include "CandidateShadow.h"
#include <cmath>
#include <stdexcept>

using namespace msime::windows;

namespace {
void require(bool value) {
  if (!value)
    throw std::runtime_error("Candidate shadow geometry validation failed");
}
bool near(double value, double expected) {
  return std::fabs(value - expected) < 0.001;
}
} // namespace

int main() {
  const auto frame = candidate_shadow_frame(320.0, 180.0, 36.0);
  require(near(frame.width, 384.0));
  require(near(frame.height, 276.0));
  require(near(frame.card_left, 32.0));
  require(near(frame.card_top, 56.0));
  require(near(frame.card_width, 320.0));
  require(near(frame.card_height, 180.0));

  CandidateShadowInsets none{0.0, 0.0, 0.0, 0.0};
  const auto plain = candidate_shadow_frame(320.0, 180.0, 0.0, none);
  require(near(plain.width, 320.0) && near(plain.height, 180.0));
  require(near(plain.card_left, 0.0) && near(plain.card_top, 0.0));

  CandidatePlacementInput placement;
  placement.anchor_x = 400;
  placement.anchor_y = 700;
  placement.width = 320;
  placement.height = 180;
  placement.decision_height = 180;
  placement.work_left = 0;
  placement.work_top = 0;
  placement.work_right = 1920;
  placement.work_bottom = 1040;
  const auto below = candidate_shadow_bounds(placement, {32, 20, 32, 40});
  // The visible card keeps its original caret alignment at (400, 703); only
  // the transparent popup bounds move outward.
  require(below.x == 368 && below.y == 683);
  require(below.width == 384 && below.height == 240);

  placement.anchor_x = 1900;
  const auto right = candidate_shadow_bounds(placement, {32, 20, 32, 40});
  require(right.x + right.width == 1918);

  bool rejected = false;
  try {
    candidate_shadow_frame(-1.0, 180.0, 0.0);
  } catch (const std::invalid_argument &) {
    rejected = true;
  }
  require(rejected);

  rejected = false;
  try {
    candidate_shadow_bounds(placement, {-1, 20, 32, 40});
  } catch (const std::invalid_argument &) {
    rejected = true;
  }
  require(rejected);
}
