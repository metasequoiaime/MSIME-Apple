#import <AppKit/AppKit.h>
#import <InputMethodKit/InputMethodKit.h>
#import "PreferencesWindowController.h"
#import "InputSourceRegistration.h"
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
        if (MetasequoiaShouldRegisterInputSource(argc, argv)) {
            OSStatus status = MetasequoiaRegisterAndEnableInputSources(NSBundle.mainBundle.bundleURL, NSBundle.mainBundle.bundleIdentifier, TISRegisterInputSource, TISCreateInputSourceList, TISGetInputSourceProperty, TISEnableInputSource);
            return status == noErr ? 0 : 1;
        }
        [NSApplication sharedApplication];
        if (MSIMEShouldShowPreferences(argc, argv))
        {
            [NSApp setActivationPolicy:NSApplicationActivationPolicyRegular];
            MSIMEPreferencesWindowController *preferences = [MSIMEPreferencesWindowController sharedController];
            id closeObserver = [NSNotificationCenter.defaultCenter
                addObserverForName:MSIMEStandalonePreferencesDidCloseNotification
                object:preferences queue:NSOperationQueue.mainQueue
                usingBlock:^(NSNotification *notification) {
                    (void)notification;
                    [NSApp terminate:nil];
                }];
            [preferences showAndActivateForStandaloneLaunch];
            [NSApp run];
            [NSNotificationCenter.defaultCenter removeObserver:closeObserver];
            return 0;
        }
        __attribute__((objc_precise_lifetime)) IMKServer *server = [[IMKServer alloc] initWithName:@"MSIMEClientPreviewConnection" bundleIdentifier:NSBundle.mainBundle.bundleIdentifier];
        if (!server) return 1;
        [NSApp run];
        (void)server;
    }
    return 0;
}
