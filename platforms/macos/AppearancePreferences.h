#pragma once
#import <AppKit/AppKit.h>
#include "CandidateSkin.h"

FOUNDATION_EXPORT NSNotificationName const MSIMEAppearanceDidChangeNotification;

// macOS-only presentation settings; never change Engine composition/configuration.
@interface MSIMEAppearancePreferences : NSWindowController
+ (instancetype)sharedPreferences;
- (instancetype)initWithDefaults:(NSUserDefaults *)defaults;
- (instancetype)initWithDefaults:(NSUserDefaults *)defaults skinsRoot:(NSURL *)root;
- (void)reloadSkins;
- (msime::mac::ResolvedSkin)resolvedSkinForDark:(BOOL)dark;
@property(nonatomic, readonly) NSImage *decorationImage;
@property(nonatomic, readonly) NSURL *skinsRoot;
@property(nonatomic) BOOL vertical;
@property(nonatomic) NSUInteger fontSize;
@property(nonatomic) NSUInteger pageSize;
@property(nonatomic, copy) NSString *skinID;
// 0: -/= (default), 1: [/], 2: Page Up/Page Down only.
@property(nonatomic) NSInteger pageShortcut;
@end
