#pragma once
#include "AuxMessage.h"
#include <atomic>
#include <functional>
#include <memory>
#include <mutex>
#include <string>
#include <thread>
#include <windows.h>

namespace msime::windows {
class PipeListener;

// Counters only. The Aux message may describe where the user clicked, so the
// listener never records its contents (AGENTS.md forbids input in logs).
struct AuxStats {
  uint64_t accepted = 0;
  uint64_t malformed = 0;
  uint64_t unknown_verb = 0;
  uint64_t dispatched = 0;
};

// A fourth, session-less pipe endpoint. The TSF DLL writes one message and
// closes; there is no handshake, no registry entry and no client id, so this
// listener deliberately holds no reference to the input path: its outputs are
// a tray anchor and optional validated host-action messages.
class AuxListener final {
public:
  using Sink = std::function<void(const TrayMenuAnchor &)>;
  using MessageSink = std::function<void(const std::wstring &)>;
  // The IME activation edges reported by the TSF DLL.
  using ActivationSink = std::function<void(AuxActivation)>;
  // Return true once the client really has been deactivated; only then is the
  // "OK" the DLL is waiting on written back.
  using TerminalSink = std::function<bool(const AuxTerminalDeactivation &)>;
  static std::unique_ptr<AuxListener> create(const std::wstring &name,
                                             Sink sink, DWORD &error,
                                             MessageSink message_sink = {},
                                             ActivationSink activation = {},
                                             TerminalSink terminal = {});
  ~AuxListener();
  AuxListener(const AuxListener &) = delete;
  AuxListener &operator=(const AuxListener &) = delete;
  // Safe from inside the sink: signals only, never joins.
  void request_stop();
  void stop();
  DWORD failure() const { return failure_.load(); }
  AuxStats stats() const;

private:
  AuxListener() = default;
  void run();
  std::unique_ptr<PipeListener> listener_;
  Sink sink_;
  MessageSink message_sink_;
  ActivationSink activation_;
  TerminalSink terminal_;
  HANDLE cancel_ = nullptr;
  std::thread worker_;
  std::mutex stop_mutex_;
  mutable std::mutex stats_mutex_;
  AuxStats stats_;
  std::atomic<DWORD> failure_{ERROR_SUCCESS};
};
} // namespace msime::windows
