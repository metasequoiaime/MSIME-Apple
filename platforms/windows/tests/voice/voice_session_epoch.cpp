#include "../../src/voice/VoiceSessionEpoch.h"
#include <cstdlib>
#include <future>
#include <stdexcept>
#include <thread>
#include <vector>

using msime::windows::VoiceSessionEpoch;
static void require(bool value) {
  if (!value)
    std::abort();
}

int main() {
  VoiceSessionEpoch epoch;
  const auto first = epoch.fetch_add(1) + 1;
  int effects = 0;
  require(epoch.with_current(first, [&] { ++effects; }));
  const auto second = epoch.fetch_add(1) + 1;
  // Late transcript, clear, cancel and commit effects are all rejected.
  for (int i = 0; i < 4; ++i)
    require(!epoch.with_current(first, [&] { ++effects; }));
  require(effects == 1);
  require(epoch.with_current(second, [&] { ++effects; }));
  require(effects == 2);
  // An effect that throws cannot strand the gate.
  try {
    epoch.with_current(second, [] { throw std::runtime_error("fixture"); });
    std::abort();
  } catch (const std::runtime_error &) {
  }
  require(epoch.fetch_add(1) == second);

  // Hold an accepted completion inside the gate while another thread tries
  // to advance. The new session's effect must follow, never be cleared by it.
  for (int iteration = 0; iteration < 100; ++iteration) {
    VoiceSessionEpoch concurrent;
    std::promise<void> entered, release, advancing;
    auto allowed = release.get_future();
    std::vector<int> order;
    std::thread completion([&] {
      require(concurrent.with_current(0, [&] {
        entered.set_value();
        allowed.wait();
        order.push_back(1);
      }));
    });
    entered.get_future().wait();
    std::thread next([&] {
      advancing.set_value();
      const auto generation = concurrent.fetch_add(1) + 1;
      require(concurrent.with_current(generation, [&] { order.push_back(2); }));
    });
    advancing.get_future().wait();
    release.set_value();
    completion.join();
    next.join();
    require((order == std::vector<int>{1, 2}));
    require(!concurrent.with_current(0, [&] { order.clear(); }));
    require(order.size() == 2);
  }
}
