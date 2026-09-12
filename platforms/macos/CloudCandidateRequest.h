#import <Foundation/Foundation.h>

/// One bounded ephemeral request. All methods and completion run on main thread.
@interface MSIMECloudCandidateRequest : NSObject <NSURLSessionDataDelegate>
- (instancetype)initWithURL:(NSURL *)url configuration:(NSURLSessionConfiguration *)configuration
                 completion:(void (^)(NSData *body))completion;
- (void)start;
/// Cancel without delivering a result; safe after completion.
- (void)cancel;
@end
