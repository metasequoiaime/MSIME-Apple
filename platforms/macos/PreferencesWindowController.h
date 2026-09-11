#pragma once
#import <AppKit/AppKit.h>

/// Native preferences entry point; pages are added incrementally to this controller.
@interface MSIMEPreferencesWindowController : NSWindowController
+ (instancetype)sharedController;
- (void)showAndActivate;
@end
