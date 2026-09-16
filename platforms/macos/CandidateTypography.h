#pragma once

#import <AppKit/AppKit.h>

// Windows candidate rendering uses a label font at 80% of the candidate font.
// Keep the scale in one place while letting AppKit retain the selected font's
// family and variation axes.
static const CGFloat MSIMECandidateNumberScale = 0.8;
static const CGFloat MSIMECandidateNumberGap = 1.5;

static inline NSFont *MSIMECandidateNumberFont(NSFont *font)
{
    if (![font isKindOfClass:NSFont.class])
    {
        return [NSFont systemFontOfSize:14.4];
    }
    return [NSFont fontWithDescriptor:font.fontDescriptor size:font.pointSize * MSIMECandidateNumberScale] ?:
        [NSFont systemFontOfSize:font.pointSize * MSIMECandidateNumberScale];
}
