#pragma once
#import <Foundation/Foundation.h>
NS_ASSUME_NONNULL_BEGIN
typedef void (^MetasequoiaVoiceCompletion)(NSString *_Nullable text, NSError *_Nullable error);
@protocol MetasequoiaVoiceService <NSObject>
@property(nonatomic, readonly) BOOL active;
@property(nonatomic, readonly) BOOL recording;
- (void)startWithCompletion:(MetasequoiaVoiceCompletion)completion;
- (void)stop;
- (void)cancel;
@end
// All methods and completion callbacks run on the main thread. cancel invalidates
// pending permission/network/inference callbacks; it never commits partial text.
@interface MetasequoiaVoiceInputService : NSObject <MetasequoiaVoiceService>
@end
NS_ASSUME_NONNULL_END
