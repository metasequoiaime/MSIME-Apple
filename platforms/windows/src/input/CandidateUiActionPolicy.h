#pragma once

#include <cstddef>
#include <cstdint>

namespace msime::windows {
// The legacy Windows UI exposes PAGE slots as 1..10. Engine IDs are global
// indices and may exceed 9 after paging; never apply this limit to an ID.
inline constexpr size_t candidate_ui_max_count = 10;

constexpr bool valid_candidate_ui_index(size_t index) noexcept {
  return index < candidate_ui_max_count;
}

template <class Candidates>
bool candidate_ui_action_matches(const Candidates &page, uint64_t session,
                                 uint64_t generation, size_t engine_index) {
  for (size_t slot = 0; slot < page.size() && valid_candidate_ui_index(slot);
       ++slot) {
    const auto &candidate = page[slot];
    if (candidate.index == engine_index && candidate.session == session &&
        candidate.generation == generation)
      return true;
  }
  return false;
}
} // namespace msime::windows
