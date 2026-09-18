#pragma once

#import <AppKit/AppKit.h>

FOUNDATION_EXPORT NSArray<NSArray<NSDictionary<NSString *, NSString *> *> *> *MSIMEShuangpinKeymapRows(
    NSString *profileName);

FOUNDATION_EXPORT NSString *MSIMEShuangpinZeroInitialText(NSString *profileName);

FOUNDATION_EXPORT BOOL MSIMEShouldShowShuangpinKeymap(BOOL isShuangpin, BOOL enabled, BOOL hasComposition);

// Raw Engine input, independent of the selected preedit display format.
FOUNDATION_EXPORT NSString *MSIMEShuangpinKeymapEditingText(NSDictionary *view);
FOUNDATION_EXPORT NSString *MSIMEShuangpinKeymapHighlightedKey(NSDictionary *view);

FOUNDATION_EXPORT NSRect MSIMEShuangpinKeymapPanelFrame(NSRect caretRect, NSSize panelSize,
                                                              CGFloat candidateClearance, NSRect visibleFrame);

@interface MSIMEShuangpinKeymapPanel : NSPanel
- (void)setProfileName:(NSString *)profileName;
- (void)updateHighlightedKey:(NSString *)key;
- (void)showNearCaretRect:(NSRect)caretRect candidateClearance:(CGFloat)candidateClearance;
@end
