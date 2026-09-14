#pragma once
#import <Foundation/Foundation.h>
#import <AVFoundation/AVFoundation.h>
#import <Speech/Speech.h>
#import "../../shared/apple/MSIMEClientSession.h"
NS_ASSUME_NONNULL_BEGIN
typedef void (^MSIMEVoiceInputResult)(NSDictionary * _Nullable, NSError * _Nullable);
typedef void (^MSIMEVoiceAudioBuffer)(AVAudioPCMBuffer *);
@interface MSIMEVoiceInputService : NSObject
- (BOOL)startWithSession:(MSIMEClientSession *)session generation:(uint64_t *)generation error:(NSError **)error;
- (BOOL)cancelWithError:(NSError **)error;
- (BOOL)startMicrophoneCapture:(MSIMEVoiceAudioBuffer)handler deviceUID:(NSString * _Nullable)deviceUID error:(NSError **)error;
- (void)stopMicrophoneCapture;
// Main-thread lifecycle; raw buffers are converted on the capture callback.
// Finish stops capture and returns one immutable recording; cancel discards it.
- (BOOL)startPCMRecording:(MSIMEVoiceAudioBuffer)handler deviceUID:(NSString * _Nullable)deviceUID error:(NSError **)error;
- (NSData * _Nullable)finishPCMRecordingWithError:(NSError **)error;
- (BOOL)startTranscriptionWithLanguage:(NSString *)language textHandler:(void (^)(NSString *, BOOL))handler error:(NSError **)error;
- (void)stopTranscription;
- (AVAuthorizationStatus)microphoneAuthorizationStatus;
- (void)requestMicrophonePermission:(void (^)(BOOL))completion;
- (SFSpeechRecognizerAuthorizationStatus)speechAuthorizationStatus;
- (void)requestSpeechPermission:(void (^)(BOOL))completion;
- (void)applyText:(NSString *)text generation:(uint64_t)generation completion:(MSIMEVoiceInputResult)completion;
@property(nonatomic, readonly, getter=isActive) BOOL active;
@end
NS_ASSUME_NONNULL_END
