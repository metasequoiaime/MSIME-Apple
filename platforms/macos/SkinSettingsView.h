// Adapted from MSIME-Apple b637828e15eafcb5e459edd270a962dd14517285.
#pragma once

#import <AppKit/AppKit.h>

@class MSIMEAppearancePreferences;
@interface MSIMESkinSettingsView : NSView
- (instancetype)initWithFrame:(NSRect)frame preferences:(MSIMEAppearancePreferences *)preferences;
@property(nonatomic, copy) BOOL (^directoryOpener)(NSURL *);
- (void)reload;
- (void)refreshSelection;
@end
