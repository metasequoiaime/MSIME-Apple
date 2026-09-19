#include "CandidateGlossLayout.h"

#include <cassert>

int main()
{
    using msime::mac::CandidateGlossDrawnWidth;
    using msime::mac::CandidateGlossReservedWidth;
    using msime::mac::kCandidateGlossGap;
    using msime::mac::kCandidateGlossMaxWidth;

    assert(CandidateGlossReservedWidth(-20.0) == 2.0 * kCandidateGlossGap);
    assert(CandidateGlossReservedWidth(1000.0) == 2.0 * kCandidateGlossGap + kCandidateGlossMaxWidth);
    assert(CandidateGlossDrawnWidth(-1.0, 100.0) == 0.0);
    assert(CandidateGlossDrawnWidth(300.0, 100.0) == 100.0);
    assert(CandidateGlossDrawnWidth(300.0, 500.0) == kCandidateGlossMaxWidth);
    assert(CandidateGlossDrawnWidth(80.0, -5.0) == 0.0);
    return 0;
}
