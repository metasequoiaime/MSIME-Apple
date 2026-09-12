#pragma once

#include <algorithm>

#include <CoreGraphics/CoreGraphics.h>

namespace metasequoia::mac
{
// A vertical candidate draws its English gloss right-aligned, with this much space on either side of it.
constexpr CGFloat kCandidateGlossGap = 12.0;

// The widest a gloss is ever drawn at. Anything longer is truncated rather than allowed to take the width the
// candidate itself needs: english.db ships senses that measure close to 300pt at the default candidate size, and
// 华中科技大学 -> "Huazhong University of Science and Technology" is one of them.
constexpr CGFloat kCandidateGlossMaxWidth = 208.0;

// Width a vertical candidate grows by to make room for a gloss that measures `measuredWidth`, gaps included.
constexpr CGFloat CandidateGlossReservedWidth(CGFloat measuredWidth)
{
    return 2.0 * kCandidateGlossGap + std::min<CGFloat>(std::max<CGFloat>(measuredWidth, 0.0), kCandidateGlossMaxWidth);
}

// Width the gloss is drawn at inside a candidate that has `availableWidth` left over for it. Layout reserves
// CandidateGlossReservedWidth for the same gloss, so drawing never claims more room than was set aside.
constexpr CGFloat CandidateGlossDrawnWidth(CGFloat measuredWidth, CGFloat availableWidth)
{
    return std::max<CGFloat>(std::min<CGFloat>({measuredWidth, kCandidateGlossMaxWidth, availableWidth}), 0.0);
}
} // namespace metasequoia::mac
