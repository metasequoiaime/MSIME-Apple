#include <chrono>
#include <cstdlib>
#include <thread>
#include <string>

// Process-control fixture only: never links Engine or opens IME pipes.
int main(int argc, char **) {
  const char *mode = std::getenv("MSIME_RUNNER_PROBE_MODE");
  if (mode && std::string(mode) == "timeout")
    std::this_thread::sleep_for(std::chrono::seconds(10));
  if (mode && std::string(mode) == "fail")
    return 7;
  return argc <= 2 ? 0 : 8;
}
