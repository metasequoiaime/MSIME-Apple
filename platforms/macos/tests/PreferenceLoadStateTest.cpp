#include "../PreferenceLoadState.h"
#include <cassert>

int main() {
    MSIMEPreferenceLoadState state;
    state.reset();
    const auto first = state.generation;
    assert(state.begin());
    assert(!state.begin());
    state.reset(); // Focus leaves while disk read is running.
    assert(!state.finish(first));
    state.reset(); // Same input controller becomes active again.
    const auto second = state.generation;
    assert(state.begin());
    assert(!state.finish(first));
    assert(state.loading);
    assert(state.finish(second));
    assert(!state.loading);
    assert(!state.finish(second));
    assert(state.begin()); // Failed read can be retried on the next timer tick.
    assert(state.finish(second));
}
