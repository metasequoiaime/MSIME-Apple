#pragma once
#import <Cocoa/Cocoa.h>

/// Return a clamped origin that centers the overlay horizontally on the full screen and sits it 10 points above the bottom of the screen's visible work area, as MSIME-Windows `update_window_bounds` does. This is kept pure so the positioning contract can be tested without opening a real window.
FOUNDATION_EXPORT NSPoint MSIMEVoiceWaveOverlayOriginForFrames(NSRect fullFrame, NSRect visibleFrame, NSSize panelSize);

/// The four presentations of MSIME-Windows `wave_overlay.cpp`, in its precedence order: the round actions win over a status label, which wins over the transcript.
typedef NS_ENUM(NSUInteger, MSIMEVoiceWaveOverlayLayout) {
    MSIMEVoiceWaveOverlayLayoutCompact = 0,
    MSIMEVoiceWaveOverlayLayoutProcessing,
    MSIMEVoiceWaveOverlayLayoutAction,
    MSIMEVoiceWaveOverlayLayoutTranscript
};
FOUNDATION_EXPORT MSIMEVoiceWaveOverlayLayout MSIMEVoiceWaveOverlayLayoutFor(BOOL actionsVisible, BOOL hasStatusLabel, BOOL hasTranscript);
/// Sizes in points: compact 78x32, processing 112x40, action 142x40, transcript 420x112.
FOUNDATION_EXPORT NSSize MSIMEVoiceWaveOverlaySizeForLayout(MSIMEVoiceWaveOverlayLayout layout);

enum { MSIMEVoiceWaveBarCount = 12 };
/// Advance the 12 bar levels by one 16 ms animation frame with the source's multi-harmonic motion. `seconds` is a monotonic clock; `inputLevel` is clamped to 0...1. Levels stay within 0...1 and settle back to 0 (dots) once `listening` is NO or the input is silent.
FOUNDATION_EXPORT void MSIMEVoiceWaveAdvanceLevels(float levels[MSIMEVoiceWaveBarCount], float inputLevel, BOOL listening, double seconds);

/// Keep the newest text that fits in `maxLines`: when the whole transcript does not fit, the oldest text is dropped behind a leading "…". `lineCount` measures a candidate string; the cut never splits a composed character sequence.
FOUNDATION_EXPORT NSString *MSIMEVoiceTranscriptVisibleText(NSString *transcript, NSUInteger maxLines, NSUInteger (^lineCount)(NSString *candidate));
/// Number of wrapped lines `text` takes in `font` at `width` points.
FOUNDATION_EXPORT NSUInteger MSIMEVoiceTranscriptLineCount(NSString *text, NSFont *font, CGFloat width);

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
/// The round cancel and confirm buttons appear only while the recording is locked (`setRecordingLocked:`) or while recognition or polishing is pending, and only when a handler is set.
@property(nonatomic, copy) void (^actionHandler)(BOOL cancel);
/// The screen containing the active IMK caret.  A nil or detached screen
/// falls back to the current main screen; AppKit points already account for
/// that screen's scale factor.
@property(nonatomic, weak) NSScreen *preferredScreen;
- (void)applyThemePreferences:(NSDictionary *)preferences;
- (BOOL)isLightTheme;
- (void)dismissProcessing;
- (void)setListening:(BOOL)listening;
/// The hold shortcut was locked with Space: recording continues after release, so the actions are shown. Ignored unless recording; `setListening:` clears it.
- (void)setRecordingLocked:(BOOL)locked;
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
