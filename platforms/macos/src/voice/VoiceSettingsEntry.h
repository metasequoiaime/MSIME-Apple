#pragma once
#import <Foundation/Foundation.h>

@protocol MSIMEVoiceSettingsWindowRouting
+ (id)sharedController;
- (void)showAndActivate;
@end

// Both the input menu and the native appearance fallback must open the same
// provider editor. Keep the dynamic lookup because several isolated settings
// tests compile AppearancePreferences without linking the voice window.
static inline BOOL MSIMEShowVoiceSettingsWindow(Class windowClass) {
    if (!windowClass || ![windowClass respondsToSelector:@selector(sharedController)]) return NO;
    id controller = [(Class<MSIMEVoiceSettingsWindowRouting>)windowClass sharedController];
    if (![controller respondsToSelector:@selector(showAndActivate)]) return NO;
    [(id<MSIMEVoiceSettingsWindowRouting>)controller showAndActivate];
    return YES;
}
