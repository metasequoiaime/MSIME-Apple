#pragma once

namespace msime::windows {
// The Engine's candidate source IDs that can be written to the user
// dictionary. Cloud/AI projections and Japanese candidates are display-only.
inline constexpr unsigned candidate_scheme_japanese = 3;

inline bool candidate_actions_available(unsigned scheme, unsigned source) {
  if (scheme == candidate_scheme_japanese)
    return false;
  return source == 0 || source == 1 || source == 4;
}
} // namespace msime::windows
