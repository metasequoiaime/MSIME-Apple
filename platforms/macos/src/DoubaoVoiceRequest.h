#pragma once
#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN
// Single-use native transport. Hosts supply converted mono 16 kHz float PCM,
// own microphone/focus state, and validate their session before applying text.
// All lifecycle methods are serialized internally; callbacks run on main.
typedef void (^MSIMEDoubaoResult)(NSString * _Nullable text, BOOL final, NSError * _Nullable error);
@interface MSIMEDoubaoVoiceRequest : NSObject
- (nullable instancetype)initWithOptions:(NSDictionary *)options error:(NSError **)error;
- (BOOL)startWithResult:(MSIMEDoubaoResult)result error:(NSError **)error;
- (BOOL)appendPCM:(NSData *)pcm error:(NSError **)error;
- (BOOL)finishWithError:(NSError **)error;
- (void)cancel;
@end
NS_ASSUME_NONNULL_END
