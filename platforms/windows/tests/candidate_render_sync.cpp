#include "../src/candidate/CandidateRenderSync.h"

#include <stdexcept>

using msime::windows::should_wait_for_candidate_render;
using msime::windows::candidate_render_key;

namespace {
void require(bool value) {
  if (!value)
    throw std::runtime_error("candidate render sync regression");
}
} // namespace

int main() {
  require(candidate_render_key(0x20));
  require(candidate_render_key(0x30));
  require(candidate_render_key(0x39));
  require(candidate_render_key(0x60));
  require(candidate_render_key(0x69));
  require(!candidate_render_key(0x41));
  require(!candidate_render_key(0x25));
  // The controller passes zero when it has not observed a receipt. A visible
  // published frame must still reach the mailbox wait (including first paint).
  require(should_wait_for_candidate_render(0, 4, false, true));
  require(should_wait_for_candidate_render(0, 1, false, true));
  require(!should_wait_for_candidate_render(0, 0, false, true));
  require(!should_wait_for_candidate_render(4, 0, false, true));
  require(!should_wait_for_candidate_render(5, 4, false, true));
  require(!should_wait_for_candidate_render(0, 4, true, true));
  require(!should_wait_for_candidate_render(0, 4, false, false));
  require(!should_wait_for_candidate_render(4, 4, false, true));
  require(should_wait_for_candidate_render(3, 4, false, true));
  require(!should_wait_for_candidate_render(3, 4, true, true));
  require(!should_wait_for_candidate_render(3, 4, false, false));
}
