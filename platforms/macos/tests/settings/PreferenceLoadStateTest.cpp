#include "../../src/settings/PreferenceLoadState.h"
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

    // Which reads are worth applying at all. The controller polls the preferences document once a
    // second, so most reads find exactly what was applied a second ago; applying that again walks
    // every preference and goes back into the Engine for nothing.
    MSIMEPreferenceLoadState revisions;
    // Nothing applied yet: every revision is new.
    assert(revisions.needsApply(7));
    revisions.applied(7);
    assert(!revisions.needsApply(7));
    assert(revisions.needsApply(8));
    // A document with no revision - one written before the field existed - says nothing about what
    // it contains, so it is always applied.
    assert(revisions.needsApply(0));
    // A local edit invalidates what was applied: the settings window writes into the same object
    // this session holds, and the document can come back at a revision already seen.
    revisions.applied(7);
    revisions.reset();
    assert(revisions.needsApply(7));
}
