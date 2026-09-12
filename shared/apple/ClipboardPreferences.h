#import <Foundation/Foundation.h>

// Only change this preference. The supplied save must enforce the loaded revision.
static inline NSDictionary *MSIMEEnableClipboardHistory(
    NSDictionary *(^load)(void),
    NSDictionary *(^save)(uint64_t, NSDictionary *)) {
    NSDictionary *current = load();
    if (![current isKindOfClass:NSDictionary.class] ||
        ![current[@"revision"] isKindOfClass:NSNumber.class] ||
        ![current[@"preferences"] isKindOfClass:NSDictionary.class]) return @{ @"error": @YES };
    NSDictionary *preferences = current[@"preferences"];
    if (![preferences[@"clipboard_history"] isKindOfClass:NSNumber.class]) return @{ @"error": @YES };
    if ([preferences[@"clipboard_history"] boolValue]) return @{ @"enabled": @YES };
    NSMutableDictionary *next = [current mutableCopy];
    NSMutableDictionary *values = [preferences mutableCopy];
    values[@"clipboard_history"] = @YES;
    next[@"preferences"] = values;
    NSDictionary *result = save([current[@"revision"] unsignedLongLongValue], next);
    if (![result[@"preferences"] isKindOfClass:NSDictionary.class] ||
        ![result[@"preferences"][@"clipboard_history"] isEqual:@YES]) return @{ @"error": @YES };
    return @{ @"enabled": @YES };
}
