#pragma once
#import <AppKit/AppKit.h>
#include <cmath>

inline bool MSIMEValidCaret(NSRect caret) {
    return std::isfinite(caret.origin.x) && std::isfinite(caret.origin.y) &&
           std::isfinite(caret.size.width) && std::isfinite(caret.size.height) && caret.size.height > 0;
}

// The tallest vertical candidate panel shown since the panel last became visible, matching Windows' g_max_vertical_container_height_dip. A panel that was hidden in between starts over, as Windows' ResetCandidatePlacementMemory does when its candidate window hides; a horizontal panel carries the memory without adding to it.
inline CGFloat MSIMETallestCandidateHeight(CGFloat remembered, CGFloat current, bool vertical, bool panelWasVisible) {
    const CGFloat base = panelWasVisible ? MAX(remembered, 0.0) : 0.0;
    return vertical ? MAX(base, current) : base;
}

// Decides the side of the caret with the taller of the current height and flipDecisionHeight, but places the panel with its current height. A vertical list that grows as candidates arrive therefore does not jump from below the caret to above it, and a shorter later page that stays above the caret sits against the line instead of leaving the tallest page's gap.
inline NSPoint MSIMECandidateOrigin(NSRect caret, NSSize size, NSRect bounds, CGFloat flipDecisionHeight) {
    const CGFloat x = MIN(MAX(NSMinX(caret), NSMinX(bounds)), MAX(NSMinX(bounds), NSMaxX(bounds) - size.width));
    const CGFloat decisionHeight = MAX(size.height, flipDecisionHeight);
    CGFloat y = NSMinY(caret) - size.height - 4;
    if (NSMinY(caret) - decisionHeight - 4 < NSMinY(bounds)) y = NSMaxY(caret) + 4;
    y = MIN(MAX(y, NSMinY(bounds)), MAX(NSMinY(bounds), NSMaxY(bounds) - size.height));
    return NSMakePoint(x, y);
}

inline NSPoint MSIMECandidateOrigin(NSRect caret, NSSize size, NSRect bounds) {
    return MSIMECandidateOrigin(caret, size, bounds, size.height);
}
