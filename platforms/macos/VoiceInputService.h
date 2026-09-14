#pragma once
#import <Foundation/Foundation.h>
#import <AVFoundation/AVFoundation.h>
#import <Speech/Speech.h>
#import "../../shared/apple/MSIMEClientSession.h"
NS_ASSUME_NONNULL_BEGIN
typedef void (^MSIMEVoiceInputResult)(NSDictionary * _Nullable, NSError * _Nullable);
typedef void (^MSIMEVoiceAudioBuffer)(AVAudioPCMBuffer *);
typedef void (^MSIMEVoicePCMChunk)(NSData * _Nullable pcm, NSError * _Nullable error);
@interface MSIMEVoiceInputService : NSObject
- (BOOL)startWithSession:(MSIMEClientSession *)session generation:(uint64_t *)generation error:(NSError **)error;
- (BOOL)cancelWithError:(NSError **)error;
- (BOOL)startMicrophoneCapture:(MSIMEVoiceAudioBuffer)handler deviceUID:(NSString * _Nullable)deviceUID error:(NSError **)error;
- (void)stopMicrophoneCapture;
// Main-thread lifecycle; raw buffers are converted on the capture callback.
// Finish stops capture and returns one immutable recording; cancel discards it.
- (BOOL)startPCMRecording:(MSIMEVoiceAudioBuffer)handler deviceUID:(NSString * _Nullable)deviceUID error:(NSError **)error;
// Conversion failure cancels capture and delivers failure once on main, only
// while this recording still owns the service. No audio is included in errors.
- (BOOL)startPCMRecording:(MSIMEVoiceAudioBuffer)handler deviceUID:(NSString * _Nullable)deviceUID failure:(void (^ _Nullable)(NSError *))failure error:(NSError **)error;
- (NSData * _Nullable)finishPCMRecordingWithError:(NSError **)error;
// Main-thread lifecycle. Handler runs on the capture callback, must return
// promptly and must not stop/destroy capture; dispatch host cancellation to main.
// Each chunk is immutable mono 16 kHz float PCM. An error is delivered once.
// Finish stops capture and returns only the not-yet-delivered converter tail.
- (BOOL)startPCMStreaming:(MSIMEVoicePCMChunk)handler deviceUID:(NSString * _Nullable)deviceUID error:(NSError **)error;
- (NSData * _Nullable)finishPCMStreamingWithError:(NSError **)error;
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
