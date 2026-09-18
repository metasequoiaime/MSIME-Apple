#pragma once
#include <filesystem>
#include <stdexcept>
#include <windows.h>

namespace msime::windows {
// Hold through resource preparation, all sessions and ordered Server shutdown.
// The stable file is never deleted: ownership is the OS handle, not existence.
class StateRootLease final {
public:
  explicit StateRootLease(const std::filesystem::path &root) {
    if (!root.is_absolute())
      throw std::invalid_argument("Relative state root");
    std::filesystem::create_directories(root);
    handle_ = CreateFileW((root / L".msime-client-server.lock").c_str(),
                          GENERIC_READ | GENERIC_WRITE, 0, nullptr, OPEN_ALWAYS,
                          FILE_ATTRIBUTE_NORMAL | FILE_FLAG_OPEN_REPARSE_POINT,
                          nullptr);
    if (handle_ == INVALID_HANDLE_VALUE)
      throw std::runtime_error("State root unavailable");
    BY_HANDLE_FILE_INFORMATION info{};
    if (!GetFileInformationByHandle(handle_, &info) ||
        (info.dwFileAttributes &
         (FILE_ATTRIBUTE_REPARSE_POINT | FILE_ATTRIBUTE_DIRECTORY))) {
      CloseHandle(handle_);
      handle_ = INVALID_HANDLE_VALUE;
      throw std::runtime_error("Invalid state lock file");
    }
  }
  ~StateRootLease() { CloseHandle(handle_); }
  StateRootLease(const StateRootLease &) = delete;
  StateRootLease &operator=(const StateRootLease &) = delete;

private:
  HANDLE handle_ = INVALID_HANDLE_VALUE;
};
} // namespace msime::windows
