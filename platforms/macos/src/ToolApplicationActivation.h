#pragma once
#import <AppKit/AppKit.h>

static inline BOOL MSIMEToolApplicationMatches(NSString *clientBundle, NSString *applicationBundle) {
    return [clientBundle isKindOfClass:NSString.class] && clientBundle.length > 0 &&
           [applicationBundle isKindOfClass:NSString.class] && [clientBundle isEqualToString:applicationBundle];
}

// A successful request is not evidence that activation has completed.
static inline BOOL MSIMEActivateToolApplication(NSApplication *host, NSRunningApplication *source,
                                                NSRunningApplication *target, BOOL cooperative = YES) {
    if (!host || !source || !target || target.terminated) return NO;
    if (cooperative) {
        if (@available(macOS 14.0, *)) {
            [host yieldActivationToApplication:target];
            return [target activateFromApplication:source options:0];
        }
    }
    return [target activateWithOptions:0];
}
