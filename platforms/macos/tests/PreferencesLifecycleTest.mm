#import "PreferencesWindowController.h"
#import "AppearancePreferences.h"
#include <cassert>

// Exercise the real window delegate without presenting a window.
@interface HiddenPreferencesController : MSIMEPreferencesWindowController
@end
@implementation HiddenPreferencesController
- (void)showWindow:(id)sender { (void)sender; }
@end

static void DrainMainQueue() {
    __block BOOL drained = NO;
    dispatch_async(dispatch_get_main_queue(), ^{ drained = YES; });
    while (!drained) {
        [NSRunLoop.currentRunLoop runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.001]];
    }
}

int main() {
    @autoreleasepool {
        [NSApplication sharedApplication];
        HiddenPreferencesController *controller = [[HiddenPreferencesController alloc] initWithWindow:nil];
        __block NSUInteger closes = 0;
        id observer = [NSNotificationCenter.defaultCenter
            addObserverForName:MSIMEStandalonePreferencesDidCloseNotification
            object:controller queue:nil usingBlock:^(NSNotification *note) {
                (void)note;
                ++closes;
            }];
        [controller showAndActivate];
        assert(controller.window == MSIMEAppearancePreferences.sharedPreferences.window);
        assert(controller.window.delegate == controller);
        [controller.window close];
        DrainMainQueue();
        assert(closes == 0); // In-process settings must not terminate the input method.

        [controller showAndActivateForStandaloneLaunch];
        [controller.window close];
        [controller windowWillClose:[NSNotification notificationWithName:NSWindowWillCloseNotification object:controller.window]];
        assert(closes == 0); // Termination is deferred until AppKit finishes closing.
        DrainMainQueue();
        assert(closes == 1);
        [controller.window close];
        DrainMainQueue();
        assert(closes == 1);

        [controller showAndActivateForStandaloneLaunch];
        [controller showAndActivate];
        [controller.window close];
        DrainMainQueue();
        assert(closes == 1); // Ordinary presentation clears standalone state.
        [NSNotificationCenter.defaultCenter removeObserver:observer];
    }
    return 0;
}
