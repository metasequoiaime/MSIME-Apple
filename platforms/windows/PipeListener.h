#pragma once
#include "PipeIo.h"
#include <memory>
#include <string>
#include <utility>

namespace msime::windows {
class PipeListener;
class PipeConnection final {
public:
  ~PipeConnection();
  PipeConnection(const PipeConnection &) = delete;
  PipeConnection &operator=(const PipeConnection &) = delete;
  HANDLE handle() const { return handle_; }

private:
  friend class PipeListener;
  PipeConnection() = default;
  HANDLE handle_ = INVALID_HANDLE_VALUE;
};
struct PipeAccept {
  IoResult io;
  std::unique_ptr<PipeConnection> connection;
};
// One worker owns the listener. Never destroy it during accept(), or destroy
// a returned connection during any operation using its borrowed handle.
// Creation publishes a real local pipe name but does not install/register TSF.
// Timeout initiates cancellation and drains completion, not a hard deadline.
// Cancellation discards a client that races with it. Returned connections are
// untrusted until PipeHandshake/PipePeer and the routing registry accept them.
class PipeListener final {
public:
  static std::unique_ptr<PipeListener> create(const std::wstring &name,
                                              DWORD &error);
  ~PipeListener();
  PipeListener(const PipeListener &) = delete;
  PipeListener &operator=(const PipeListener &) = delete;
  PipeAccept accept(DWORD timeout_ms, HANDLE cancel = nullptr);

private:
  explicit PipeListener(std::wstring name) : name_(std::move(name)) {}
  HANDLE instance(bool first) const;
  std::wstring name_;
  PSECURITY_DESCRIPTOR security_ = nullptr;
  HANDLE pending_ = INVALID_HANDLE_VALUE;
};
} // namespace msime::windows
