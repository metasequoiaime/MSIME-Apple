#include "../src/candidates/PairedPunctuation.h"

#include <cassert>
#include <optional>
#include <string>

int main() {
  using msime::linux_host::PairedPunctuationTracker;
  using msime::linux_host::PairedPunctuationModifier;
  using msime::linux_host::paired_closing_modifiers_allowed;
  using msime::linux_host::paired_closing_for_key;
  using msime::linux_host::paired_punctuation_excluded_client;

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
  assert(paired_punctuation_excluded_client("/usr/bin/scalc"));
  assert(paired_punctuation_excluded_client("scalc.bin"));
  assert(paired_punctuation_excluded_client("GNUMERIC"));
  assert(!paired_punctuation_excluded_client("soffice.bin"));
  assert(!paired_punctuation_excluded_client("org.gnome.TextEditor"));

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
  {
    using msime::linux_host::normalize_punctuation_pair;
    using msime::linux_host::paired_closing_from_text;
    using Mode = msime::linux_host::PunctuationPairMode;
    std::string text = "（";
    assert(normalize_punctuation_pair(text, Mode::Bracket) && text == "（）");
    assert(paired_closing_from_text(text) == std::optional<std::string>("）"));
    text = "你好《";
    assert(normalize_punctuation_pair(text, Mode::Bracket) && text == "你好《》");
    text = "{";
    assert(normalize_punctuation_pair(text, Mode::Brace) && text == "{}");
    text = "｛";
    assert(normalize_punctuation_pair(text, Mode::Brace) && text == "｛｝");
    // Engine alternates quote halves; either one becomes a complete pair.
    text = "”";
    assert(normalize_punctuation_pair(text, Mode::DoubleQuote) && text == "“”");
    text = "‘";
    assert(normalize_punctuation_pair(text, Mode::SingleQuote) && text == "‘’");
    text = "(";
    assert(!normalize_punctuation_pair(text, Mode::Bracket) && text == "(");
    assert(!normalize_punctuation_pair(text, Mode::Unpaired));
  }
  return 0;
}
