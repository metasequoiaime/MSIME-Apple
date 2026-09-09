#include "SessionWorkers.h"
#include <algorithm>
#include <chrono>
#include <map>

using namespace msime::windows;
namespace {
void require(bool value) {
  if (!value)
    throw std::runtime_error("Session worker test failed");
}
class IdleTransport final : public MainTransport {
public:
  void add(const PipeTicket &ticket) {
    std::lock_guard lock(mutex_);
    current_[ticket.client] = ticket;
    ready_.notify_all();
  }
  bool current(const PipeTicket &ticket) override {
    std::lock_guard lock(mutex_);
    return matches(ticket);
  }
  std::optional<FanyImeNamedpipeData> read(const PipeTicket &ticket) override {
    std::unique_lock lock(mutex_);
    if (!matches(ticket))
      return std::nullopt;
    started_.push_back({ticket, std::this_thread::get_id()});
    ++reading_;
    peak_ = std::max(peak_, reading_);
    ready_.notify_all();
    ready_.wait(lock, [&] { return !matches(ticket); });
    --reading_;
    return std::nullopt;
  }
  bool send(const PipeTicket &, uint32_t,
            const std::vector<uint8_t> &) override {
    return false; // No input in this lifecycle-only fixture.
  }
  void close(const PipeTicket &ticket) noexcept override {
    std::lock_guard lock(mutex_);
    if (matches(ticket))
      current_.erase(ticket.client);
    ready_.notify_all();
  }
  void wait_started(size_t count) {
    std::unique_lock lock(mutex_);
    require(ready_.wait_for(lock, std::chrono::seconds(10),
                            [&] { return started_.size() >= count; }));
  }
  std::thread::id reader(const PipeTicket &ticket) {
    std::lock_guard lock(mutex_);
    for (const auto &[started, thread] : started_)
      if (same_ticket(started, ticket))
        return thread;
    return {};
  }
  size_t peak() {
    std::lock_guard lock(mutex_);
    return peak_;
  }

private:
  bool matches(const PipeTicket &ticket) const {
    auto found = current_.find(ticket.client);
    return found != current_.end() && same_ticket(found->second, ticket);
  }
  std::mutex mutex_;
  std::condition_variable ready_;
  std::map<uint64_t, PipeTicket> current_;
  std::vector<std::pair<PipeTicket, std::thread::id>> started_;
  size_t reading_ = 0;
  size_t peak_ = 0;
};
} // namespace
void session_worker_tests(const std::string &options) {
  FocusGate gate;
  InputQueue queue(gate, 2, 16, options);
  IdleTransport transport;
  auto key = [](InputState &, const FocusLease &,
                const FanyImeNamedpipeData &) -> std::optional<PendingReply> {
    return std::nullopt;
  };
  auto event = [](const FocusRoute &, const FanyImeNamedpipeData &) {
    return true;
  };
  SessionWorkers workers(transport, queue, gate, 2, key, event);
  PipeTicket a{42, {1, 2, 3}}, b{43, {4, 5, 6}}, c{44, {7, 8, 9}};
  transport.add(a);
  transport.add(b);
  require(workers.submit(a) && workers.submit(a) && workers.submit(b));
  transport.wait_started(2);
  require(workers.stats().active == 2 && workers.stats().pending == 0);
  transport.add(c);
  require(!workers.submit(c) && !transport.current(c));
  PipeTicket replacement{42, {10, 2, 3}};
  transport.add(replacement);
  require(workers.submit(replacement));
  transport.wait_started(3);
  require(transport.reader(a) == transport.reader(replacement));
  require(!workers.submit(a) && transport.current(replacement));
  auto forbidden = queue.submit([&](InputState &) {
    bool rejected = false;
    try {
      workers.stop();
    } catch (const std::logic_error &) {
      rejected = true;
    }
    require(rejected);
  });
  require(forbidden && forbidden->get() == InputTaskStatus::Completed);
  PipeTicket latest{42, {12, 2, 3}};
  {
    struct Release {
      std::promise<void> promise;
      bool done = false;
      void release() {
        if (!done) {
          done = true;
          promise.set_value();
        }
      }
      ~Release() { release(); }
    } release;
    auto resume = release.promise.get_future().share();
    std::promise<void> entered;
    auto blocked = queue.submit([&, resume](InputState &) {
      entered.set_value();
      resume.wait(); // Test-only barrier, not production queue behavior.
    });
    require(blocked.has_value());
    entered.get_future().wait();
    PipeTicket superseded{42, {11, 2, 3}};
    transport.add(superseded);
    require(workers.submit(superseded));
    transport.add(latest);
    require(workers.submit(latest));
    require(workers.stats().active == 2 && workers.stats().pending == 1);
    require(transport.current(latest) && !transport.current(superseded));
    release.release();
    require(blocked->get() == InputTaskStatus::Completed);
    transport.wait_started(4);
    require(transport.reader(superseded) == std::thread::id{} &&
            transport.reader(latest) == transport.reader(replacement));
  }
  auto stopping = std::async(std::launch::async, [&] { workers.stop(); });
  workers.stop();
  stopping.get();
  const auto stats = workers.stats();
  require(stats.active == 0 && stats.pending == 0 && stats.finished == 4 &&
          stats.failed == 0 && stats.stopping && transport.peak() == 2);
  require(!transport.current(latest) && !transport.current(b));
  require(queue.stats().accepting); // Pumps finish cleanup before queue stop.
  transport.add(c);
  require(!workers.submit(c) && !transport.current(c));
  queue.stop();
}
