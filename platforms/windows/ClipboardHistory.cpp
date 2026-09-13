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
  explicit StoreLock(const std::filesystem::path &store) {
#ifdef _WIN32
    auto lock_path = store;
    lock_path += ".lock";
    handle_ = CreateFileW(lock_path.c_str(), GENERIC_READ | GENERIC_WRITE,
                          FILE_SHARE_READ | FILE_SHARE_WRITE | FILE_SHARE_DELETE,
                          nullptr, OPEN_ALWAYS, FILE_ATTRIBUTE_NORMAL, nullptr);
    if (handle_ == INVALID_HANDLE_VALUE) {
      handle_ = nullptr;
      return;
    }
    OVERLAPPED offset{};
    if (!LockFileEx(handle_, LOCKFILE_EXCLUSIVE_LOCK, 0, MAXDWORD, MAXDWORD,
                    &offset)) {
      CloseHandle(handle_);
      handle_ = nullptr;
    }
#else
    (void)store;
#endif
  }
  ~StoreLock() {
#ifdef _WIN32
    if (handle_) {
      OVERLAPPED offset{};
      UnlockFileEx(handle_, 0, MAXDWORD, MAXDWORD, &offset);
      CloseHandle(handle_);
    }
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
  std::error_code error;
  std::filesystem::create_directories(path.parent_path(), error);
  if (error) return false;
  const auto payload = nlohmann::json(items).dump();
#ifdef _WIN32
  auto temporary = path;
  temporary += ".tmp";
  temporary += std::to_string(GetCurrentProcessId());
  std::ofstream output(temporary, std::ios::binary | std::ios::trunc);
  if (!output) return false;
  output.write(payload.data(), static_cast<std::streamsize>(payload.size()));
  output.close();
  if (!output) {
    std::filesystem::remove(temporary, error);
    return false;
  }
  if (!MoveFileExW(temporary.c_str(), path.c_str(),
                   MOVEFILE_REPLACE_EXISTING | MOVEFILE_WRITE_THROUGH)) {
    std::filesystem::remove(temporary, error);
    return false;
  }
  return true;
#else
  std::ofstream output(path, std::ios::binary | std::ios::trunc);
  if (!output) return false;
  output.write(payload.data(), static_cast<std::streamsize>(payload.size()));
  return static_cast<bool>(output);
#endif
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
  StoreLock lock(store_); return lock ? read_store(store_) : std::vector<std::string>{};
}
bool ClipboardHistory::add(std::string text) {
  if (!enabled_) return false;
  text = normalize_clipboard_text(std::move(text));
  if (text.empty()) return false;
  StoreLock lock(store_); if (!lock) return false;
  auto items = read_store(store_);
  if (!items.empty() && items.front() == text) return false;
  items.erase(std::remove(items.begin(), items.end(), text), items.end());
  items.insert(items.begin(), std::move(text));
  if (items.size() > max_items) items.resize(max_items);
  return write_store(store_, items);
}
bool ClipboardHistory::remove(const std::string &text) {
  StoreLock lock(store_); if (!lock) return false;
  auto items = read_store(store_); const auto before = items.size();
  items.erase(std::remove(items.begin(), items.end(), text), items.end());
  if (items.size() == before) return false;
  return write_store(store_, items);
}
bool ClipboardHistory::clear() {
  StoreLock lock(store_); if (!lock) return false;
  std::error_code error; return std::filesystem::remove(store_, error) || !std::filesystem::exists(store_);
}
} // namespace msime::windows
