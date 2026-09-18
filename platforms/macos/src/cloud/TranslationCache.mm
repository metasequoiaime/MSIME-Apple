#import "TranslationCache.h"

@implementation MSIMETranslationCache {
    NSMutableDictionary<NSArray<NSString *> *, NSString *> *_positive;
    NSMutableDictionary<NSArray<NSString *> *, NSNumber *> *_negative;
}
+ (instancetype)sharedCache {
    static MSIMETranslationCache *cache;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ cache = [MSIMETranslationCache new]; });
    return cache;
}
- (instancetype)init {
    if ((self = [super init])) { _positive = [NSMutableDictionary dictionary]; _negative = [NSMutableDictionary dictionary]; }
    return self;
}
- (NSTimeInterval)currentTime { return NSProcessInfo.processInfo.systemUptime; }
- (id)valueForIdentity:(NSArray<NSString *> *)identity {
    NSAssert(NSThread.isMainThread, @"Translation cache is main-thread only");
    NSString *positive = _positive[identity];
    if (positive) return positive;
    NSNumber *deadline = _negative[identity];
    if (deadline && deadline.doubleValue > [self currentTime]) return NSNull.null;
    [_negative removeObjectForKey:identity];
    return nil;
}
- (void)rememberTranslation:(NSString *)translation identity:(NSArray<NSString *> *)identity {
    NSAssert(NSThread.isMainThread, @"Translation cache is main-thread only");
    // Deep-copy keys so mutable caller strings cannot corrupt dictionary hashing.
    NSMutableArray *key = [NSMutableArray arrayWithCapacity:identity.count];
    for (NSString *part in identity) [key addObject:[part copy]];
    if (translation.length) {
        if (_positive.count >= 4096) [_positive removeAllObjects];
        _positive[key] = [translation copy];
        [_negative removeObjectForKey:key];
    } else {
        if (_negative.count >= 4096) [_negative removeAllObjects];
        _negative[key] = @([self currentTime] + 8 * 60);
        [_positive removeObjectForKey:key];
    }
}
- (void)clear {
    NSAssert(NSThread.isMainThread, @"Translation cache is main-thread only");
    [_positive removeAllObjects]; [_negative removeAllObjects];
}
@end
