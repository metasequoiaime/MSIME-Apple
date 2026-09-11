// Adapted from MSIME-Apple b637828e15eafcb5e459edd270a962dd14517285.
#pragma once

#import <AppKit/AppKit.h>

#include "CandidateSkin.h"

@class MSIMEAppearancePreferences;
@interface MSIMECandidatePreviewView : NSView
@property(nonatomic, weak) MSIMEAppearancePreferences *preferences;
@property(nonatomic, weak) NSButton *themeButton;
- (void)updatePanelStyle:(NSInteger)panelStyle pageSize:(NSInteger)pageSize fontSize:(NSInteger)fontSize;
- (void)setPreviewSkinId:(NSString *)skinId;
- (NSString *)previewSkinId;
- (void)setShowsLayoutShowcase:(BOOL)showsLayoutShowcase;
- (void)toggleForcedTheme;
- (BOOL)previewUsesDark;
- (NSString *)forcedThemeButtonTitle;
- (void)reloadPreview;
- (msime::mac::ResolvedSkin)previewSkin;
- (NSColor *)previewCanvasFillColor;
- (NSColor *)previewPanelFillColor;
- (NSColor *)previewTextColor;
- (NSColor *)previewAccentColor;
- (CGFloat)previewContentHeight;
@end
