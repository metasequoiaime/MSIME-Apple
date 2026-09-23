#pragma once
#import <Cocoa/Cocoa.h>

/// Return a clamped origin that centers the overlay in a screen's visible
/// work area while leaving a small bottom breathing room.  This is kept pure
/// so the positioning contract can be tested without opening a real window.
FOUNDATION_EXPORT NSPoint MSIMEVoiceWaveOverlayOriginForFrames(NSRect fullFrame, NSRect visibleFrame, NSSize panelSize);

typedef NS_ENUM(NSUInteger, MSIMEVoiceFailure) {
    MSIMEVoiceFailureMicrophonePermission = 1,
    MSIMEVoiceFailureSpeechPermission,
    MSIMEVoiceFailureCapture,
    MSIMEVoiceFailureProvider,
    MSIMEVoiceFailureNoSpeech,
    MSIMEVoiceFailureTimeout,
    MSIMEVoiceFailureSession,
    MSIMEVoiceFailureMissingToken
};
@interface MSIMEVoiceWaveOverlay : NSPanel
// Host presentation only; all calls are made on the main thread.
@property(nonatomic, copy) void (^actionHandler)(BOOL cancel);
/// The screen containing the active IMK caret.  A nil or detached screen
/// falls back to the current main screen; AppKit points already account for
/// that screen's scale factor.
@property(nonatomic, weak) NSScreen *preferredScreen;
- (void)applyThemePreferences:(NSDictionary *)preferences;
- (BOOL)isLightTheme;
- (void)dismissProcessing;
- (void)setListening:(BOOL)listening;
- (void)setProcessing:(BOOL)polishing;
- (void)showFailure:(MSIMEVoiceFailure)failure;
/// `detail` is the provider's own account of the failure, as MSIME-Windows shows it: the status line keeps the category's fixed message and the detail takes the transcript area. Nil or empty shows the category alone.
- (void)showFailure:(MSIMEVoiceFailure)failure detail:(NSString *)detail;
- (void)dismissFailure;
- (void)setInputLevel:(float)level;
- (void)setTranscript:(NSString *)text;
@property(nonatomic, readonly, copy) NSString *statusText;
@property(nonatomic, readonly, copy) NSString *transcriptText;
@end
