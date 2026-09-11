#pragma once
#import <AppKit/AppKit.h>
@interface MSIMEVoiceSettings : NSWindowController
+ (instancetype)sharedSettings;
- (void)showAndActivate;
@end
