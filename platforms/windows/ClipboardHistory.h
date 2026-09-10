#pragma once
#include <filesystem>
#include <string>
#include <vector>
#include <functional>
#ifdef _WIN32
#include <windows.h>
#endif

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
  void set_enabled(bool enabled) { enabled_ = enabled; if (!enabled_) clear(); }
  bool enabled() const { return enabled_; }
private:
  std::filesystem::path store_;
  bool enabled_ = true;
};
std::string normalize_clipboard_text(std::string text);

#ifdef _WIN32
class ClipboardMonitor final {
public:
  using Callback = std::function<void(std::string)>;
  ClipboardMonitor(ClipboardHistory &history, Callback callback);
  ~ClipboardMonitor();
  ClipboardMonitor(const ClipboardMonitor &) = delete;
  bool start();
  void stop();
private:
  static LRESULT CALLBACK window_proc(HWND, UINT, WPARAM, LPARAM);
  ClipboardHistory &history_;
  Callback callback_;
  void *window_ = nullptr;
  unsigned long sequence_ = 0;
};
#endif
} // namespace msime::windows
