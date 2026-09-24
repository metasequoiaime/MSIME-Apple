#pragma once
#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN
// Single-use native transport. Hosts supply converted mono 16 kHz float PCM,
// own microphone/focus state, and validate their session before applying text.
// All lifecycle methods are serialized internally; callbacks run on main.
typedef void (^MSIMEDoubaoResult)(NSString * _Nullable text, BOOL final, NSError * _Nullable error);
// The streaming shape the controller drives: partial text while the user speaks, one final after finish. Doubao's websocket and the on-device helper (LocalVoiceRequest.h) both provide it, so both share one controller path with its inline preedit, overlay transcript and polish.
@protocol MSIMEStreamingVoiceRequest <NSObject>
- (BOOL)startWithResult:(MSIMEDoubaoResult)result error:(NSError **)error;
- (BOOL)appendPCM:(NSData *)pcm error:(NSError **)error;
- (BOOL)finishWithError:(NSError **)error;
- (void)cancel;
@end
@interface MSIMEDoubaoVoiceRequest : NSObject <MSIMEStreamingVoiceRequest>
- (nullable instancetype)initWithOptions:(NSDictionary *)options error:(NSError **)error;
@end
NS_ASSUME_NONNULL_END
