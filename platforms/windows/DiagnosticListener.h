#pragma once

#include "DiagnosticBatch.h"

#include <windows.h>

#include <atomic>
#include <functional>
#include <memory>
#include <mutex>
#include <string>
#include <thread>

namespace msime::windows {
class PipeListener;

// The fifth pipe: TIP diagnostics.
//
// The TIP side was ported in full - the bounded queue, the 250 ms flush and
// the writer - but nothing on the Server ever opened this pipe, so enabling
// diagnostic logging produced nothing at all. Session-less like the Aux
// endpoint: it holds no registry, no session and no window, because a TIP that
// is failing to compose is exactly the one whose diagnostics matter, and it
// must be able to report without a working session.
class DiagnosticListener final {
public:
  using Sink = std::function<void(const DiagnosticBatch &)>;
  struct Stats {
    uint64_t accepted = 0;
    uint64_t batches = 0;
    uint64_t malformed = 0;
    // Records the TIPs reported having dropped, summed. A gap in the log is
    // worth surfacing rather than leaving invisible.
    uint64_t dropped_records = 0;
  };

  static std::unique_ptr<DiagnosticListener>
  create(const std::wstring &name, Sink sink, DWORD &error);
  ~DiagnosticListener();
  DiagnosticListener(const DiagnosticListener &) = delete;
  DiagnosticListener &operator=(const DiagnosticListener &) = delete;
  void request_stop();
  void stop();
  DWORD failure() const { return failure_.load(); }
  Stats stats() const;

private:
  DiagnosticListener() = default;
  void run();
  std::unique_ptr<PipeListener> listener_;
  Sink sink_;
  HANDLE cancel_ = nullptr;
  std::thread worker_;
  std::mutex stop_mutex_;
  mutable std::mutex stats_mutex_;
  Stats stats_;
  std::atomic<DWORD> failure_{ERROR_SUCCESS};
};
} // namespace msime::windows
