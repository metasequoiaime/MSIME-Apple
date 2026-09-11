#include "../CandidateSelectionState.h"
#include <cassert>

int main()
{
    metasequoia::mac::CandidateSelectionState state;
    assert(!state.selected_index().has_value());
    state.update(2, "ignored-before-navigation");
    assert(!state.selected_index().has_value());
    state.begin_navigation();
    state.update(2, "candidate");
    assert(state.selected_index().has_value() && *state.selected_index() == 2);
    state.reset();
    assert(!state.selected_index().has_value());
    state.begin_navigation();
    state.update(8, "last-candidate");
    assert(state.selected_index() == 8);
    return 0;
}
