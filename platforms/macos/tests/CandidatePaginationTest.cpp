#include "../InputControllerKeyRouting.h"
#include "../CandidateWheelRouting.h"
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
    require(msime::mac::IsJapaneseMinusEqualInput(3, false, '-') && msime::mac::IsJapaneseMinusEqualInput(3, false, '='), "direct Japanese scheme punctuation");
    require(msime::mac::IsJapaneseMinusEqualInput(0, true, '-') && msime::mac::IsJapaneseMinusEqualInput(0, true, '='), "temporary Japanese punctuation");
    require(!msime::mac::IsJapaneseMinusEqualInput(0, false, '-') && !msime::mac::IsJapaneseMinusEqualInput(3, false, '['), "non-Japanese punctuation remains navigation");
    require(msime::mac::PhysicalCandidateDigitSlot(18) == 0 && msime::mac::PhysicalCandidateDigitSlot(25) == 8, "physical number row mapping");
    require(msime::mac::PhysicalCandidateDigitSlot(83) == 0 && msime::mac::PhysicalCandidateDigitSlot(92) == 8, "keypad digit mapping");
    require(msime::mac::PhysicalCandidateDigitSlot(82) == -1 && msime::mac::PhysicalCandidateDigitSlot(29) == -1 && msime::mac::PhysicalCandidateDigitSlot(0) == -1, "non-candidate key codes rejected");
    require(msime::mac::IsKeypadDecimal(65) && !msime::mac::IsKeypadDecimal(0), "keypad decimal mapping");
    using msime::mac::CandidateWheelAction;
    require(msime::mac::CandidateWheelPageAction(1, true, true, false) == CandidateWheelAction::PreviousPage, "wheel previous page");
    require(msime::mac::CandidateWheelPageAction(-1, true, false, true) == CandidateWheelAction::NextPage, "wheel next page");
    require(msime::mac::CandidateWheelPageAction(-1, false, true, true) == CandidateWheelAction::None, "disabled wheel passthrough");
    require(msime::mac::CandidateWheelPageAction(1, true, false, true) == CandidateWheelAction::None, "wheel respects first page");
    require(msime::mac::CandidateWheelPageAction(-1, true, true, false) == CandidateWheelAction::None, "wheel respects last page");
}
