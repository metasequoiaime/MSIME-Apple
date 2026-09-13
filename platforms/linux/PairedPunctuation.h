#pragma once

#include <cstddef>
#include <optional>
#include <string>
#include <string_view>
#include <utility>
#include <vector>

namespace msime::linux_host {

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
               bool following_known) {
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
