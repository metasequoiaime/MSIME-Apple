#pragma once
#import <AppKit/AppKit.h>

// Use the same attributed-string measurement as drawing: fallback glyphs can
// exceed the primary font's ascent/descent even at the same point size.
inline CGFloat MSIMECandidateTextHeight(NSString *text, NSFont *font) {
    return ceil(MAX(font.ascender - font.descender + font.leading,
                    [text sizeWithAttributes:@{NSFontAttributeName:font}].height));
}
