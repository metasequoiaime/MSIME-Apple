#include "FocusGate.h"
#include <future>
#include <iostream>
#include <stdexcept>

using namespace msime::windows;
struct ReleaseOnExit {
  std::promise<void> &promise;
  bool done = false;
  ~ReleaseOnExit() {
    if (!done)
      promise.set_value();
  }
};
void require(bool value) {
  if (!value)
    throw std::runtime_error("Focus gate test failed");
}
int main() {
  try {
    FocusGate gate;
    PipeTicket a{11, {1, 2, 3}}, b{22, {4, 5, 6}};
    require(!gate.begin({}, 1));
    require(!gate.begin(a, 0));
    require(!gate.begin({11, {1, 0, 3}}, 1));
    auto first = *gate.begin(a, 71);
    require(!first.previous);
    auto wrong_token = first.pending;
    ++wrong_token.token;
    require(!gate.acknowledge(wrong_token, [] { return true; }));
    require(!gate.deactivate(wrong_token));
    unsigned effects = 0;
    require(!gate.with_active(first.pending, [&] { ++effects; }));
    require(gate.acknowledge(first.pending, [] { return true; }));
    require(!gate.acknowledge(first.pending, [&] {
      ++effects;
      return true;
    }));
    require(gate.with_active(first.pending, [&] { ++effects; }));
    require(effects == 1);
    auto second = *gate.begin(b, 72);
    require(second.previous && second.previous->epoch == first.pending.epoch);
    require(second.pending.epoch > first.pending.epoch);
    require(!gate.deactivate(first.pending));
    require(!gate.invalidate(a));
    require(!gate.acknowledge(first.pending, [&] {
      ++effects;
      return true;
    }));
    require(!gate.with_active(first.pending, [&] { ++effects; }));
    require(!gate.acknowledge(second.pending, [] { return false; }));
    require(!gate.with_active(second.pending, [&] { ++effects; }));
    auto third = *gate.begin(a, 73);
    require(!third.previous);
    bool threw = false;
    try {
      gate.acknowledge(third.pending, []() -> bool {
        throw std::runtime_error("Synthetic failure");
      });
    } catch (const std::runtime_error &) {
      threw = true;
    }
    require(threw && !gate.with_active(third.pending, [] {}));
    auto fourth = *gate.begin(a, 74);
    require(gate.acknowledge(fourth.pending, [] { return true; }));
    auto wrong = fourth.pending;
    ++wrong.transport.generations[0];
    require(!gate.with_active(wrong, [] {}));
    require(!gate.invalidate(wrong.transport));
    // A competing activation cannot pass an in-flight authorized action.
    std::promise<void> entered, release;
    auto released = release.get_future().share();
    auto acting = std::async(std::launch::async, [&] {
      return gate.with_active(fourth.pending, [&] {
        entered.set_value();
        released.wait();
      });
    });
    ReleaseOnExit release_guard{release};
    require(entered.get_future().wait_for(std::chrono::seconds(2)) ==
            std::future_status::ready);
    auto changing =
        std::async(std::launch::async, [&] { return gate.begin(b, 75); });
    const bool held = changing.wait_for(std::chrono::milliseconds(30)) ==
                      std::future_status::timeout;
    release.set_value();
    release_guard.done = true;
    require(held && acting.get());
    auto fifth = *changing.get();
    require(!gate.with_active(fourth.pending, [] {}));
    require(gate.acknowledge(fifth.pending, [] { return true; }));
    require(gate.invalidate(b));
    require(!gate.with_active(fifth.pending, [] {}));

    // A delayed deactivation from the previous client must not clear a newer
    // acknowledged focus lease, even when both lifecycle events are serialized
    // through the same gate.
    FocusGate stale;
    PipeTicket first_ticket{31, {7, 8, 9}};
    PipeTicket second_ticket{32, {10, 11, 12}};
    const auto first_change = *stale.begin(first_ticket, 81);
    require(stale.acknowledge(first_change.pending, [] { return true; }));
    const auto second_change = *stale.begin(second_ticket, 82);
    require(stale.acknowledge(second_change.pending, [] { return true; }));
    require(!stale.deactivate(first_change.pending));
    require(stale.with_active(second_change.pending, [] {}));

    // A reconnect from the same TSF client is a new session and must advance
    // the epoch; the old acknowledged lease must not authorize new input.
    FocusGate reconnect;
    PipeTicket client{41, {13, 14, 15}};
    const auto old_change = *reconnect.begin(client, 91);
    require(reconnect.acknowledge(old_change.pending, [] { return true; }));
    require(reconnect.deactivate(old_change.pending));
    const auto new_change = *reconnect.begin(client, 92);
    require(new_change.pending.epoch != old_change.pending.epoch);
    require(!reconnect.with_active(old_change.pending, [] {}));
    require(reconnect.acknowledge(new_change.pending, [] { return true; }));
    require(reconnect.with_active(new_change.pending, [] {}));
    std::cout << "Focus pending/ready, stale fences and serialized activation "
                 "passed\n";
  } catch (const std::exception &error) {
    std::cerr << error.what() << '\n';
    return 1;
  }
}
