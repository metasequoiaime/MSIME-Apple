#pragma once
#import <Foundation/Foundation.h>
#include "InputControllerKeyRouting.h"
#include <cmath>

// Local product options; do not extend the backend's versioned preference schema.
inline NSString *const MetasequoiaInputBehaviorKey = @"MetasequoiaImeInputBehavior";
inline NSDictionary *MetasequoiaInputBehavior()
{
    NSDictionary *values = [NSUserDefaults.standardUserDefaults dictionaryForKey:MetasequoiaInputBehaviorKey];
    return values ? values : @{};
}
inline NSInteger MetasequoiaInputInteger(NSString *key, NSInteger fallback, NSInteger minimum, NSInteger maximum)
{
    id value = MetasequoiaInputBehavior()[key];
    if (![value isKindOfClass:NSNumber.class] || !std::isfinite([value doubleValue]) ||
        [value doubleValue] != [value integerValue])
        return fallback;
    NSInteger number = [value integerValue];
    return number >= minimum && number <= maximum ? number : fallback;
}
inline void MetasequoiaSetInputBehavior(NSString *key, NSInteger value)
{
    [NSUserDefaults.standardUserDefaults synchronize];
    NSMutableDictionary *values = [MetasequoiaInputBehavior() mutableCopy];
    values[key] = @(value);
    // Both controls own the same keys. Enabling one turns the other off atomically.
    if ([key isEqualToString:@"edgeSelection"] && value)
        values[@"pageBrackets"] = @0;
    if ([key isEqualToString:@"pageBrackets"] && value)
        values[@"edgeSelection"] = @0;
    if ([key isEqualToString:@"alwaysChinesePunctuation"] && value)
        values[@"alwaysEnglishPunctuation"] = @0;
    if ([key isEqualToString:@"alwaysEnglishPunctuation"] && value)
        values[@"alwaysChinesePunctuation"] = @0;
    [NSUserDefaults.standardUserDefaults setObject:values forKey:MetasequoiaInputBehaviorKey];
    [NSUserDefaults.standardUserDefaults synchronize];
}
inline BOOL MetasequoiaInputFlag(NSString *key, BOOL fallback = NO)
{
    return MetasequoiaInputInteger(key, fallback ? 1 : 0, 0, 1) != 0;
}
inline metasequoia::mac::CandidateKeyOptions MetasequoiaCandidateKeyOptions(NSInteger legacyShortcut)
{
    return {
        MetasequoiaInputInteger(@"pageMinus", legacyShortcut == 0, 0, 1) != 0,
        MetasequoiaInputInteger(@"pageComma", 0, 0, 1) != 0,
        MetasequoiaInputInteger(@"pageBrackets", legacyShortcut == 1, 0, 1) != 0,
        MetasequoiaInputInteger(@"pageKeys", 1, 0, 1) != 0,
        MetasequoiaInputInteger(@"verticalNavigation", 1, 0, 1) != 0,
        MetasequoiaInputInteger(@"edgeSelection", 0, 0, 1) != 0,
    };
}

inline BOOL MetasequoiaRememberedEnglishMode(NSString *bundleIdentifier)
{
    id modes = MetasequoiaInputBehavior()[@"applicationModes"];
    id value = [modes isKindOfClass:NSDictionary.class] && bundleIdentifier.length ? modes[bundleIdentifier] : nil;
    return [value isKindOfClass:NSNumber.class] ? [value boolValue]
                                                : MetasequoiaInputInteger(@"defaultEnglish", 0, 0, 1) != 0;
}
inline void MetasequoiaRememberEnglishMode(NSString *bundleIdentifier, BOOL english)
{
    if (!bundleIdentifier.length || !MetasequoiaInputInteger(@"perApplicationMode", 0, 0, 1))
        return;
    [NSUserDefaults.standardUserDefaults synchronize];
    NSMutableDictionary *values = [MetasequoiaInputBehavior() mutableCopy];
    id stored = values[@"applicationModes"];
    NSMutableDictionary *modes =
        [stored isKindOfClass:NSDictionary.class] ? [stored mutableCopy] : [NSMutableDictionary dictionary];
    modes[bundleIdentifier] = @(english);
    values[@"applicationModes"] = modes;
    [NSUserDefaults.standardUserDefaults setObject:values forKey:MetasequoiaInputBehaviorKey];
    [NSUserDefaults.standardUserDefaults synchronize];
}
