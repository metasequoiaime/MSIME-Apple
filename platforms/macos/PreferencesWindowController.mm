#import "PreferencesWindowController.h"
#import "AppearancePreferences.h"

@implementation MSIMEPreferencesWindowController
+ (instancetype)sharedController
{
    static MSIMEPreferencesWindowController *controller;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ controller = [[self alloc] initWithWindow:nil]; });
    return controller;
}

- (void)showAndActivate
{
    [[MSIMEAppearancePreferences sharedPreferences] showWindow:nil];
    [NSApp activateIgnoringOtherApps:YES];
}
@end
