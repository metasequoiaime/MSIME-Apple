#pragma once
#import <AppKit/AppKit.h>
@interface MSIMECloudClipboardWindowController : NSWindowController
+ (instancetype)sharedController;
- (void)showWithToken:(NSString *)token;
@end
