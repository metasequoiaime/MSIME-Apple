#pragma once
#include <filesystem>
#include <string>
#include <vector>

namespace msime::windows {
class ClipboardHistory final {
public:
  static constexpr size_t max_items = 50;
  static constexpr size_t max_chars = 4000;
  explicit ClipboardHistory(std::filesystem::path store);
  std::vector<std::string> load() const;
  bool add(std::string text);
  bool remove(const std::string &text);
  bool clear();
private:
  std::filesystem::path store_;
};
std::string normalize_clipboard_text(std::string text);
} // namespace msime::windows
