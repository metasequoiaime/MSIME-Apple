#import <AppKit/AppKit.h>
#import <InputMethodKit/InputMethodKit.h>
#import "InputSourceRegistration.h"
#import "PreferencesWindowController.h"
#import "RuntimeOptions.h"
#include <cstring>
#include <dlfcn.h>

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
        NSString *swiftBackend = [NSBundle.mainBundle.privateFrameworksPath stringByAppendingPathComponent:@"MSIMEBackend.dylib"];
        if (swiftBackend.length > 0 && dlopen(swiftBackend.fileSystemRepresentation, RTLD_NOW | RTLD_GLOBAL) == nullptr) return 1;
        if (MSIMEShouldShowPreferences(argc, argv)) {
            [NSApp setActivationPolicy:NSApplicationActivationPolicyRegular];
            [[MSIMEPreferencesWindowController sharedController] showAndActivate];
            [NSApp run];
            return 0;
        }
        __attribute__((objc_precise_lifetime)) IMKServer *server = [[IMKServer alloc] initWithName:@"MSIMEClientPreviewConnection" bundleIdentifier:NSBundle.mainBundle.bundleIdentifier];
        if (!server) return 1;
        Class bridge = NSClassFromString(@"MSIMEBackendWindowBridge");
        id shared = [bridge respondsToSelector:@selector(shared)] ? [bridge performSelector:@selector(shared)] : nil;
        if ([shared respondsToSelector:@selector(startClipboardCaptureWithOptions:)]) {
            [shared performSelector:@selector(startClipboardCaptureWithOptions:) withObject:MSIMELoadRuntimeOptions() ?: @{}];
        }
        [NSApp run];
        if ([shared respondsToSelector:@selector(stopClipboardCapture)]) [shared performSelector:@selector(stopClipboardCapture)];
        (void)server;
    }
    return 0;
}
