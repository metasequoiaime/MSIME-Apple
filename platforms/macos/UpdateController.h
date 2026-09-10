#pragma once
#import <AppKit/AppKit.h>
NS_ASSUME_NONNULL_BEGIN
@interface MSIMEUpdateController : NSObject
+ (instancetype)sharedController;
- (BOOL)canCheckForUpdates;
- (void)checkForUpdates:(nullable id)sender;
@end
NS_ASSUME_NONNULL_END
