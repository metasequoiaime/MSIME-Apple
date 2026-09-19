#pragma once

#include <algorithm>

#include <CoreGraphics/CoreGraphics.h>

namespace msime::mac
{
// Keep a remote or packaged gloss from taking the space needed by the candidate itself.
// This is deliberately shared by measurement and drawing so a truncated gloss never
// reserves a different width from the one it receives at paint time.
constexpr CGFloat kCandidateGlossGap = 12.0;
constexpr CGFloat kCandidateGlossMaxWidth = 208.0;

constexpr CGFloat CandidateGlossReservedWidth(CGFloat measuredWidth)
{
    return 2.0 * kCandidateGlossGap +
           std::min<CGFloat>(std::max<CGFloat>(measuredWidth, 0.0), kCandidateGlossMaxWidth);
}

constexpr CGFloat CandidateGlossDrawnWidth(CGFloat measuredWidth, CGFloat availableWidth)
{
    return std::max<CGFloat>(
        std::min<CGFloat>({std::max<CGFloat>(measuredWidth, 0.0), kCandidateGlossMaxWidth,
                            std::max<CGFloat>(availableWidth, 0.0)}),
        0.0);
}
} // namespace msime::mac
