#pragma once

#import <AppKit/AppKit.h>

FOUNDATION_EXPORT NSArray<NSArray<NSDictionary<NSString *, NSString *> *> *> *MetasequoiaShuangpinKeymapRows(
    NSString *profileName);

FOUNDATION_EXPORT NSString *MetasequoiaShuangpinZeroInitialText(NSString *profileName);

FOUNDATION_EXPORT BOOL MetasequoiaShouldShowShuangpinKeymap(BOOL isShuangpin, BOOL enabled, BOOL hasComposition);

FOUNDATION_EXPORT NSRect MetasequoiaShuangpinKeymapPanelFrame(NSRect caretRect, NSSize panelSize,
                                                              CGFloat candidateClearance, NSRect visibleFrame);

@interface MetasequoiaShuangpinKeymapPanel : NSPanel
- (void)setProfileName:(NSString *)profileName;
- (void)updateHighlightedKey:(NSString *)key;
- (void)showNearCaretRect:(NSRect)caretRect candidateClearance:(CGFloat)candidateClearance;
@end
