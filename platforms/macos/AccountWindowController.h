#pragma once
#import <AppKit/AppKit.h>
@interface MSIMEAccountWindowController : NSWindowController
+ (instancetype)sharedController;
- (void)showForAccountID:(NSString *)accountID;
@end
