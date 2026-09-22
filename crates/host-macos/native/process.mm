#import <AppKit/AppKit.h>

// Stop the separate IMK host before moving its SQLite databases. The settings application has a
// different bundle identifier, so it is never part of this set.
extern "C" bool msime_macos_stop_input_method(void) {
    if (!NSThread.isMainThread) return false;
    NSString *identifier = @"app.msime.inputmethod.MetasequoiaIME";
    NSArray<NSRunningApplication *> *applications =
        [NSRunningApplication runningApplicationsWithBundleIdentifier:identifier];
    for (NSRunningApplication *application in applications) {
        if (!application.terminated && ![application terminate]) return false;
    }
    NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:3.0];
    while ([deadline timeIntervalSinceNow] > 0.0) {
        BOOL running = NO;
        for (NSRunningApplication *application in applications) {
            if (!application.terminated) {
                running = YES;
                break;
            }
        }
        if (!running) return true;
        [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.02]];
    }
    return [applications indexOfObjectPassingTest:^BOOL(NSRunningApplication *application, NSUInteger, BOOL *) {
        return !application.terminated;
    }] == NSNotFound;
}
