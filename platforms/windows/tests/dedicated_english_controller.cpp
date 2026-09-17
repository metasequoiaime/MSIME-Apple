#include "../SessionController.h"
#include "../DedicatedEnglishMailbox.h"
#include "TestHostOptions.h"
#include <cassert>
using namespace msime::windows;
class ModeTransport final : public MainTransport {
public:
  const PipeTicket ticket{42, {1, 2, 3}};
  bool current(const PipeTicket &value) override {
    return !closed && same_ticket(ticket, value);
  }
  bool try_current(const PipeTicket &value) override { return current(value); }
  std::optional<FanyImeNamedpipeData> read(const PipeTicket &value) override {
    std::unique_lock lock(mutex);
    if (!current(value)) return std::nullopt;
    if (!activated) {
      activated = true;
      FanyImeNamedpipeData packet{};
      packet.client_id = ticket.client;
      packet.event_type = FanyImePipeEventType::ClientActivated;
      packet.request_id = 77;
      return packet;
    }
    ready.wait(lock, [&] { return closed.load(); });
    return std::nullopt;
  }
  KeyEventSendResult send(const PipeTicket &value, uint32_t,
                         const std::vector<uint8_t> &) override {
    if (!current(value)) return KeyEventSendResult::DefinitelyNotSent;
    ++writes;
    return KeyEventSendResult::Sent;
  }
  void close(const PipeTicket &) noexcept override {
    std::lock_guard lock(mutex);
    closed = true;
    ready.notify_all();
  }
  std::atomic<unsigned> writes{0};
private:
  std::atomic<bool> closed{false};
  bool activated = false;
  std::mutex mutex;
  std::condition_variable ready;
};
int main() {
  const auto root = std::filesystem::temp_directory_path() /
      ("msime-english-controller-" + std::to_string(
          std::chrono::steady_clock::now().time_since_epoch().count()));
  std::filesystem::create_directory(root);
  struct Cleanup {
    std::filesystem::path path;
    ~Cleanup() { std::error_code ec; std::filesystem::remove_all(path, ec); }
  } cleanup{root};
  // Both defaults describe the host's own passthrough for a new focus
  // session. Neither may start the Engine in dedicated English, which the
  // CN/EN switch cannot leave.
  for (const char *mode : {"chinese", "english"}) {
    auto options = test_host_options(root / mode);
    options["preferences"]["default_ime_mode"] = mode;
    ModeTransport transport;
    RegistrationInbox inbox(1);
    std::promise<FocusLease> activation;
    auto activated = activation.get_future();
    SessionController *owner = nullptr;
    SessionController controller(transport, inbox, 1, 8, options.dump(),
        [](InputState &, const FocusLease &, const FanyImeNamedpipeData &)
            -> std::optional<PendingReply> { return std::nullopt; },
        [&](const FocusRoute &route, const FanyImeNamedpipeData &) {
          bool rejected = false;
          try { (void)owner->dedicated_english_state(*route.route); }
          catch (const std::logic_error &) { rejected = true; }
          assert(rejected);
          activation.set_value(*route.route);
          return true;
        }, [] { return true; }, [&] { transport.close(transport.ticket); });
    owner = &controller;
    assert(!controller.dedicated_english_state({}));
    assert(inbox.push(transport.ticket));
    assert(activated.wait_for(std::chrono::seconds(10)) == std::future_status::ready);
    const auto lease = activated.get();
    std::optional<bool> result;
    const auto deadline = std::chrono::steady_clock::now() + std::chrono::seconds(5);
    while (!(result = controller.dedicated_english_state(lease)) &&
           std::chrono::steady_clock::now() < deadline)
      std::this_thread::sleep_for(std::chrono::milliseconds(1));
    assert(result && *result == false);
    assert(transport.writes == 1); // Only the activation fence; reads send nothing.
    assert(controller.reset_cache());
    DedicatedEnglishMailbox mailbox;
    assert(!mailbox.snapshot(lease));
    mailbox.publish(lease, *result);
    assert(mailbox.snapshot(lease) == false);
    // The mailbox reports whatever the queue observed, including a mode the
    // user turns on at runtime; only the lease decides what it will answer.
    mailbox.publish(lease, true);
    assert(mailbox.snapshot(lease) == true);
    auto stale = lease;
    ++stale.token;
    assert(!controller.dedicated_english_state(stale));
    assert(!mailbox.snapshot(stale));
    stale = lease;
    ++stale.transport.generations[0];
    assert(!controller.dedicated_english_state(stale));
    assert(!mailbox.snapshot(stale));
    controller.stop();
    assert(!controller.dedicated_english_state(lease));
  }
}
