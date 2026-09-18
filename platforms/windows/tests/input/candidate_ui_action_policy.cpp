#include "input/CandidateUiActionPolicy.h"
#include <cassert>
#include <vector>

struct Candidate {
  uint64_t session;
  uint64_t generation;
  size_t index;
};

int main() {
  using msime::windows::valid_candidate_ui_index;
  assert(valid_candidate_ui_index(0));
  assert(valid_candidate_ui_index(9));
  assert(!valid_candidate_ui_index(10));
  using msime::windows::candidate_ui_action_matches;
  // Third page: visible slots 0..5 carry Engine IDs 12..17.
  std::vector<Candidate> page;
  for (size_t index = 12; index < 18; ++index)
    page.push_back({7, 11, index});
  assert(candidate_ui_action_matches(page, 7, 11, 12));
  assert(candidate_ui_action_matches(page, 7, 11, 17));
  assert(!candidate_ui_action_matches(page, 7, 11, 0));
  assert(!candidate_ui_action_matches(page, 7, 11, 18));
  assert(!candidate_ui_action_matches(page, 8, 11, 12));
  assert(!candidate_ui_action_matches(page, 7, 10, 12));
  for (size_t index = 18; index < 23; ++index)
    page.push_back({7, 11, index});
  assert(candidate_ui_action_matches(page, 7, 11, 21));
  assert(!candidate_ui_action_matches(page, 7, 11, 22));
  page.clear();
  assert(!candidate_ui_action_matches(page, 7, 11, 12));
}
