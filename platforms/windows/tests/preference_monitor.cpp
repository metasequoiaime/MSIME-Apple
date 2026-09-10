#include "PreferenceMonitor.h"
#include <filesystem>
#include <fstream>
#include <stdexcept>

namespace {
void require(bool value, const char *message) {
  if (!value)
    throw std::runtime_error(message);
}
template <class F> void await(F ready) {
  const auto deadline =
      std::chrono::steady_clock::now() + std::chrono::seconds(5);
  while (!ready()) {
    require(std::chrono::steady_clock::now() < deadline,
            "Preference monitor timed out");
    std::this_thread::sleep_for(std::chrono::milliseconds(5));
  }
}
} // namespace
void preference_monitor_tests(const std::string &options,
                              const std::string &directory) {
  using namespace msime::windows;
  auto write = [&](const std::string &value) {
    std::ofstream output(std::filesystem::u8path(directory) /
                         "preferences.json");
    output << value;
    output.close();
    require(static_cast<bool>(output), "Synthetic settings write failed");
  };
  auto document = nlohmann::json{
      {"format_version", 1},
      {"revision", 1},
      {"preferences", nlohmann::json::parse(options).at("preferences")}};
  write(document.dump());
  const auto older = PreferenceSnapshot::load(directory);
  document["revision"] = 2;
  document["preferences"]["navigation"] = {{"minus_equal", false}, {"comma_period", false},
    {"brackets", true}, {"tab", false}, {"page_up_down", false}, {"arrows", false}};
  document["preferences"]["word_character"] = {{"enabled", true}, {"keys", "minus_equal"}};
  write(document.dump());
  FocusGate gate;
  InputQueue input(gate, 1, 1, options);
  std::promise<void> entered, release;
  auto released = release.get_future().share();
  auto blocker = input.submit([&](InputState &) {
    entered.set_value();
    released.wait();
  });
  entered.get_future().wait();
  // Ensure the test never strands its synthetic blocking task on an assertion.
  struct Release {
    std::promise<void> &value;
    ~Release() {
      try {
        value.set_value();
      } catch (...) {
      }
    }
  } guard{release};
  auto filler = input.submit([](InputState &) {});
  require(filler.has_value(), "Synthetic queue fill failed");
  PreferenceMonitor monitor(input, directory, std::chrono::milliseconds(10));
  // Stop monitor before Release unwinds: its pending tasks capture only values,
  // and stopping never waits for an input publication receipt.
  await([&] { return monitor.status() == PreferenceMonitorStatus::QueueFull; });
  release.set_value();
  require(blocker->get() == InputTaskStatus::Completed &&
              filler->get() == InputTaskStatus::Completed,
          "Synthetic queue unblock failed");
  await([&] { return monitor.status() == PreferenceMonitorStatus::Current; });
  const auto completed = input.stats().completed;
  std::this_thread::sleep_for(std::chrono::milliseconds(60));
  require(input.stats().completed == completed,
          "Unchanged settings were repeatedly published");
  auto check = input.submit([&](InputState &state) {
    bool rejected = false;
    try {
      state.publish_preferences(older);
    } catch (const std::invalid_argument &) {
      rejected = true;
    }
    require(rejected, "Monitor did not publish newest settings");
    const auto navigation = state.navigation_bindings();
    require(state.word_character_binding() == WordCharacterBinding::MinusEqual,
            "Live word binding was not published or was reverted by stale settings");
    require(!navigation.minus_equal && !navigation.comma_period && navigation.brackets &&
            !navigation.tab && !navigation.page_up_down && !navigation.arrows,
            "Live navigation settings were not published or were reverted by stale settings");
    bool join_rejected = false;
    try {
      monitor.stop();
    } catch (const std::logic_error &) {
      join_rejected = true;
    }
    require(join_rejected, "Input thread joined dependent monitor");
  });
  require(check && check->get() == InputTaskStatus::Completed,
          "Monitor publication check failed");
  write("broken");
  await(
      [&] { return monitor.status() == PreferenceMonitorStatus::ReadFailed; });
  require(!monitor.failed(), "Read failure killed settings monitoring");
  write(older.serialized());
  std::this_thread::sleep_for(std::chrono::milliseconds(40));
  require(monitor.status() == PreferenceMonitorStatus::ReadFailed,
          "Stale file replaced settings");
  document["revision"] = 3;
  write(document.dump());
  await([&] { return monitor.status() == PreferenceMonitorStatus::Current; });
  input.stop();
  await([&] { return monitor.failed(); });
  monitor.stop();
  monitor.stop();
  InputQueue idle(gate, 1, 1, options);
  PreferenceMonitor stopping(idle, directory, std::chrono::seconds(60));
  const auto start = std::chrono::steady_clock::now();
  stopping.request_stop();
  stopping.stop();
  require(stopping.status() == PreferenceMonitorStatus::Stopped &&
              std::chrono::steady_clock::now() - start <
                  std::chrono::seconds(2),
          "Monitor stop waited for poll interval");
  idle.stop();
}
