#pragma once
#import <AppKit/AppKit.h>
@interface MSIMEUpdateController : NSObject
+ (instancetype)sharedController;
- (BOOL)canCheckForUpdates;
- (void)checkForUpdates:(nullable id)sender;
@end
