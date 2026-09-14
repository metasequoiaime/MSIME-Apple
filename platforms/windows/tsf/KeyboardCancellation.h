#pragma once
#include <cstdint>

namespace msime::tsf {
struct KeyboardCancellationIdentity {
  std::uint64_t focus = 0;
  std::uint64_t composition = 0;
};

inline bool keyboard_cancellation_matches(KeyboardCancellationIdentity expected,
                                          KeyboardCancellationIdentity current,
                                          bool negotiated, bool keyboard) {
  return negotiated && keyboard && expected.focus != 0 &&
         expected.composition != 0 && expected.focus == current.focus &&
         expected.composition == current.composition;
}

// Every host operation can re-enter. Never continue a stale transaction or
// turn a failed deletion/end into success. Retire only the exact ended object.
template <class Result, class Current, class Prepare, class Clear, class End,
          class Retire>
Result cancel_keyboard_composition(Result applied, Result stale,
                                   Current current, Prepare prepare,
                                   Clear clear, End end, Retire retire) {
  if (!current())
    return stale;
  auto result = prepare();
  if (result != applied)
    return result;
  if (!current())
    return stale;
  result = clear();
  if (result != applied)
    return result;
  if (!current())
    return stale;
  result = end();
  if (result != applied)
    return result;
  return retire();
}
} // namespace msime::tsf
