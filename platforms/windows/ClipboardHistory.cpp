#include "ClipboardHistory.h"
#include <nlohmann/json.hpp>
#include <algorithm>
#include <fstream>

namespace msime::windows {
std::string normalize_clipboard_text(std::string text) {
  text.erase(std::remove(text.begin(), text.end(), '\0'), text.end());
  std::string normalized;
  normalized.reserve(text.size());
  for (size_t i = 0; i < text.size() && normalized.size() < ClipboardHistory::max_chars; ++i) {
    if (text[i] == '\r') {
      if (i + 1 < text.size() && text[i + 1] == '\n') ++i;
      normalized.push_back('\n');
    } else {
      normalized.push_back(text[i]);
    }
  }
  while (!normalized.empty() && (normalized.back() == '\n' || normalized.back() == ' ' || normalized.back() == '\t')) normalized.pop_back();
  return normalized;
}
ClipboardHistory::ClipboardHistory(std::filesystem::path store) : store_(std::move(store)) {}
std::vector<std::string> ClipboardHistory::load() const {
  std::ifstream input(store_);
  if (!input) return {};
  try {
    const auto value = nlohmann::json::parse(input);
    if (!value.is_array()) return {};
    std::vector<std::string> result;
    for (const auto &item : value) if (item.is_string() && result.size() < max_items) result.push_back(normalize_clipboard_text(item.get<std::string>()));
    result.erase(std::remove(result.begin(), result.end(), ""), result.end());
    return result;
  } catch (...) { return {}; }
}
bool ClipboardHistory::add(std::string text) {
  text = normalize_clipboard_text(std::move(text));
  if (text.empty()) return false;
  auto items = load();
  if (!items.empty() && items.front() == text) return false;
  items.erase(std::remove(items.begin(), items.end(), text), items.end());
  items.insert(items.begin(), std::move(text));
  if (items.size() > max_items) items.resize(max_items);
  std::filesystem::create_directories(store_.parent_path());
  std::ofstream output(store_, std::ios::trunc);
  if (!output) return false;
  output << nlohmann::json(items).dump();
  return static_cast<bool>(output);
}
bool ClipboardHistory::remove(const std::string &text) {
  auto items = load(); const auto before = items.size();
  items.erase(std::remove(items.begin(), items.end(), text), items.end());
  if (items.size() == before) return false;
  std::ofstream output(store_, std::ios::trunc); if (!output) return false;
  output << nlohmann::json(items).dump(); return static_cast<bool>(output);
}
bool ClipboardHistory::clear() {
  std::error_code error; return std::filesystem::remove(store_, error) || !std::filesystem::exists(store_);
}
} // namespace msime::windows
