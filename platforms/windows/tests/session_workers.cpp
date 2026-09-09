#include "SessionController.h"
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
  std::atomic<int> write_failure{0};
  std::vector<std::pair<uint32_t, std::vector<uint8_t>>> writes() {
    std::lock_guard lock(mutex_);
    return writes_;
  }
  void add(const PipeTicket &ticket) {
    std::lock_guard lock(mutex_);
    current_[ticket.client] = ticket;
    packets_[ticket.client].clear();
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
    ready_.wait(lock, [&] {
      return !matches(ticket) || !packets_[ticket.client].empty();
    });
    --reading_;
    if (!matches(ticket))
      return std::nullopt;
    auto packet = packets_[ticket.client].front();
    packets_[ticket.client].pop_front();
    return packet;
  }
  bool send(const PipeTicket &ticket, uint32_t role,
            const std::vector<uint8_t> &bytes) override {
    std::lock_guard lock(mutex_);
    if (!matches(ticket)) return false;
    writes_.emplace_back(role, bytes);
    if (write_failure == 2)
      throw std::runtime_error("Synthetic write failure");
    return write_failure == 0;
  }
  void push(FanyImeNamedpipeData packet) {
    std::lock_guard lock(mutex_);
    packets_[packet.client_id].push_back(packet);
    ready_.notify_all();
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
  std::vector<std::pair<uint32_t, std::vector<uint8_t>>> writes_;
  std::condition_variable ready_;
  std::map<uint64_t, PipeTicket> current_;
  std::map<uint64_t, std::deque<FanyImeNamedpipeData>> packets_;
  std::vector<std::pair<PipeTicket, std::thread::id>> started_;
  size_t reading_ = 0;
  size_t peak_ = 0;
};
} // namespace
void session_worker_tests(const std::string &options) {
  for (int write_failure : {0, 1, 2}) {
    IdleTransport transport;
    RegistrationInbox inbox(2);
    PipeTicket ticket{42, {1, 2, 3}};
    SessionController *owner = nullptr;
    std::atomic<size_t> observed{0};
    std::promise<void> ui_entered, release_ui;
    auto entered = ui_entered.get_future();
    auto release = release_ui.get_future();
    SessionPump::Presentation presentation;
    presentation.delivered = [&](const FocusLease &, const PendingReply &reply,
                                 const FanyImeNamedpipeData &) {
      bool rejected = false;
      try {
        (void)owner->candidate_view();
      } catch (const std::logic_error &) {
        rejected = true;
      }
      require(rejected);
      ++observed;
      if (reply.ui_selection) {
        ui_entered.set_value();
        require(release.wait_for(std::chrono::seconds(10)) ==
                std::future_status::ready);
      }
    };
    SessionController controller(
        transport, inbox, 1, 8, options,
        [](InputState &state, const FocusLease &lease,
           const FanyImeNamedpipeData &packet) {
          return state.configured_key(lease, packet, TsfPreeditStyle::Local,
                                      {});
        },
        [](const FocusRoute &, const FanyImeNamedpipeData &) { return true; },
        [] { return true; }, [&] { transport.close(ticket); },
        std::chrono::milliseconds(10), {}, presentation);
    owner = &controller;
    require(!controller.candidate_view());
    transport.add(ticket);
    require(inbox.push(ticket));
    FanyImeNamedpipeData packet{};
    packet.client_id = ticket.client;
    packet.event_type = FanyImePipeEventType::ClientActivated;
    packet.request_id = 77;
    transport.push(packet);
    packet.event_type = FanyImePipeEventType::KeyEvent;
    packet.request_id = 2;
    packet.keycode = 'U';
    packet.wch = 'U';
    packet.modifiers_down = 1;
    transport.push(packet);
    transport.wait_started(3);
    const auto first = controller.candidate_view();
    require(first && first->visible && observed == 1);
    packet.request_id = 3;
    packet.keycode = '4';
    packet.wch = '4';
    packet.modifiers_down = 0;
    transport.push(packet);
    transport.wait_started(4);
    const auto second = controller.candidate_view();
    require(second && second->visible && observed == 2);
    require(second->generation > first->generation);
    for (char c : std::string("e2d")) {
      ++packet.request_id;
      packet.keycode = c >= 'a' && c <= 'z' ? c - 'a' + 'A' : c;
      packet.wch = c;
      transport.push(packet);
    }
    transport.wait_started(7);
    const auto shown = controller.candidate_view();
    require(shown && shown->candidates.at(0).text == "中");
    const auto candidate = shown->candidates.at(0);
    if (write_failure) {
      transport.write_failure = write_failure;
      require(controller.request_selection(shown->lease, candidate.session, candidate.generation, candidate.index) == SelectionRequestResult::Failed);
      require(observed == 5 && !transport.current(ticket) && !controller.candidate_view());
      controller.stop();
      require(controller.failure() != ControllerFailure::None);
      continue;
    }
    require(controller.request_selection(
                shown->lease, candidate.session, candidate.generation + 1,
                candidate.index) == SelectionRequestResult::Rejected);
    auto selection = std::async(std::launch::async, [&] {
      return controller.request_selection(shown->lease, candidate.session,
                                          candidate.generation,
                                          candidate.index);
    });
    require(entered.wait_for(std::chrono::seconds(10)) ==
            std::future_status::ready);
    const auto busy = controller.request_selection(
        shown->lease, candidate.session, candidate.generation, candidate.index);
    ++packet.request_id;
    packet.keycode = 'U';
    packet.wch = 'U';
    packet.modifiers_down = 1;
    transport.push(packet); // Must wait until the UI transaction finishes.
    release_ui.set_value();
    require(busy == SelectionRequestResult::Busy &&
            selection.get() == SelectionRequestResult::Sent);
    transport.wait_started(8);
    require(controller.failure() == ControllerFailure::None && observed == 7);
    const auto after_click = controller.candidate_view();
    require(after_click && after_click->visible &&
            after_click->generation > shown->generation);
    const auto writes = transport.writes();
    size_t commits = 0;
    for (const auto &write : writes)
      if (write.first == FanyImePipeRole::ToTsfWorkerThread &&
          write.second == ui_complete_selection("中")->worker)
        ++commits;
    require(commits == 1);
    transport.close(ticket);
    require(!controller.candidate_view());
    controller.stop();
    require(!controller.candidate_view());
  }
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
  for (int mode = 0; mode < 3; ++mode) {
    IdleTransport transport;
    RegistrationInbox inbox(2);
    std::promise<FocusLease> activated;
    auto activation = activated.get_future();
    SessionController *owner = nullptr;
    SessionController controller(
        transport, inbox, 1, 8, options,
        [](InputState &, const FocusLease &, const FanyImeNamedpipeData &)
            -> std::optional<PendingReply> { return std::nullopt; },
        [&](const FocusRoute &route, const FanyImeNamedpipeData &packet) {
          if (packet.event_type == FanyImePipeEventType::ClientActivated) {
            bool rejected = false;
            try {
              owner->request_mode(*route.route, WorkerMode::Fullwidth);
            } catch (const std::logic_error &) {
              rejected = true;
            }
            require(rejected); // No recursive focus lock from event callback.
            activated.set_value(*route.route);
          }
          return true;
        },
        [] { return true; }, [&] { transport.close(a); });
    owner = &controller;
    require(controller.request_mode({}, WorkerMode::Fullwidth) ==
            ModeRequestResult::Rejected);
    transport.add(a);
    require(inbox.push(a));
    FanyImeNamedpipeData packet{};
    packet.client_id = a.client;
    packet.event_type = FanyImePipeEventType::ClientActivated;
    packet.request_id = 77;
    transport.push(packet);
    require(activation.wait_for(std::chrono::seconds(10)) ==
            std::future_status::ready);
    const auto lease = activation.get();
    transport.wait_started(2); // Activation transaction has released its lock.
    auto stale = lease;
    ++stale.epoch;
    require(controller.request_mode(stale, WorkerMode::Fullwidth) ==
            ModeRequestResult::Rejected);
    stale = lease;
    ++stale.transport.generations[0];
    require(controller.request_mode(stale, WorkerMode::Fullwidth) ==
            ModeRequestResult::Rejected);
    require(controller.request_mode(lease, static_cast<WorkerMode>(99)) ==
            ModeRequestResult::Rejected);
    require(transport.writes().size() == 1); // Only the initial focus fence.
    transport.write_failure = mode;
    if (mode == 0) {
      for (auto command :
           {WorkerMode::English, WorkerMode::Chinese,
            WorkerMode::AsciiPunctuation, WorkerMode::ChinesePunctuation,
            WorkerMode::Fullwidth, WorkerMode::Halfwidth}) {
        require(controller.request_mode(lease, command) ==
                ModeRequestResult::Sent);
        const auto writes = transport.writes();
        require(writes.back().first == FanyImePipeRole::ToTsfWorkerThread &&
                writes.back().second == *worker_mode_bytes(command));
      }
      require(transport.writes().size() == 7);
    } else {
      require(controller.request_mode(lease, WorkerMode::Fullwidth) ==
              ModeRequestResult::WriteFailed);
      require(!transport.current(a));
      require(controller.request_mode(lease, WorkerMode::Fullwidth) ==
              ModeRequestResult::Rejected);
      require(transport.writes().size() ==
              2); // No replay after uncertain write.
    }
    controller.stop();
    require(controller.request_mode(lease, WorkerMode::Chinese) ==
            ModeRequestResult::Rejected);
  }
  for (int mode = 0; mode < 3; ++mode) {
    IdleTransport supervised;
    RegistrationInbox inbox(2);
    std::atomic<bool> healthy{true};
    std::promise<void> stopped;
    auto stopped_future = stopped.get_future();
    SessionController *owner = nullptr;
    SessionController controller(
        supervised, inbox, 2, 16, options,
        [](InputState &, const FocusLease &,
           const FanyImeNamedpipeData &) -> std::optional<PendingReply> {
          throw std::runtime_error("Synthetic supervised input failure");
        },
        [&](const FocusRoute &, const FanyImeNamedpipeData &) {
          if (mode == 2)
            owner->request_stop();
          return true;
        },
        [&] { return healthy.load(); },
        [&] {
          supervised.close(a);
          supervised.close(b);
          stopped.set_value();
        },
        std::chrono::milliseconds(10),
        nlohmann::json::parse(options).at("cache").get<std::string>());
    owner = &controller;
    const auto settings_deadline =
        std::chrono::steady_clock::now() + std::chrono::seconds(5);
    while (controller.preferences_status() !=
           PreferenceMonitorStatus::Current) {
      require(std::chrono::steady_clock::now() < settings_deadline);
      std::this_thread::sleep_for(std::chrono::milliseconds(5));
    }
    supervised.add(a);
    supervised.add(b);
    require(inbox.push(a) && inbox.push(b));
    supervised.wait_started(2);
    if (mode != 0) {
      FanyImeNamedpipeData packet{};
      packet.client_id = a.client;
      packet.event_type = FanyImePipeEventType::ClientActivated;
      packet.request_id = 77;
      supervised.push(packet);
      packet.event_type = FanyImePipeEventType::KeyEvent;
      packet.request_id = 2;
      packet.keycode = 'U';
      packet.wch = 'U';
      if (mode == 1)
        supervised.push(packet);
    } else {
      healthy = false;
    }
    require(stopped_future.wait_for(std::chrono::seconds(10)) ==
            std::future_status::ready);
    controller.stop();
    require(inbox.closed() && !supervised.current(a) && !supervised.current(b));
    require(controller.failure() == (mode == 1   ? ControllerFailure::InputQueue
                                     : mode == 0 ? ControllerFailure::Service
                                                 : ControllerFailure::None));
  }
}
