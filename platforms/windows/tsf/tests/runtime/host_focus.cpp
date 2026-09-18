#include "../HostFocusState.h"
#include <cstdlib>
#include <vector>
int main() {
    msime::tsf::HostFocusState state;
    std::vector<bool> calls;
    auto send = [&](bool focused) { calls.push_back(focused); return true; };
    if (!state.update(true, true, send)) return EXIT_FAILURE;
    for (int i = 0; i < 10; ++i)
        if (!state.update(true, false, send)) return EXIT_FAILURE;
    if (calls != std::vector<bool>{true}) return EXIT_FAILURE;
    // Transient loss is deferred by TSF, so returning to the same context
    // must not call runtime focus(true), which would cancel its composition.
    state.update(true, false, send);
    state.update(true, true, send);
    state.update(false, false, send);
    state.update(false, false, send);
    state.update(true, true, send);
    if (calls != std::vector<bool>{true, true, false, true}) return EXIT_FAILURE;
    auto fail = [&](bool focused) { calls.push_back(focused); return false; };
    if (state.update(false, false, fail)) return EXIT_FAILURE;
    if (!state.update(false, false, send) || calls.size() != 6) return EXIT_FAILURE;
    if (!state.update(true, true, send)) return EXIT_FAILURE;
    if (state.update(true, true, fail)) return EXIT_FAILURE;
    const auto before = calls.size();
    if (!state.update(true, false, send) || calls.size() != before + 1) return EXIT_FAILURE;
    return EXIT_SUCCESS;
}
