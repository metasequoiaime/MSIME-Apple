#pragma once
#include <mutex>
#include <optional>
#include <string>
#include <vector>

namespace msime::windows {
struct ClipboardPresentation {
  uint64_t revision = 0;
  bool enabled = false;
  std::vector<std::string> items;
};

// UI-facing value mailbox. Clipboard storage/monitor writes snapshots; the
// window thread reads a copy and never touches the store or Win32 clipboard.
class ClipboardMailbox final {
public:
  void publish(bool enabled, std::vector<std::string> items);
  std::optional<ClipboardPresentation> snapshot() const;
  void clear();
private:
  mutable std::mutex mutex_;
  std::optional<ClipboardPresentation> latest_;
  uint64_t revision_ = 0;
};
} // namespace msime::windows
