#pragma once
#import <AppKit/AppKit.h>
FOUNDATION_EXPORT NSNotificationName const MSIMEVoiceSettingsDidChangeNotification;
@interface MSIMEVoiceSettings : NSWindowController
+ (instancetype)sharedSettings;
- (void)showAndActivate;
@end
