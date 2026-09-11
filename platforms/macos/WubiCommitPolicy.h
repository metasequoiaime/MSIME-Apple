#pragma once
#import <Foundation/Foundation.h>

inline BOOL MSIMEShouldAutoCommitWubi(BOOL enabled, NSDictionary *view) {
    if (!enabled || ![view isKindOfClass:NSDictionary.class]) return NO;
    NSNumber *scheme = view[@"scheme"];
    NSNumber *fallback = view[@"answered_by_pinyin_fallback"];
    NSString *preedit = view[@"preedit"];
    NSArray *candidates = view[@"candidates"];
    return [scheme isKindOfClass:NSNumber.class] && scheme.integerValue == 2 &&
        [fallback isKindOfClass:NSNumber.class] && !fallback.boolValue &&
        [preedit isKindOfClass:NSString.class] && preedit.length == 4 &&
        [candidates isKindOfClass:NSArray.class] && candidates.count == 1;
}
