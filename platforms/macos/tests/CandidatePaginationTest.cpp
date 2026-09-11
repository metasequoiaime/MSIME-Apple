#include "../InputControllerKeyRouting.h"
#include <stdexcept>

static void require(bool value, const char *message) { if (!value) throw std::runtime_error(message); }

int main() {
    using namespace metasequoia::mac;
    require(CandidatePageStart(0, 23, 9) == 0, "first page start");
    require(CandidatePageStart(8, 23, 9) == 0, "selected item stays on first page");
    require(CandidatePageStart(9, 23, 9) == 9, "second page start");
    require(CandidatePageStart(99, 23, 9) == 18, "out of range selection clamps to last page");
    require(CandidatePageEnd(9, 23, 9) == 17, "second page end");
    require(CandidatePageEnd(18, 23, 9) == 22, "short final page end");
    require(CandidatePageStart(0, 0, 9) == 0 && CandidatePageEnd(0, 0, 9) == 0, "empty page");
    require(ClassifyControllerKey(kVK_PageUp, true) == ControllerKeyAction::MoveCandidatePageUp, "page up key");
    require(ClassifyControllerKey(kVK_PageDown, true) == ControllerKeyAction::MoveCandidatePageDown, "page down key");
    require(ClassifyControllerKey(0, true, CandidatePageShortcut::Brackets, '[', false) == ControllerKeyAction::MoveCandidatePageUp, "bracket page up");
    require(ClassifyControllerKey(0, true, CandidatePageShortcut::Brackets, ']', false) == ControllerKeyAction::MoveCandidatePageDown, "bracket page down");
    require(ClassifyControllerKey(0, true, CandidatePageShortcut::Brackets, '[', true) == ControllerKeyAction::Character, "modified bracket passthrough");
}
