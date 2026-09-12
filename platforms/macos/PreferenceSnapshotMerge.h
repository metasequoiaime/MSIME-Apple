#pragma once
#import <Foundation/Foundation.h>

// Pure merge: no window controller/defaults reads on the persistence worker.
// Nested overrides own only their named fields; preserve other host settings.
static inline NSDictionary *MSIMEMergePreferenceSnapshot(NSDictionary *base, NSDictionary *overrides) {
    if (![base isKindOfClass:NSDictionary.class] || ![overrides isKindOfClass:NSDictionary.class]) return nil;
    NSMutableDictionary *merged = [base mutableCopy];
    for (NSString *key in overrides) {
        id value = overrides[key];
        if ([value isKindOfClass:NSDictionary.class]) {
            id original = base[key] ?: @{};
            NSDictionary *nested = MSIMEMergePreferenceSnapshot(original, value);
            if (!nested) return nil;
            merged[key] = nested;
        } else {
            merged[key] = value;
        }
    }
    return [merged copy];
}
