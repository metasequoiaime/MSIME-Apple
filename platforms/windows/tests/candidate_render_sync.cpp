#include "../CandidateRenderSync.h"

#include <stdexcept>

using msime::windows::should_wait_for_candidate_render;

namespace {
void require(bool value) {
  if (!value)
    throw std::runtime_error("candidate render sync regression");
}
} // namespace

int main() {
  require(!should_wait_for_candidate_render(0, 4, false, true));
  require(!should_wait_for_candidate_render(4, 4, false, true));
  require(should_wait_for_candidate_render(3, 4, false, true));
  require(!should_wait_for_candidate_render(3, 4, true, true));
  require(!should_wait_for_candidate_render(3, 4, false, false));
}
