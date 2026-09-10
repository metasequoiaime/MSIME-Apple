#include "ClipboardHistory.h"
#include <nlohmann/json.hpp>
#include <algorithm>
#include <fstream>
#ifdef _WIN32
#include <windows.h>
#endif

namespace msime::windows {
namespace {
class StoreLock final {
public:
  StoreLock() {
#ifdef _WIN32
    handle_ = CreateMutexW(nullptr, FALSE, L"Local\\MSIMEClient.ClipboardHistory");
    if (handle_ && WaitForSingleObject(handle_, 5000) != WAIT_OBJECT_0) { CloseHandle(handle_); handle_ = nullptr; }
#endif
  }
  ~StoreLock() {
#ifdef _WIN32
    if (handle_) { ReleaseMutex(handle_); CloseHandle(handle_); }
#endif
  }
  explicit operator bool() const {
#ifdef _WIN32
    return handle_ != nullptr;
#else
    return true;
#endif
  }
private:
#ifdef _WIN32
  HANDLE handle_ = nullptr;
#endif
};
std::vector<std::string> read_store(const std::filesystem::path &path) {
  std::ifstream input(path); if (!input) return {};
  try { const auto value = nlohmann::json::parse(input); if (!value.is_array()) return {}; std::vector<std::string> result; for (const auto &item : value) if (item.is_string() && result.size() < ClipboardHistory::max_items) result.push_back(normalize_clipboard_text(item.get<std::string>())); result.erase(std::remove(result.begin(), result.end(), ""), result.end()); return result; } catch (...) { return {}; }
}
bool write_store(const std::filesystem::path &path, const std::vector<std::string> &items) {
  std::filesystem::create_directories(path.parent_path()); std::ofstream output(path, std::ios::trunc); if (!output) return false; output << nlohmann::json(items).dump(); return static_cast<bool>(output);
}
}
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
  StoreLock lock; return lock ? read_store(store_) : std::vector<std::string>{};
}
bool ClipboardHistory::add(std::string text) {
  if (!enabled_) return false;
  text = normalize_clipboard_text(std::move(text));
  if (text.empty()) return false;
  StoreLock lock; if (!lock) return false;
  auto items = read_store(store_);
  if (!items.empty() && items.front() == text) return false;
  items.erase(std::remove(items.begin(), items.end(), text), items.end());
  items.insert(items.begin(), std::move(text));
  if (items.size() > max_items) items.resize(max_items);
  return write_store(store_, items);
}
bool ClipboardHistory::remove(const std::string &text) {
  StoreLock lock; if (!lock) return false;
  auto items = read_store(store_); const auto before = items.size();
  items.erase(std::remove(items.begin(), items.end(), text), items.end());
  if (items.size() == before) return false;
  return write_store(store_, items);
}
bool ClipboardHistory::clear() {
  StoreLock lock; if (!lock) return false;
  std::error_code error; return std::filesystem::remove(store_, error) || !std::filesystem::exists(store_);
}
} // namespace msime::windows
