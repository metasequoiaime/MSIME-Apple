#pragma once

#import <AppKit/AppKit.h>

FOUNDATION_EXPORT NSArray<NSArray<NSDictionary<NSString *, NSString *> *> *> *MetasequoiaXiaoheKeymapRows(void);

// The zero-initial syllables map to a two-letter code rather than to a single key, so they cannot be shown on the key
// caps and need their own line.
FOUNDATION_EXPORT NSString *MetasequoiaXiaoheZeroInitialText(void);
FOUNDATION_EXPORT NSArray<NSArray<NSDictionary<NSString *, NSString *> *> *> *MetasequoiaShuangpinKeymapRows(NSString *profile);
FOUNDATION_EXPORT NSString *MetasequoiaShuangpinZeroInitialText(NSString *profile);

FOUNDATION_EXPORT BOOL MetasequoiaShouldShowShuangpinKeymap(BOOL isShuangpin, BOOL enabled, BOOL hasComposition);

FOUNDATION_EXPORT NSRect MetasequoiaShuangpinKeymapPanelFrame(NSRect caretRect, NSSize panelSize,
                                                              CGFloat candidateClearance, NSRect visibleFrame);

@interface MetasequoiaShuangpinKeymapPanel : NSPanel
- (void)setProfileName:(NSString *)profile;
- (void)updateHighlightedKey:(NSString *)key;
- (void)showNearCaretRect:(NSRect)caretRect candidateClearance:(CGFloat)candidateClearance;
@end
