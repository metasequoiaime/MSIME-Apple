#import <AppKit/AppKit.h>
#import <InputMethodKit/InputMethodKit.h>
#import "InputSourceRegistration.h"
#import "AppearancePreferences.h"
#include <cstring>

static bool MSIMEShouldShowPreferences(int argc, const char *argv[]) {
    for (int index = 1; index < argc; ++index) {
        if (strcmp(argv[index], "--preferences") == 0) return true;
    }
    return false;
}

int main(int argc, const char *argv[]) {
    @autoreleasepool {
        if (MSIMEShouldRegisterInputSource(argc, argv)) {
            NSURL *bundleURL = NSBundle.mainBundle.bundleURL;
            NSString *identifier = NSBundle.mainBundle.bundleIdentifier;
            OSStatus status = MSIMERegisterAndEnableInputSources(bundleURL, identifier,
                TISRegisterInputSource, TISCreateInputSourceList,
                [](TISInputSourceRef source, CFStringRef key) -> void * {
                    return (void *)TISGetInputSourceProperty(source, key);
                }, TISEnableInputSource);
            return status == noErr ? 0 : 1;
        }
        [NSApplication sharedApplication];
        if (MSIMEShouldShowPreferences(argc, argv)) {
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
