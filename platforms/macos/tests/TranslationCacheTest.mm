#import "../TranslationCache.h"
#include <cassert>
@interface TestTranslationCache : MSIMETranslationCache
@property(nonatomic) NSTimeInterval now;
@end
@implementation TestTranslationCache
- (NSTimeInterval)currentTime { return self.now; }
@end
int main() {
    @autoreleasepool {
        TestTranslationCache *cache = [TestTranslationCache new];
        NSMutableString *text = [@"hello" mutableCopy];
        NSArray *identity = @[@"https://translation.invalid/api", @"en", @"en", @"zh", text];
        [cache rememberTranslation:@"你好" identity:identity];
        [text setString:@"changed"];
        NSArray *original = @[@"https://translation.invalid/api", @"en", @"en", @"zh", @"hello"];
        assert([[cache valueForIdentity:original] isEqual:@"你好"]);
        assert(![cache valueForIdentity:identity]);
        for (NSUInteger index = 0; index < original.count; ++index) {
            NSMutableArray *different = [original mutableCopy]; different[index] = @"different";
            assert(![cache valueForIdentity:different]);
        }
        cache.now = 100;
        [cache rememberTranslation:nil identity:original];
        assert([cache valueForIdentity:original] == NSNull.null);
        cache.now = 579.99; assert([cache valueForIdentity:original] == NSNull.null);
        cache.now = 580; assert(![cache valueForIdentity:original]);
        [cache rememberTranslation:nil identity:original];
        [cache rememberTranslation:@"positive" identity:original];
        assert([[cache valueForIdentity:original] isEqual:@"positive"]);
        [cache clear]; assert(![cache valueForIdentity:original]);
        for (NSNumber *positive in @[@NO, @YES]) {
            [cache clear];
            for (NSUInteger i = 0; i < 4096; ++i)
                [cache rememberTranslation:positive.boolValue ? @"value" : nil identity:@[[NSString stringWithFormat:@"synthetic-%lu", (unsigned long)i]]];
            assert([cache valueForIdentity:@[@"synthetic-0"]]);
            [cache rememberTranslation:positive.boolValue ? @"value" : nil identity:@[@"overflow"]];
            assert(![cache valueForIdentity:@[@"synthetic-0"]] && [cache valueForIdentity:@[@"overflow"]]);
        }
    }
    return 0;
}
