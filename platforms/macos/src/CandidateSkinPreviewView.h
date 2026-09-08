#pragma once

#import <AppKit/AppKit.h>

#include "CandidateSkin.h"

@interface MetasequoiaCandidatePreviewView : NSView
- (void)updatePanelStyle:(NSInteger)panelStyle pageSize:(NSInteger)pageSize fontSize:(NSInteger)fontSize;
- (void)setPreviewSkinId:(NSString *)skinId;
- (NSString *)previewSkinId;
- (void)setShowsLayoutShowcase:(BOOL)showsLayoutShowcase;
- (void)toggleForcedTheme;
- (BOOL)previewUsesDark;
- (NSString *)forcedThemeButtonTitle;
- (void)reloadPreview;
- (metasequoia::mac::ResolvedSkin)previewSkin;
- (NSColor *)previewCanvasFillColor;
- (NSColor *)previewPanelFillColor;
- (NSColor *)previewTextColor;
- (NSColor *)previewAccentColor;
- (CGFloat)previewContentHeight;
@end
