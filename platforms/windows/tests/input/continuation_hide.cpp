#include "ContinuationHide.h"

#include <iostream>
#include <stdexcept>
#include <string>

using namespace msime::windows;
namespace {
void require(bool value, int line) {
  if (!value)
    throw std::runtime_error("continuation hide failed at line " + std::to_string(line));
}
#define REQUIRE(value) require((value), __LINE__)
} // namespace

int main() {
  try {
    const ContinuationHide::Clock::time_point start{std::chrono::seconds(100)};
    ContinuationHide mark;
    // Nothing armed spares nothing.
    REQUIRE(!mark.consume(start));

    // A hide inside the lifetime is spared, once.
    mark.arm(start);
    REQUIRE(mark.consume(start + std::chrono::milliseconds(999)));
    REQUIRE(!mark.consume(start + std::chrono::milliseconds(999)));
    mark.arm(start);
    REQUIRE(mark.consume(start + ContinuationHide::lifetime));

    // A mark the TIP never answered expires: a hide more than a second later is a real one, and it spends the mark.
    mark.arm(start);
    REQUIRE(!mark.consume(start + std::chrono::milliseconds(1001)));
    REQUIRE(!mark.consume(start + std::chrono::milliseconds(1002)));

    // Clearing drops the mark, and re-arming restarts the window.
    mark.arm(start);
    mark.clear();
    REQUIRE(!mark.consume(start));
    mark.arm(start);
    mark.arm(start + std::chrono::milliseconds(900));
    REQUIRE(mark.consume(start + std::chrono::milliseconds(1800)));

    // A clock that reads earlier than the arm time is not inside the window.
    mark.arm(start);
    REQUIRE(!mark.consume(start - std::chrono::milliseconds(1)));
  } catch (const std::exception &error) {
    std::cerr << error.what() << '\n';
    return 1;
  }
  return 0;
}
