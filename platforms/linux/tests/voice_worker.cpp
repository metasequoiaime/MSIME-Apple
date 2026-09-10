#include "VoiceAction.h"
#include "VoiceWorker.h"

#include <atomic>
#include <cassert>
#include <chrono>
#include <thread>

int main() {
  assert(msime_voice_bound_result("水杉") == "水杉");
  auto oversized = msime_voice_bound_result("水杉水杉", 6);
  assert(oversized == "水杉");

  MsimeVoiceWorker worker;
  std::atomic_bool delivered{false};
  worker.run(
      [](const std::atomic_bool &cancelled) {
        while (!cancelled.load())
          std::this_thread::sleep_for(std::chrono::milliseconds(1));
        return std::string("cancelled");
      },
      [&](std::string) { delivered.store(true); });
  worker.cancel();
  assert(!delivered.load());

  worker.run([](const std::atomic_bool &) { return std::string("完成"); },
             [&](std::string value) {
               delivered.store(value == "完成");
             });
  for (int i = 0; i < 100 && !delivered.load(); ++i)
    std::this_thread::sleep_for(std::chrono::milliseconds(1));
  worker.cancel();
  assert(delivered.load());
}
