#import <AppKit/AppKit.h>
#import <InputMethodKit/InputMethodKit.h>
#import "InputSourceRegistration.h"
#import "../settings/PreferencesWindowController.h"
#import "../settings/RuntimeOptions.h"
#import "../settings/AppearancePreferences.h"
#import "../candidate/CandidateSkin.h"
#import "../voice/VoiceAudioMuter.h"
#include <cstring>
#include <dlfcn.h>

static bool MSIMEShouldShowPreferences(int argc, const char *argv[]) {
    for (int index = 1; index < argc; ++index) {
        if (strcmp(argv[index], "--preferences") == 0) return true;
    }
    return false;
}

static void MSIMEConfigureMovableState(void) {
    NSDictionary *options = MSIMELoadRuntimeOptions();
    NSString *directory = [options[@"preferences_directory"] isKindOfClass:NSString.class]
        ? options[@"preferences_directory"] : nil;
    if (directory.length > 0 && directory.isAbsolutePath) {
        metasequoia::mac::SetDefaultSkinsRoot(
            std::filesystem::path(directory.fileSystemRepresentation) / "skins");
    }
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
        MSIMEConfigureMovableState();
        NSString *swiftBackend = [NSBundle.mainBundle.privateFrameworksPath stringByAppendingPathComponent:@"MSIMEBackend.dylib"];
        if (swiftBackend.length > 0 && dlopen(swiftBackend.fileSystemRepresentation, RTLD_NOW | RTLD_GLOBAL) == nullptr) return 1;
        using MSIMEStartTelemetryFn = void (*)(void);
        MSIMEStartTelemetryFn startTelemetry = reinterpret_cast<MSIMEStartTelemetryFn>(dlsym(RTLD_DEFAULT, "MSIMEStartTelemetry"));
        if (startTelemetry != nullptr) startTelemetry();
        if (MSIMEShouldShowPreferences(argc, argv)) {
            [NSApp setActivationPolicy:NSApplicationActivationPolicyRegular];
            id closeObserver = [[NSNotificationCenter defaultCenter]
                addObserverForName:MSIMEStandalonePreferencesDidCloseNotification
                            object:nil
                             queue:NSOperationQueue.mainQueue
                        usingBlock:^(NSNotification *notification) {
                            (void)notification;
                            [NSApp terminate:nil];
                        }];
            [[MSIMEPreferencesWindowController sharedController] showAndActivateForStandaloneLaunch];
            [NSApp run];
            [[NSNotificationCenter defaultCenter] removeObserver:closeObserver];
            return 0;
        }
        // Recover a prior crashed capture before accepting new IMK sessions.
        // A running owner holds the journal lock, so this cannot undo its mute.
        [[[MSIMEVoiceAudioMuter alloc] init] restore];
        __attribute__((objc_precise_lifetime)) IMKServer *server = [[IMKServer alloc] initWithName:@"MSIMEClientPreviewConnection" bundleIdentifier:NSBundle.mainBundle.bundleIdentifier];
        if (!server) return 1;
        __attribute__((objc_precise_lifetime)) MSIMEInputSourceMonitor *sourceMonitor =
            [[MSIMEInputSourceMonitor alloc] initWithCenter:NSDistributedNotificationCenter.defaultCenter
                bundleIdentifier:NSBundle.mainBundle.bundleIdentifier copySource:TISCopyCurrentKeyboardInputSource
                propertyGetter:[](TISInputSourceRef source, CFStringRef key) -> void * {
                    return (void *)TISGetInputSourceProperty(source, key);
                } switchedAway:^{ [[MSIMEAppearancePreferences sharedPreferences] resetGlobalInputMode]; }];
        Class bridge = NSClassFromString(@"MSIMEBackendWindowBridge");
        id shared = [bridge respondsToSelector:@selector(shared)] ? [bridge performSelector:@selector(shared)] : nil;
        if ([shared respondsToSelector:@selector(startClipboardCaptureWithOptions:)]) {
            [shared performSelector:@selector(startClipboardCaptureWithOptions:) withObject:MSIMELoadRuntimeOptions() ?: @{}];
        }
        [NSApp run];
        if ([shared respondsToSelector:@selector(stopClipboardCapture)]) [shared performSelector:@selector(stopClipboardCapture)];
        [sourceMonitor stop];
        (void)server;
    }
    return 0;
}
