#pragma once

#import <AppKit/AppKit.h>

NS_ASSUME_NONNULL_BEGIN

FOUNDATION_EXPORT NSColor *MSIMEInputModeHUDForestColor(void);
FOUNDATION_EXPORT NSColor *MSIMEInputModeHUDOnForestColor(void);
FOUNDATION_EXPORT NSString *MSIMEInputModeHUDText(BOOL englishInputMode);
FOUNDATION_EXPORT BOOL MSIMEInputModeHUDUsableCaretRect(NSRect caretRect);
FOUNDATION_EXPORT NSRect MSIMEInputModeHUDFrame(NSRect caretRect, NSSize panelSize, NSRect visibleFrame);

/// A short, non-activating badge shown after the user switches Chinese/English input.
@interface MSIMEInputModeHUDPanel : NSPanel
+ (instancetype)sharedPanel;
- (void)showEnglishInputMode:(BOOL)englishInputMode nearCaretRect:(NSRect)caretRect;
@property(nonatomic, copy, readonly, nullable) NSString *displayedText;
@property(nonatomic, readonly) BOOL showsLogo;
@end

NS_ASSUME_NONNULL_END
