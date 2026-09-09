#pragma once
#include "FocusRouter.h"
#include "FocusedSession.h"
#include "PreferenceSnapshot.h"
#include <condition_variable>
#include <deque>
#include <functional>
#include <future>
#include <memory>

namespace msime::windows {
// Owned exclusively by InputQueue's worker, including construction/destruction.
// References to this object or its sessions must never escape a task.
class InputState final {
public:
  InputState(FocusGate &gate, size_t clients, std::string options);
  ~InputState();
  InputState(const InputState &) = delete;
  InputState &operator=(const InputState &) = delete;
  FocusRoute connected(const PipeTicket &ticket);
  FocusRoute disconnected(const PipeTicket &ticket);
  // Applies old-session cleanup and new-session preparation before returning.
  // The caller then schedules a fence on an I/O worker, never in this task.
  FocusRoute dispatch(const PipeTicket &ticket,
                      const FanyImeNamedpipeData &packet);
  bool confirmed(const FocusLease &lease);
  FocusRoute failed(const FocusLease &lease);
  std::optional<PendingReply>
  key(const FocusLease &lease, const FanyImeNamedpipeData &packet,
      ReplyPath path, bool uiless = false,
      std::optional<std::string> local_text = std::nullopt);
  bool delivered(const FocusLease &lease, uint64_t request);
  std::optional<PendingReply> configured_key(
      const FocusLease &lease, const FanyImeNamedpipeData &packet,
      TsfPreeditStyle style, const NavigationBindings &bindings,
      std::optional<std::string> local_text = std::nullopt,
      WordCharacterBinding word_binding = WordCharacterBinding::Disabled);
  std::optional<PendingReply> basic_key(const FocusLease &lease,
      const FanyImeNamedpipeData &packet, TsfPreeditStyle style,
      std::optional<std::string> local_text = std::nullopt);
  std::optional<PendingReply> edit(const FocusLease &lease,
      const FanyImeNamedpipeData &packet, TsfPreeditStyle style);
  bool synchronize_input_mode(const FocusLease &lease,
                              const FanyImeNamedpipeData &packet);
  bool queue_preferences(const FocusLease &lease, const std::string &snapshot);
  // Retain latest validated global settings for current and future focus.
  // Snapshot loading happens outside the input queue. Older/conflicting values
  // are rejected; identical publications are safe retries.
  void publish_preferences(const PreferenceSnapshot &snapshot);
  std::optional<PendingReply> navigate(const FocusLease &lease,
                                       const FanyImeNamedpipeData &packet,
                                       const NavigationBindings &bindings);
  std::optional<nlohmann::json> update_preferences(const FocusLease &lease,
                                                   const std::string &snapshot);

private:
  friend class InputQueue;
  void shutdown() noexcept;
  struct Client {
    PipeTicket ticket;
    std::unique_ptr<FocusedSession> session;
  };
  void check_thread() const;
  void cleanup(const FocusRoute &route);
  FocusedSession *session(const PipeTicket &ticket);
  const std::thread::id thread_ = std::this_thread::get_id();
  FocusGate &gate_;
  FocusRouter router_;
  std::string options_;
  std::optional<PreferenceSnapshot> preferences_;
  std::unordered_map<uint64_t, Client> clients_;
};

enum class InputTaskStatus { Completed, Failed, Cancelled };
struct InputQueueStats {
  size_t queued = 0;
  bool active = false;
  bool accepting = false;
  uint64_t completed = 0;
  uint64_t failed = 0;
  uint64_t cancelled = 0;
};
class InputQueue final {
public:
  using Task = std::function<void(InputState &)>;
  // Capacity bounds queued task count, not captured payload bytes. Controller
  // tasks must contain bounded copies, never borrowed pipe buffers or sessions.
  // Gate must outlive stop(). Tasks must not block on I/O or queue futures.
  InputQueue(FocusGate &gate, size_t clients, size_t capacity,
             std::string options);
  ~InputQueue();
  InputQueue(const InputQueue &) = delete;
  InputQueue &operator=(const InputQueue &) = delete;
  // Nonblocking admission. Full/stopped/empty task returns null. Every accepted
  // task settles its future, including cancellation. No silent input dropping:
  // caller must invalidate affected transport/focus on failed admission.
  std::optional<std::future<InputTaskStatus>> submit(Task task);
  void request_stop(); // May be called from a task; does not join.
  void stop();         // External control thread only; idempotent, joins.
  InputQueueStats stats() const;
  bool on_worker_thread() const noexcept;

private:
  struct Job {
    Task task;
    std::promise<InputTaskStatus> completion;
  };
  void run(FocusGate &gate, size_t clients, std::string options);
  size_t capacity_;
  mutable std::mutex mutex_;
  std::mutex stop_mutex_;
  std::condition_variable ready_;
  bool started_ = false;
  bool startup_failed_ = false;
  bool stopping_ = false;
  std::deque<Job> jobs_;
  InputQueueStats stats_;
  std::thread worker_;
};
} // namespace msime::windows
