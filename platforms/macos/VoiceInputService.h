#pragma once
#import <Foundation/Foundation.h>
#import <AVFoundation/AVFoundation.h>
#import "MSIMEClientSession.h"

NS_ASSUME_NONNULL_BEGIN
typedef void (^MSIMEVoiceInputResult)(NSDictionary * _Nullable result, NSError * _Nullable error);
typedef void (^MSIMEVoiceAudioBuffer)(AVAudioPCMBuffer *buffer);
@interface MSIMEVoiceInputService : NSObject
- (BOOL)startWithSession:(MSIMEClientSession *)session generation:(uint64_t *)generation error:(NSError **)error;
- (BOOL)cancelWithError:(NSError **)error;
- (BOOL)startMicrophoneCapture:(MSIMEVoiceAudioBuffer)bufferHandler error:(NSError **)error;
- (void)stopMicrophoneCapture;
- (AVAuthorizationStatus)microphoneAuthorizationStatus;
- (void)requestMicrophonePermission:(void (^)(BOOL granted))completion;
- (void)applyText:(NSString *)text generation:(uint64_t)generation completion:(MSIMEVoiceInputResult)completion;
@property(nonatomic, readonly, getter=isActive) BOOL active;
@end
NS_ASSUME_NONNULL_END
