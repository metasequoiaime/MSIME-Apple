#import "../InputControllerKeyRouting.h"
#include <cassert>
int main(){using namespace metasequoia::mac; assert(ClassifyControllerKey(kVK_LeftArrow,true)==ControllerKeyAction::MoveCandidateLeft); assert(ClassifyControllerKey(kVK_PageDown,true)==ControllerKeyAction::MoveCandidatePageDown); assert(ClassifyControllerKey(kVK_Space,false)==ControllerKeyAction::CommitCandidate); assert(ClassifyControllerKey(kVK_Delete,false)==ControllerKeyAction::Backspace); assert(ClassifyControllerKey(kVK_ANSI_KeypadEnter,false)==ControllerKeyAction::CommitRaw); assert(CandidatePageStart(8,10,5)==5);}
