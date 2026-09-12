#pragma once

#import <AppKit/AppKit.h>

@class MSIMEAppearancePreferences;
@interface MetasequoiaSkinSettingsView : NSView
@property(nonatomic, weak, readonly) MSIMEAppearancePreferences *preferences;
@property(nonatomic, copy) BOOL (^directoryOpener)(NSURL *url);
- (instancetype)initWithFrame:(NSRect)frameRect preferences:(MSIMEAppearancePreferences *)preferences;
- (void)reload;
- (void)refreshSelection;
@end
