#import "../../src/core/UpdateController.h"

#import <AppKit/AppKit.h>

#include <cassert>
#include <cstdio>

// Stands in for Sparkle so the controller's own behaviour can be checked without starting an updater.
@interface UpdateDriverFixture : NSObject <MetasequoiaUpdateDriver>
@property(nonatomic) BOOL canCheckForUpdates;
@property(nonatomic) BOOL automaticallyChecksForUpdates;
@property(nonatomic) NSUInteger checks;
@property(nonatomic) id lastSender;
@end

@implementation UpdateDriverFixture
- (void)checkForUpdates:(id)sender
{
    self.lastSender = sender;
    ++self.checks;
}
@end

int main()
{
    @autoreleasepool
    {
        // The activation handler talks to NSApp; without this it would be messaging nil rather than the
        // accessory application the shipped controller runs in.
        [NSApplication sharedApplication];
        __block NSUInteger activations = 0;
        UpdateDriverFixture *driver = [UpdateDriverFixture new];
        driver.canCheckForUpdates = YES;
        driver.automaticallyChecksForUpdates = YES;
        MSIMEUpdateController *controller =
            [[MSIMEUpdateController alloc] initWithDriver:driver
                                        activationHandler:^{ ++activations; }];

        assert(controller.canCheckForUpdates);
        assert(controller.automaticallyChecksForUpdates);

        // The menu item is in an accessory process, so a manual check has to raise the window itself
        // before handing the request on; a check that activates nothing leaves the sheet behind whatever
        // the user was typing into.
        NSMenuItem *sender = [NSMenuItem new];
        [controller checkForUpdates:sender];
        assert(activations == 1 && driver.checks == 1 && driver.lastSender == sender);

        // Both are read through, not cached: Sparkle answers differently once an update is in flight, and
        // a stale "can check" leaves the menu item enabled for a check that cannot start.
        driver.canCheckForUpdates = NO;
        driver.automaticallyChecksForUpdates = NO;
        assert(!controller.canCheckForUpdates);
        assert(!controller.automaticallyChecksForUpdates);

        // Sparkle is only startable inside an application bundle. Everywhere else - a test binary, a
        // command-line tool, a bundle whose identifier never made it into the plist - it answers a start
        // with a modal alert, and an input method that stops typing behind a dialog is the worse failure.
        assert(MSIMEUpdateHostIsApplicationBundle(@"app.msime.inputmethod.MetasequoiaIME",
                                                  @"/Users/someone/Library/Input Methods/水杉输入法（预览）.app"));
        assert(MSIMEUpdateHostIsApplicationBundle(@"app.example", @"/Applications/Example.app/"));
        assert(!MSIMEUpdateHostIsApplicationBundle(nil, @"/Applications/Example.app"));
        assert(!MSIMEUpdateHostIsApplicationBundle(@"", @"/Applications/Example.app"));
        assert(!MSIMEUpdateHostIsApplicationBundle(@"app.example", nil));
        assert(!MSIMEUpdateHostIsApplicationBundle(@"app.example", @"/usr/local/bin/example"));
        // A bundle path that merely contains ".app" is not one: this is the shape a test binary built
        // inside a bundle's directory has.
        assert(!MSIMEUpdateHostIsApplicationBundle(@"app.example", @"/Applications/Example.app/Contents/MacOS/example"));

        // This binary is exactly the case the guard exists for, so the shared controller must not have
        // started Sparkle - and must still answer rather than crash the caller.
        assert(!MSIMEUpdateHostIsApplicationBundle(NSBundle.mainBundle.bundleIdentifier,
                                                   NSBundle.mainBundle.bundlePath));
        MSIMEUpdateController *shared = MSIMEUpdateController.sharedController;
        assert(shared && !shared.canCheckForUpdates && !shared.automaticallyChecksForUpdates);
        [shared checkForUpdates:nil];
    }
    std::puts("macOS update controller passed.");
    return 0;
}
