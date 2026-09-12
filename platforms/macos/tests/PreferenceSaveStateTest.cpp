#include "../PreferenceSaveState.h"
#include <cassert>

int main() {
    MSIMEPreferenceSaveState state;
    assert(state.request());
    for (int change = 0; change < 20; ++change) assert(!state.request());
    assert(state.finish());
    assert(state.request());
    // No additional event: the follow-up settles without an infinite retry.
    assert(!state.finish());
    assert(!state.saving && !state.pending);
    // A new event during the follow-up needs another save, even after failure.
    assert(state.request());
    assert(!state.request());
    assert(state.finish());
    assert(state.request());
    assert(!state.request());
    assert(state.finish());
    assert(state.request());
    assert(!state.finish());
}
