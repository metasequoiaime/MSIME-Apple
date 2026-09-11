#pragma once

#import <AppKit/AppKit.h>

/// Stable native preferences entry point; pages are added incrementally.
@interface MSIMEPreferencesWindowController : NSWindowController
+ (instancetype)sharedController;
- (void)showAndActivate;
@end
