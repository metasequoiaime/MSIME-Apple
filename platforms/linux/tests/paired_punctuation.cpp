#include "PairedPunctuation.h"

#include <cassert>

int main() {
  using msime::linux_host::PairedPunctuationTracker;
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
  return 0;
}
