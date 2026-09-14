#pragma once
#import <Cocoa/Cocoa.h>
typedef NS_ENUM(NSUInteger, MSIMEVoiceFailure) {
    MSIMEVoiceFailureMicrophonePermission = 1,
    MSIMEVoiceFailureSpeechPermission,
    MSIMEVoiceFailureCapture,
    MSIMEVoiceFailureProvider,
    MSIMEVoiceFailureNoSpeech,
    MSIMEVoiceFailureTimeout,
    MSIMEVoiceFailureSession
};
@interface MSIMEVoiceWaveOverlay : NSPanel
// Host presentation only; all calls are made on the main thread.
@property(nonatomic, copy) void (^actionHandler)(BOOL cancel);
- (void)dismissProcessing;
- (void)setListening:(BOOL)listening;
- (void)setProcessing:(BOOL)polishing;
- (void)showFailure:(MSIMEVoiceFailure)failure;
- (void)dismissFailure;
- (void)setInputLevel:(float)level;
- (void)setTranscript:(NSString *)text;
@property(nonatomic, readonly, copy) NSString *statusText;
@property(nonatomic, readonly, copy) NSString *transcriptText;
@end
