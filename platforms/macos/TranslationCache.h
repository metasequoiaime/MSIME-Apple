#import <Foundation/Foundation.h>

/// Main-thread, process-local cache. Never persists candidate text or credentials.
@interface MSIMETranslationCache : NSObject
+ (instancetype)sharedCache;
/// NSString = positive hit, NSNull = unexpired negative hit, nil = miss.
- (id)valueForIdentity:(NSArray<NSString *> *)identity;
- (void)rememberTranslation:(NSString *)translation identity:(NSArray<NSString *> *)identity;
- (void)clear;
@end
