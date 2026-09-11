#pragma once
#import <Foundation/Foundation.h>
#import <AVFoundation/AVFoundation.h>
#import <Speech/Speech.h>
#import "MSIMEClientSession.h"

NS_ASSUME_NONNULL_BEGIN
typedef void (^MSIMEVoiceInputResult)(NSDictionary * _Nullable result, NSError * _Nullable error);
typedef void (^MSIMEVoiceAudioBuffer)(AVAudioPCMBuffer *buffer);
@interface MSIMEVoiceInputService : NSObject
- (BOOL)startWithSession:(MSIMEClientSession *)session generation:(uint64_t *)generation error:(NSError **)error;
- (BOOL)cancelWithError:(NSError **)error;
- (BOOL)startMicrophoneCapture:(MSIMEVoiceAudioBuffer)bufferHandler error:(NSError **)error;
- (void)stopMicrophoneCapture;
- (BOOL)startTranscriptionWithLanguage:(NSString *)language textHandler:(void (^)(NSString *text, BOOL final))handler error:(NSError **)error;
- (void)stopTranscription;
- (AVAuthorizationStatus)microphoneAuthorizationStatus;
- (void)requestMicrophonePermission:(void (^)(BOOL granted))completion;
- (void)applyText:(NSString *)text generation:(uint64_t)generation completion:(MSIMEVoiceInputResult)completion;
@property(nonatomic, readonly, getter=isActive) BOOL active;
@end
NS_ASSUME_NONNULL_END
