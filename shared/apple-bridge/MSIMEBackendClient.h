#import <Foundation/Foundation.h>
NS_ASSUME_NONNULL_BEGIN
// Main-thread client; each instance owns one cancellable cloud-candidate request.
@interface MSIMEBackendClient : NSObject <NSURLSessionDataDelegate>
+ (NSString *)baseURL;
+ (BOOL)isEnabled;
+ (BOOL)saveBaseURL:(NSString *)baseURL token:(NSString *)token enabled:(BOOL)enabled;
+ (BOOL)isValidBaseURL:(NSString *)baseURL;
- (void)reloadConfiguration;
- (void)cancel;
- (void)cloudCandidateForText:(NSString *)text
                     japanese:(BOOL)japanese
                   completion:(void (^)(NSString *_Nullable candidate))completion;
@end
NS_ASSUME_NONNULL_END
