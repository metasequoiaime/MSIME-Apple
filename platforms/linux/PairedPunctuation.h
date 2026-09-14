#pragma once

#include <cstddef>
#include <cstdint>
#include <optional>
#include <string>
#include <string_view>
#include <utility>
#include <vector>

namespace msime::linux_host {

// Shift is intentionally absent from the rejected mask: on common layouts it
// is part of the key stroke for ), }, >, and quotes. The other modifiers must
// not turn a caret-over-existing-pair shortcut into an IME action.
enum class PairedPunctuationModifier : std::uint32_t {
  Control = 1u << 0,
  Alt = 1u << 1,
  Super = 1u << 2,
  Meta = 1u << 3,
  Hyper = 1u << 4,
  Mod5 = 1u << 5,
  Shift = 1u << 6,
};

constexpr bool paired_closing_modifiers_allowed(std::uint32_t modifiers) {
  constexpr auto disallowed =
      static_cast<std::uint32_t>(PairedPunctuationModifier::Control) |
      static_cast<std::uint32_t>(PairedPunctuationModifier::Alt) |
      static_cast<std::uint32_t>(PairedPunctuationModifier::Super) |
      static_cast<std::uint32_t>(PairedPunctuationModifier::Meta) |
      static_cast<std::uint32_t>(PairedPunctuationModifier::Hyper) |
      static_cast<std::uint32_t>(PairedPunctuationModifier::Mod5);
  return (modifiers & disallowed) == 0;
}

// Keep the same document invariant as the native Windows host: a closing mark
// may be skipped only while it is immediately to the right of the caret. The
// bound prevents swallowed keys from growing this state without limit.
class PairedPunctuationTracker {
 public:
  static constexpr std::size_t kMaxDepth = 16;

  void clear() { closings_.clear(); }
  bool empty() const { return closings_.empty(); }
  std::size_t size() const { return closings_.size(); }

  void push(std::string closing) {
    if (closing.empty()) return;
    if (closings_.size() >= kMaxDepth) closings_.erase(closings_.begin());
    closings_.push_back(std::move(closing));
  }

  bool matches(std::string_view closing) const {
    return !closings_.empty() && closings_.back() == closing;
  }

  // A failed document check invalidates the complete stack because the caret
  // has moved outside the sequence that was being tracked.
  bool consume(std::string_view closing, std::string_view following,
               bool following_known, bool modifiers_allowed = true) {
    if (!modifiers_allowed) return false;
    if (!matches(closing)) {
      if (!closings_.empty()) clear();
      return false;
    }
    if (!following_known || following != closing) {
      clear();
      return false;
    }
    closings_.pop_back();
    return true;
  }

 private:
  std::vector<std::string> closings_;
};

inline std::optional<std::string> paired_closing_for_key(char key,
                                                          bool fullwidth) {
  switch (key) {
    case '"': return std::string("”");
    case '\'': return std::string("’");
    case ')': return std::string("）");
    case ']': return std::string("】");
    case '}': return fullwidth ? std::string("｝") : std::string("}");
    case '>': return std::string("〉");
    default: return std::nullopt;
  }
}

}  // namespace msime::linux_host
