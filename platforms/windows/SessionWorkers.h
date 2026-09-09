#pragma once
#include "SessionPump.h"

namespace msime::windows {
struct SessionWorkerStats {
  size_t active = 0;
  size_t pending = 0;
  uint64_t finished = 0;
  uint64_t failed = 0;
  uint64_t rejected = 0;
  bool stopping = false;
};
// Fixed connection slots, each with one I/O thread and at most one replacement.
// A long-lived idle Main connection cannot consume an unbounded new thread.
class SessionWorkers final {
public:
  SessionWorkers(MainTransport &transport, InputQueue &input, FocusGate &focus,
                 size_t capacity, SessionPump::KeyHandler key,
                 SessionPump::EventHandler event,
                 SessionPump::Presentation presentation = {});
  ~SessionWorkers();
  SessionWorkers(const SessionWorkers &) = delete;
  SessionWorkers &operator=(const SessionWorkers &) = delete;
  // Control thread only: validates a negotiated ticket, cancels its superseded
  // connection, and queues one replacement. Rejected tickets are closed;
  // duplicate current tickets succeed without creating a second reader.
  // Cancellation may wait for a bounded in-flight write; don't call directly
  // from a nonblocking handshake callback or an input/gate callback.
  bool submit(const PipeTicket &ticket);
  void request_stop(); // Cancels reads and discards pending tickets; no join.
  void
  stop(); // External control thread; cancel then join, input queue stays live.
  SessionWorkerStats stats() const;

private:
  struct Slot {
    uint64_t client = 0;
    std::optional<PipeTicket> active;
    std::optional<PipeTicket> pending;
  };
  void run(size_t index);
  MainTransport &transport_;
  InputQueue &input_;
  SessionPump pump_;
  mutable std::mutex mutex_;
  std::mutex stop_mutex_;
  std::condition_variable ready_;
  std::vector<Slot> slots_;
  std::vector<std::thread> workers_;
  SessionWorkerStats stats_;
};
} // namespace msime::windows
