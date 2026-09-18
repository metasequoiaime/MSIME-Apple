#include "CandidateWheel.h"
#include <stdexcept>

using namespace msime::windows;

int main() {
  int accumulator = 0;
  auto steps = consume_candidate_wheel_delta(accumulator, 40, 120);
  if (steps.page_up != 0 || steps.page_down != 0 || accumulator != 40)
    throw std::runtime_error("partial wheel delta was not retained");
  steps = consume_candidate_wheel_delta(accumulator, 80, 120);
  if (steps.page_up != 1 || steps.page_down != 0 || accumulator != 0)
    throw std::runtime_error("wheel notch was not emitted");
  steps = consume_candidate_wheel_delta(accumulator, -120, 120);
  if (steps.page_up != 0 || steps.page_down != 1 || accumulator != 0)
    throw std::runtime_error("wheel direction was not mapped to paging");
  consume_candidate_wheel_delta(accumulator, 80, 120);
  steps = consume_candidate_wheel_delta(accumulator, -120, 120);
  if (steps.page_down != 1 || accumulator != 0)
    throw std::runtime_error("wheel reversal retained stale travel");
}
