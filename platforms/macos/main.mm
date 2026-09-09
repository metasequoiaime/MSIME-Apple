#import <AppKit/AppKit.h>
#import <InputMethodKit/InputMethodKit.h>

int main() {
    @autoreleasepool {
        [NSApplication sharedApplication];
        __attribute__((objc_precise_lifetime)) IMKServer *server = [[IMKServer alloc] initWithName:@"MSIMEClientPreviewConnection" bundleIdentifier:NSBundle.mainBundle.bundleIdentifier];
        if (!server) return 1;
        [NSApp run];
        (void)server;
    }
    return 0;
}
