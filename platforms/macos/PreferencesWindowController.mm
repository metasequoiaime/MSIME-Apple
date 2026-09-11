#import "PreferencesWindowController.h"
#import "AppearancePreferences.h"

NSNotificationName const MSIMEStandalonePreferencesDidCloseNotification = @"MSIMEClientStandalonePreferencesDidClose";

@implementation MSIMEPreferencesWindowController {
    BOOL _standaloneLaunch;
}
+ (instancetype)sharedController {
    static MSIMEPreferencesWindowController *controller;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ controller = [[self alloc] initWithWindow:nil]; });
    return controller;
}
- (void)showAndActivate {
    _standaloneLaunch = NO;
    [self presentAndActivate];
}
- (void)showAndActivateForStandaloneLaunch {
    _standaloneLaunch = YES;
    [self presentAndActivate];
}
- (void)presentAndActivate {
    self.window = [MSIMEAppearancePreferences sharedPreferences].window;
    self.window.delegate = self;
    [self showWindow:nil];
    [NSApp activateIgnoringOtherApps:YES];
}
- (void)windowWillClose:(NSNotification *)notification {
    if (notification.object != self.window || !_standaloneLaunch) return;
    _standaloneLaunch = NO;
    dispatch_async(dispatch_get_main_queue(), ^{
        [NSNotificationCenter.defaultCenter postNotificationName:MSIMEStandalonePreferencesDidCloseNotification object:self];
    });
}
@end
