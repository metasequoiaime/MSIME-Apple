#include "PairedPunctuation.h"

#include <cassert>

int main() {
  using msime::linux_host::PairedPunctuationTracker;
  using msime::linux_host::PairedPunctuationModifier;
  using msime::linux_host::paired_closing_modifiers_allowed;
  using msime::linux_host::paired_closing_for_key;

  PairedPunctuationTracker tracker;
  tracker.push("）");
  tracker.push("】");
  assert(tracker.size() == 2);
  assert(tracker.matches("】"));
  assert(!tracker.consume("）", "）", true));
  assert(tracker.empty());

  tracker.push("｝");
  assert(!tracker.consume("｝", "}", true));
  assert(tracker.empty());
  tracker.push("”");
  assert(tracker.consume("”", "”", true));
  assert(tracker.empty());
  tracker.push("〉");
  assert(!tracker.consume("〉", "", false));
  assert(tracker.empty());

  for (std::size_t index = 0; index < PairedPunctuationTracker::kMaxDepth + 3;
       ++index)
    tracker.push("）");
  assert(tracker.size() == PairedPunctuationTracker::kMaxDepth);

  assert(paired_closing_for_key('"', false) == "”");
  assert(paired_closing_for_key('\'', false) == "’");
  assert(paired_closing_for_key(')', false) == "）");
  assert(paired_closing_for_key('}', false) == "}");
  assert(paired_closing_for_key('}', true) == "｝");
  assert(!paired_closing_for_key(',', false));

  constexpr auto control =
      static_cast<unsigned>(PairedPunctuationModifier::Control);
  constexpr auto alt = static_cast<unsigned>(PairedPunctuationModifier::Alt);
  constexpr auto super =
      static_cast<unsigned>(PairedPunctuationModifier::Super);
  assert(paired_closing_modifiers_allowed(0));
  assert(paired_closing_modifiers_allowed(
      static_cast<unsigned>(PairedPunctuationModifier::Shift)));
  assert(!paired_closing_modifiers_allowed(control));
  assert(!paired_closing_modifiers_allowed(alt | super));

  tracker.push("）");
  assert(!tracker.consume("）", "）", true, false));
  assert(tracker.matches("）"));
  assert(tracker.consume("）", "）", true));
  return 0;
}
