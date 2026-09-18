#pragma once

#include <cstddef>
#include <cstdint>
#include <cctype>
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

// Spreadsheet cells on Linux cannot reliably preserve the caret move used by
// paired punctuation.  IBus supplies the focused client name, so keep the
// exclusion narrow to applications whose executable identifies as a
// spreadsheet.  LibreOffice's shared soffice.bin name is intentionally not
// included because it also hosts Writer and other editors.
inline bool paired_punctuation_excluded_client(std::string_view client) {
  const auto slash = client.find_last_of("/\\");
  client = client.substr(slash == std::string_view::npos ? 0 : slash + 1);
  std::string normalized;
  normalized.reserve(client.size());
  for (const unsigned char value : client)
    normalized.push_back(static_cast<char>(std::tolower(value)));
  return normalized == "scalc" || normalized == "scalc.bin" ||
         normalized == "libreoffice-calc" || normalized == "gnumeric" ||
         normalized == "org.gnome.gnumeric" ||
         normalized == "calligrasheets" ||
         normalized == "org.kde.calligrasheets";
}

}  // namespace msime::linux_host
