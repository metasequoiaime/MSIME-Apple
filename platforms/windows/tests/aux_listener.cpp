#include "AuxListener.h"
#include <atomic>
#include <chrono>
#include <condition_variable>
#include <cstring>
#include <iostream>
#include <mutex>
#include <stdexcept>
#include <string>
#include <vector>
#include <functional>

using namespace msime::windows;
namespace {
void require_at(bool value, int line) {
  if (!value)
    throw std::runtime_error("Aux listener test failed at line " +
                             std::to_string(line));
}
std::wstring isolated_name(int serial) {
  return L"\\\\.\\pipe\\MSIMEClientAuxTest-" +
         std::to_wstring(GetCurrentProcessId()) + L"-" +
         std::to_wstring(serial);
}
// Write exactly what the TSF DLL writes: raw code units, no NUL terminator.
bool send_like_tsf(const std::wstring &name, const std::wstring &message) {
  for (int attempt = 0; attempt < 50; ++attempt) {
    HANDLE pipe = CreateFileW(name.c_str(), GENERIC_READ | GENERIC_WRITE, 0,
                              nullptr, OPEN_EXISTING,
                              SECURITY_SQOS_PRESENT | SECURITY_IDENTIFICATION,
                              nullptr);
    if (pipe == INVALID_HANDLE_VALUE) {
      Sleep(20);
      continue;
    }
    DWORD written = 0;
    const DWORD size = static_cast<DWORD>(message.size() * sizeof(wchar_t));
    const BOOL ok = WriteFile(pipe, message.data(), size, &written, nullptr);
    CloseHandle(pipe);
    return ok && written == size;
  }
  return false;
}
// The DLL writes one message and closes immediately, so the Server must already
// be parked in accept() to catch it; otherwise ConnectNamedPipe reports
// ERROR_NO_DATA and the message is lost. A long-running Server satisfies that,
// but a just-created listener in a test may not yet have reached accept(), so
// retry until the endpoint is actually listening.
bool deliver(const std::wstring &name, const std::wstring &message,
             const std::function<uint64_t()> &progress, uint64_t target) {
  for (int attempt = 0; attempt < 100; ++attempt) {
    if (!send_like_tsf(name, message))
      return false;
    for (int spin = 0; spin < 10; ++spin) {
      if (progress() >= target)
        return true;
      Sleep(10);
    }
  }
  return false;
}
class Collected final {
public:
  void add(const TrayMenuAnchor &anchor) {
    std::lock_guard<std::mutex> lock(mutex_);
    anchors_.push_back(anchor);
    ready_.notify_all();
  }
  bool wait_for(size_t count) {
    std::unique_lock<std::mutex> lock(mutex_);
    return ready_.wait_for(lock, std::chrono::seconds(5),
                           [&] { return anchors_.size() >= count; });
  }
  std::vector<TrayMenuAnchor> snapshot() {
    std::lock_guard<std::mutex> lock(mutex_);
    return anchors_;
  }

private:
  std::mutex mutex_;
  std::condition_variable ready_;
  std::vector<TrayMenuAnchor> anchors_;
};
} // namespace
#define require(...) require_at((__VA_ARGS__), __LINE__)

int main() {
  try {
    {
      // A client byte-identical to the TSF DLL reaches the sink.
      const auto name = isolated_name(1);
      Collected collected;
      DWORD error = ERROR_SUCCESS;
      std::atomic<int> activations{0};
      std::atomic<int> deactivations{0};
      auto listener = AuxListener::create(
          name, [&](const TrayMenuAnchor &a) { collected.add(a); }, error, {},
          [&](AuxActivation activation) {
            if (activation == AuxActivation::Activated)
              ++activations;
            else
              ++deactivations;
          });
      require(listener != nullptr);
      const auto dispatched = [&] { return listener->stats().dispatched; };
      require(deliver(name, L"LangbarRightClick|100|200|140|240", dispatched, 1));
      require(collected.wait_for(1));
      const auto anchors = collected.snapshot();
      require(anchors[0].center_x == 120 && anchors[0].top == 200);
      require(listener->stats().dispatched == 1);

      // Several sequential clients, proving accept/read/close rollover.
      for (uint64_t index = 0; index < 5; ++index)
        require(deliver(name, L"LangbarRightClick|0|0|40|40", dispatched,
                        2 + index));
      require(collected.wait_for(6));
      require(listener->stats().dispatched == 6);

      // The activation edges reach their own sink rather than being dropped.
      // Gating the toolbar on the mode view instead made it blink away on any
      // temporary focus suspension.
      // The sink runs before the dispatch counter advances, so once deliver
      // observes the count the callback has already been seen.
      require(deliver(name, L"IMEDeactivation", dispatched, 7));
      require(deactivations.load() == 1 && activations.load() == 0);
      require(deliver(name, L"IMEActivation", dispatched, 8));
      require(activations.load() == 1);
      require(listener->stats().unknown_verb == 0);

      // A genuinely unknown verb is still counted and dropped, and the
      // endpoint keeps working afterwards.
      require(deliver(name, L"SomethingElse|1",
                      [&] { return listener->stats().unknown_verb; }, 1));
      require(listener->stats().unknown_verb == 1);
      // TerminalDeactivation parses but is deliberately not acknowledged while
      // no deactivation path exists, so it counts as unhandled.
      require(deliver(name, L"TerminalDeactivation|7|42",
                      [&] { return listener->stats().unknown_verb; }, 2));
      require(deliver(name, L"LangbarRightClick|10|10|50|50", dispatched, 9));
      require(collected.wait_for(7));

      // A client that connects and never writes must not wedge the endpoint.
      HANDLE idle = CreateFileW(name.c_str(), GENERIC_READ | GENERIC_WRITE, 0,
                                nullptr, OPEN_EXISTING, 0, nullptr);
      require(idle != INVALID_HANDLE_VALUE);
      CloseHandle(idle);
      require(deliver(name, L"LangbarRightClick|20|20|60|60", dispatched, 8));
      require(collected.wait_for(8));

      // Stopping twice is safe, and no hard failure was latched.
      listener->stop();
      listener->stop();
      require(listener->failure() == ERROR_SUCCESS);
    }
    {
      // The name is claimed exclusively, so a second Server cannot silently
      // share the endpoint.
      const auto name = isolated_name(2);
      DWORD first_error = ERROR_SUCCESS;
      auto first = AuxListener::create(
          name, [](const TrayMenuAnchor &) {}, first_error);
      require(first != nullptr);
      DWORD second_error = ERROR_SUCCESS;
      auto second = AuxListener::create(
          name, [](const TrayMenuAnchor &) {}, second_error);
      require(second == nullptr);
      first->stop();
    }
    {
      // A sink may ask the listener to stop without deadlocking.
      const auto name = isolated_name(3);
      std::atomic<bool> seen{false};
      DWORD error = ERROR_SUCCESS;
      AuxListener *self = nullptr;
      auto listener = AuxListener::create(
          name,
          [&](const TrayMenuAnchor &) {
            seen.store(true);
            if (self)
              self->request_stop();
          },
          error);
      require(listener != nullptr);
      self = listener.get();
      require(deliver(name, L"LangbarRightClick|1|1|41|41",
                      [&] { return seen.load() ? 1u : 0u; }, 1));
      for (int spin = 0; spin < 250 && !seen.load(); ++spin)
        Sleep(20);
      require(seen.load());
      listener->stop();
    }
    std::cout << "Aux listener: langbar clicks dispatched, endpoint resilient\n";
    return 0;
  } catch (const std::exception &error) {
    std::cerr << error.what() << "\n";
    return 1;
  }
}
