#pragma once

#include <cstddef>
#include <string>
#include <string_view>
#include <vector>
#include <optional>

namespace msime::mac {

inline std::optional<std::string> paired_closing_for_key(char key, bool fullwidth) {
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

// Tracks only closing marks inserted by this host, so a later key can skip
// one without consuming text that belonged to the document already.
class PairedPunctuationTracker {
 public:
  static constexpr std::size_t kMaxDepth = 16;

  void clear() { closings_.clear(); }
  bool empty() const { return closings_.empty(); }

  void push(std::string closing) {
    if (closing.empty()) return;
    if (closings_.size() == kMaxDepth) closings_.erase(closings_.begin());
    closings_.push_back(std::move(closing));
  }

  bool consume(std::string_view closing, std::string_view following,
               bool followingKnown, bool modifiersAllowed = true) {
    if (!modifiersAllowed || closings_.empty() || closings_.back() != closing) return false;
    if (!followingKnown || following != closing) { clear(); return false; }
    closings_.pop_back();
    return true;
  }

 private:
  std::vector<std::string> closings_;
};

inline bool paired_closing_modifiers_allowed(unsigned long long flags,
                                             unsigned long long control,
                                             unsigned long long option,
                                             unsigned long long command) {
  return (flags & (control | option | command)) == 0;
}

}  // namespace msime::mac
