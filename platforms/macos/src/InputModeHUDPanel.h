#pragma once

#import <AppKit/AppKit.h>

NS_ASSUME_NONNULL_BEGIN

/// The Metasequoia forest green, and the ink that reads on top of it. Matching
/// platforms/ios/SharedUI/MetasequoiaTheme.swift, including its two shades: the light-mode green is
/// dark enough for white on top, the dark-mode one is light enough that white would fail on it.
FOUNDATION_EXPORT NSColor *MetasequoiaForestColor(void);
FOUNDATION_EXPORT NSColor *MetasequoiaOnForestColor(void);

/// 中 or 英 -- the state being switched to, as one character.
FOUNDATION_EXPORT NSString *MetasequoiaInputModeHUDText(BOOL englishInputMode);

/// Sits under the caret, close enough to be seen without looking away from what is being typed, and
/// clamped inside the screen. A client that reports no usable caret -- a terminal mid-redraw, a web
/// view that answers with zeroes -- gets the lower middle of the screen instead of a badge pinned to
/// the corner.
FOUNDATION_EXPORT NSRect MetasequoiaInputModeHUDFrame(NSRect caretRect, NSSize panelSize, NSRect visibleFrame);

FOUNDATION_EXPORT BOOL MetasequoiaIsUsableCaretRect(NSRect caretRect);

/// The badge that says which mode a switch landed in. It shows itself, waits, and fades out; it
/// never takes focus and never takes a click.
@interface MetasequoiaInputModeHUDPanel : NSPanel
+ (instancetype)sharedPanel;
- (void)showEnglishInputMode:(BOOL)englishInputMode nearCaretRect:(NSRect)caretRect;
/// Visible for tests: the text currently on the badge, or nil when it is hidden.
@property(nonatomic, copy, readonly, nullable) NSString *displayedText;
/// Whether the logo was found in the bundle. It is absent when the panel is built outside the app,
/// as a test binary does, and the badge then shows the character alone.
@property(nonatomic, readonly) BOOL showsLogo;
@end

NS_ASSUME_NONNULL_END
