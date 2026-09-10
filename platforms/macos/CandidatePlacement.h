#pragma once
#import <AppKit/AppKit.h>
#include <cmath>

inline bool MSIMEValidCaret(NSRect caret) {
    return std::isfinite(caret.origin.x) && std::isfinite(caret.origin.y) &&
           std::isfinite(caret.size.width) && std::isfinite(caret.size.height) && caret.size.height > 0;
}

inline NSPoint MSIMECandidateOrigin(NSRect caret, NSSize size, NSRect bounds) {
    const CGFloat x = MIN(MAX(NSMinX(caret), NSMinX(bounds)), MAX(NSMinX(bounds), NSMaxX(bounds) - size.width));
    CGFloat y = NSMinY(caret) - size.height - 4;
    if (y < NSMinY(bounds)) y = NSMaxY(caret) + 4;
    y = MIN(MAX(y, NSMinY(bounds)), MAX(NSMinY(bounds), NSMaxY(bounds) - size.height));
    return NSMakePoint(x, y);
}
