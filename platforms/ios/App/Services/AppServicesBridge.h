#import <Foundation/Foundation.h>
NS_ASSUME_NONNULL_BEGIN
@interface AppServicesBridge : NSObject
+ (nullable NSData *)polishBody:(NSString *)model prompt:(NSString *)prompt text:(NSString *)text error:(NSError **)error;
+ (nullable NSDictionary<NSString *, id> *)transcriptionBody:(NSData *)wav model:(NSString *)model error:(NSError **)error;
+ (nullable NSString *)parseResponse:(NSData *)data voice:(BOOL)voice error:(NSError **)error;
@end
NS_ASSUME_NONNULL_END
