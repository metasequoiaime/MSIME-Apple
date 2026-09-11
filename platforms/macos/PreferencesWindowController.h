#pragma once
#import <AppKit/AppKit.h>

FOUNDATION_EXPORT NSNotificationName const MSIMEStandalonePreferencesDidCloseNotification;

/// Native preferences entry point; pages are added incrementally to this controller.
@interface MSIMEPreferencesWindowController : NSWindowController <NSWindowDelegate>
+ (NSInteger)storedScheme;
+ (NSString *)storedShuangpinSchema;
+ (instancetype)sharedController;
- (void)showAndActivate;
- (void)showAndActivateForStandaloneLaunch;
@end
