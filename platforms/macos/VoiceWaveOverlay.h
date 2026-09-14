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
- (void)setListening:(BOOL)listening;
- (void)setProcessing:(BOOL)polishing;
- (void)showFailure:(MSIMEVoiceFailure)failure;
- (void)dismissFailure;
- (void)setInputLevel:(float)level;
@property(nonatomic, readonly, copy) NSString *statusText;
@end
