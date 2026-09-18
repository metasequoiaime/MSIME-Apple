#include "input/CandidateUiActionPolicy.h"
#include <cassert>

int main() {
  using msime::windows::valid_candidate_ui_index;
  assert(valid_candidate_ui_index(0));
  assert(valid_candidate_ui_index(9));
  assert(!valid_candidate_ui_index(10));
}
