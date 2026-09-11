#pragma once
#import <Foundation/Foundation.h>

// Swift class is loaded from the bundled dylib, not linked into native tests.
@protocol MSIMEBackendAccountEntry <NSObject>
+ (id)shared;
- (void)showAccount;
@end

static inline BOOL MSIMEOpenBackendAccount(Class windowClass) {
    if (![windowClass respondsToSelector:@selector(shared)]) return NO;
    id<MSIMEBackendAccountEntry> window = [(id<MSIMEBackendAccountEntry>)windowClass shared];
    if (![window respondsToSelector:@selector(showAccount)]) return NO;
    [window showAccount];
    return YES;
}
