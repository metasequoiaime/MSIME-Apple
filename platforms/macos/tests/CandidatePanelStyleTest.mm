#import "../CandidatePanelStyle.h"
#include <cassert>
int main(){using namespace metasequoia::mac; assert(NormalizeCandidatePanelStyle(0)==CandidatePanelStyle::Horizontal); assert(NormalizeCandidatePanelStyle(9)==CandidatePanelStyle::Horizontal); assert(NormalizeCandidatePanelStyle(1)==CandidatePanelStyle::Vertical); assert(IsPrimaryCandidateDirection(kVK_LeftArrow,kIMKSingleRowSteppingCandidatePanel)); assert(!IsPrimaryCandidateDirection(kVK_LeftArrow,kIMKSingleColumnScrollingCandidatePanel));}
