#import <AppKit/AppKit.h>
#import <InputMethodKit/InputMethodKit.h>
#import "AppearancePreferences.h"
#include <cstring>

static bool MSIMEShouldShowPreferences(int argc, const char *argv[])
{
    for (int index = 1; index < argc; ++index)
    {
        if (std::strcmp(argv[index], "--preferences") == 0) return true;
    }
    return false;
}

int main(int argc, const char *argv[])
{
    @autoreleasepool {
        [NSApplication sharedApplication];
        if (MSIMEShouldShowPreferences(argc, argv))
        {
            [NSApp setActivationPolicy:NSApplicationActivationPolicyRegular];
            [[MSIMEAppearancePreferences sharedPreferences] showWindow:nil];
            [NSApp activateIgnoringOtherApps:YES];
            [NSApp run];
            return 0;
        }
        __attribute__((objc_precise_lifetime)) IMKServer *server = [[IMKServer alloc] initWithName:@"MSIMEClientPreviewConnection" bundleIdentifier:NSBundle.mainBundle.bundleIdentifier];
        if (!server) return 1;
        [NSApp run];
        (void)server;
    }
    return 0;
}
