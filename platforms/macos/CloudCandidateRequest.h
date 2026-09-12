#import <Foundation/Foundation.h>

/// One bounded ephemeral request. All methods and completion run on main thread.
@interface MSIMECloudCandidateRequest : NSObject <NSURLSessionDataDelegate>
- (instancetype)initWithURL:(NSURL *)url configuration:(NSURLSessionConfiguration *)configuration
                 completion:(void (^)(NSData *body))completion;
- (void)start;
/// Consume the shared custom-translation descriptor. HTTP(S) only; no redirects.
- (instancetype)initWithTranslationDescriptor:(NSDictionary *)descriptor configuration:(NSURLSessionConfiguration *)configuration
                                   completion:(void (^)(NSData *body))completion;
/// Cancel without delivering a result; safe after completion.
- (void)cancel;
/// Fixed Tencent HTTPS endpoint. Sends signed body_utf8 unchanged; no redirects.
- (instancetype)initWithTencentDescriptor:(NSDictionary *)descriptor configuration:(NSURLSessionConfiguration *)configuration
                               completion:(void (^)(NSData *body))completion;
@end
