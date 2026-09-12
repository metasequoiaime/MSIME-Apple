#pragma once
#import <Foundation/Foundation.h>

// IMK can reactivate the same controller. Registration must remain idempotent.
static inline void MSIMESetBackendSelectionObservation(NSNotificationCenter *center,
                                                       id observer, SEL selector, BOOL active) {
    NSString *name = @"MSIMEHandwritingCandidateSelected";
    [center removeObserver:observer name:name object:nil];
    if (active) [center addObserver:observer selector:selector name:name object:nil];
}
