#import "../SupportWindowController.h"

#include <cassert>

static NSView *FindView(NSView *view, NSString *identifier) {
    if ([view.accessibilityIdentifier isEqualToString:identifier]) return view;
    for (NSView *subview in view.subviews) {
        NSView *found = FindView(subview, identifier);
        if (found != nil) return found;
    }
    return nil;
}

int main() {
    @autoreleasepool {
        [NSApplication sharedApplication];
        MSIMESupportWindowController *controller = [MSIMESupportWindowController sharedController];
        assert(controller != nil && controller.window != nil);

        [controller showPage:MSIMESupportPageHelp];
        assert(controller.page == MSIMESupportPageHelp);
        assert([controller.window.title isEqualToString:@"水杉输入法帮助"]);
        assert(FindView(controller.window.contentView, @"MSIMESupportPreferences") != nil);

        [controller showPage:MSIMESupportPageAbout];
        assert(controller.page == MSIMESupportPageAbout);
        assert([controller.window.title isEqualToString:@"关于水杉输入法"]);
        assert(FindView(controller.window.contentView, @"MSIMESupportCheckForUpdates") != nil);
        assert(FindView(controller.window.contentView, @"MSIMESupportLicense") != nil);
        assert(FindView(controller.window.contentView, @"MSIMESupportPrivacy") != nil);

        [controller showPage:MSIMESupportPageFeedback];
        assert(controller.page == MSIMESupportPageFeedback);
        assert([controller.window.title isEqualToString:@"反馈与交流"]);
        assert(FindView(controller.window.contentView, @"MSIMESupportIssues") != nil);
        assert(FindView(controller.window.contentView, @"MSIMESupportQQ") != nil);
        assert(FindView(controller.window.contentView, @"MSIMESupportTelegram") != nil);
        [controller.window orderOut:nil];
    }
    return 0;
}
