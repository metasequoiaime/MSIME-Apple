#include "ModeAuthority.h"
#include <iostream>
#include <stdexcept>
#include <string>

using namespace msime::windows;
namespace {
[[noreturn]] void require_failed(int line) {
  throw std::runtime_error("Mode authority test failed at line " +
                           std::to_string(line));
}
#define require(value)                                                         \
  do {                                                                         \
    if (!(value))                                                              \
      require_failed(__LINE__);                                                \
  } while (false)
} // namespace
int main() {
  try {
    // Seeding: the first observation adopts the client's mode rather than
    // fighting it with an authority that was never set.
    ModeAuthorityState state;
    state.seeded = false;
    auto step = mode_authority_step(state, true, true, 1, false);
    require(!step.push);
    require(step.next.seeded && !step.next.chinese && step.next.session == 1);
    state = step.next;

    // Same client changing its own mode: the user meant it, so it becomes the
    // authority and will travel to the next application.
    step = mode_authority_step(state, true, true, 1, true);
    require(!step.push);
    require(step.next.chinese);
    state = step.next;

    // A different client takes focus reporting the other mode: the authority
    // wins and is pushed back to it.
    step = mode_authority_step(state, true, true, 2, false);
    require(step.push && step.push_chinese);
    require(step.next.session == 2);
    // The authority itself does not change on a push.
    require(step.next.chinese);

    // A client that already agrees is left alone: pushing would be a pointless
    // round trip through the pipe on every focus change.
    step = mode_authority_step(step.next, true, true, 3, true);
    require(!step.push);
    require(step.next.session == 3);

    // Per-application scope never pushes, whatever the mismatch. That is
    // exactly what the 按应用记忆 option promises.
    ModeAuthorityState per_app;
    per_app.seeded = true;
    per_app.chinese = true;
    per_app.session = 1;
    auto app_step = mode_authority_step(per_app, false, true, 2, false);
    require(!app_step.push);
    require(app_step.next.session == 2 && !app_step.next.chinese);

    // Nothing focused: the authority survives and nothing is pushed, so a
    // moment with no client does not reset the user's mode.
    auto idle = mode_authority_step(state, true, false, 0, false);
    require(!idle.push);
    require(idle.next.chinese == state.chinese);
    require(idle.next.session == state.session);
    require(idle.next.seeded);

    std::cout << "Mode authority: one CN/EN state follows the user\n";
  } catch (const std::exception &failure) {
    std::cerr << failure.what() << '\n';
    return 1;
  } catch (...) {
    std::cerr << "Mode authority test failed with an unknown error\n";
    return 1;
  }
}
