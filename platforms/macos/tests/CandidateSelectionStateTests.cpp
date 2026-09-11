#include "../CandidateSelectionState.h"
#include <cassert>
int main() { using namespace metasequoia::mac; CandidateSelectionState state; state.begin_navigation(); state.update(3, "fixture"); assert(state.selected_index()==3); state.reset(); assert(!state.selected_index()); assert(CandidateSelectionState::candidates_per_page==9); }
