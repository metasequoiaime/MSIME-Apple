#pragma once

#include "PipeListener.h"
#include <atomic>
#include <functional>
#include <memory>
#include <mutex>
#include <string>
#include <thread>
#include <vector>

namespace msime::windows {
// A bounded, session-less message pipe for host actions that do not belong to
// an input client. It deliberately has no Engine or TSF knowledge; the owner
// decides which validated messages are actionable.
class AuxPipeService final {
public:
  using Message = std::function<void(const std::vector<uint8_t> &)>;

  AuxPipeService(std::wstring name, Message message,
                 DWORD operation_timeout = 250);
  ~AuxPipeService();
  AuxPipeService(const AuxPipeService &) = delete;
  AuxPipeService &operator=(const AuxPipeService &) = delete;

  void request_stop();
  void stop();
  DWORD failure() const { return failure_.load(); }

private:
  void listen();

  std::unique_ptr<PipeListener> listener_;
  HANDLE cancel_ = nullptr;
  Message message_;
  DWORD operation_timeout_ = 250;
  std::thread thread_;
  std::mutex stop_mutex_;
  std::atomic<DWORD> failure_{ERROR_SUCCESS};
};
} // namespace msime::windows
