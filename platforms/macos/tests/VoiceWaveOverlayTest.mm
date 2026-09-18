#import "../src/VoiceWaveOverlay.h"
#include <cassert>
#include <cmath>

@interface BriefFailureOverlay : MSIMEVoiceWaveOverlay
@end
@implementation BriefFailureOverlay
- (NSTimeInterval)failureDisplayDuration { return 0.02; }
@end

int main(int argc, char **argv) {
    @autoreleasepool {
        [NSApplication sharedApplication];
        const NSRect syntheticFullScreen = NSMakeRect(-1440, 0, 1440, 900);
        const NSRect syntheticWorkArea = NSMakeRect(-1360, 40, 1360, 860);
        const NSPoint centered = MSIMEVoiceWaveOverlayOriginForFrames(syntheticFullScreen, syntheticWorkArea, NSMakeSize(220, 44));
        assert(std::abs(centered.x - (-830.0)) < 0.01);
        assert(std::abs(centered.y - 72.0) < 0.01);
        // A left-side Dock narrows the work area but must not move the
        // horizontal center away from the physical monitor center.
        const NSPoint rightDock = MSIMEVoiceWaveOverlayOriginForFrames(
            NSMakeRect(0, 0, 1440, 900), NSMakeRect(0, 0, 1360, 900), NSMakeSize(220, 44));
        assert(std::abs(rightDock.x - 610.0) < 0.01);
        const NSPoint oversized = MSIMEVoiceWaveOverlayOriginForFrames(syntheticFullScreen, syntheticWorkArea, NSMakeSize(1800, 1000));
        assert(std::abs(oversized.x - NSMinX(syntheticFullScreen)) < 0.01);
        assert(std::abs(oversized.y - NSMinY(syntheticWorkArea)) < 0.01);
        MSIMEVoiceWaveOverlay *panel = [MSIMEVoiceWaveOverlay new];
        assert(panel != nil);
        assert(panel.level == NSFloatingWindowLevel);
        assert(panel.ignoresMouseEvents);
        assert(!panel.isOpaque);
        assert(!panel.canBecomeKeyWindow);
        assert(!panel.canBecomeMainWindow);
        assert(panel.contentView != nil);
        assert(!panel.isVisible);
        panel.preferredScreen = NSScreen.mainScreen;
        assert(panel.preferredScreen == NSScreen.mainScreen);
        [panel applyThemePreferences:@{@"theme": @"light", @"voice_theme": @"dark"}];
        assert(!panel.isLightTheme && panel.appearance != nil);
        [panel applyThemePreferences:@{@"theme": @"dark", @"voice_theme": @"light"}];
        assert(panel.isLightTheme && panel.appearance != nil);
        [panel applyThemePreferences:@{@"theme": @"system", @"voice_theme": @"follow"}];
        assert(panel.appearance == nil);
        [panel applyThemePreferences:@{@"theme": @"dark", @"voice_theme": @"invalid"}];
        assert(!panel.isLightTheme && panel.appearance != nil);
        __block NSUInteger cancels = 0, confirms = 0;
        panel.actionHandler = ^(BOOL cancel) { if (cancel) ++cancels; else ++confirms; };
        [panel setListening:YES];
        NSButton *cancelButton = [panel valueForKey:@"cancelButton"];
        NSButton *confirmButton = [panel valueForKey:@"confirmButton"];
        assert(!cancelButton.hidden && !confirmButton.hidden && !panel.ignoresMouseEvents);
        [cancelButton performClick:nil]; [confirmButton performClick:nil];
        assert(cancels == 1 && confirms == 1);
        assert(!panel.canBecomeKeyWindow && !panel.canBecomeMainWindow);
        [panel setProcessing:NO]; [panel dismissProcessing]; [panel setProcessing:YES];
        [panel setTranscript:@"synthetic dismissed preview"];
        assert(!panel.visible && !panel.transcriptText.length);
        [confirmButton performClick:nil]; assert(confirms == 1);
        [panel setListening:YES];
        assert(panel.visible && !confirmButton.hidden);
        [panel showFailure:MSIMEVoiceFailureProvider];
        assert(cancelButton.hidden && confirmButton.hidden && !panel.actionHandler);
        [panel setListening:NO];
        assert(!panel.isVisible);
        // Synthetic levels exercise the main-queue update without microphone access.
        [panel setListening:YES];
        assert([panel.statusText isEqual:@"正在录音…"]);
        NSMutableString *preview = [@"合成预览文本，仅用于测试。\nEnglish preview · 日本語 · 🙂" mutableCopy];
        [panel setTranscript:preview];
        [preview appendString:@"changed outside the overlay"];
        assert(![panel.transcriptText containsString:@"changed outside"]);
        assert(panel.frame.size.width >= 380 && panel.frame.size.height == 180);
        assert(!panel.ignoresMouseEvents && !panel.canBecomeKeyWindow && !panel.canBecomeMainWindow);
        for (NSNumber *level in @[@0, @0.5, @1]) {
            [panel setInputLevel:level.floatValue];
        }
        NSDate *until = [NSDate dateWithTimeIntervalSinceNow:0.05];
        [NSRunLoop.currentRunLoop runUntilDate:until];
        assert([[panel.contentView valueForKey:@"level"] floatValue] == 1);
        [panel setInputLevel:1]; // A queued meter update must not revive processing UI.
        [panel setProcessing:NO];
        assert(panel.visible && [panel.statusText isEqual:@"正在识别…"]);
        [NSRunLoop.currentRunLoop runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.03]];
        assert([[panel.contentView valueForKey:@"level"] floatValue] == 0);
        [panel setProcessing:YES];
        assert(panel.visible && [panel.statusText isEqual:@"正在润色…"]);
        assert([panel.transcriptText containsString:@"合成预览"]);
        assert([panel.contentView.accessibilityLabel isEqual:panel.statusText]);
        if (argc == 2) {
            panel.actionHandler = ^(BOOL) {};
            NSBitmapImageRep *bitmap = [panel.contentView bitmapImageRepForCachingDisplayInRect:panel.contentView.bounds];
            [panel.contentView cacheDisplayInRect:panel.contentView.bounds toBitmapImageRep:bitmap];
            assert([[bitmap representationUsingType:NSBitmapImageFileTypePNG properties:@{}] writeToFile:@(argv[1]) atomically:YES]);
            panel.actionHandler = nil;
        }
        assert(!panel.canBecomeKeyWindow && !panel.canBecomeMainWindow);
        NSString *longPreview = [@"合成滚动文本\n" stringByPaddingToLength:5000 withString:@"合成滚动文本\n" startingAtIndex:0];
        [panel setTranscript:longPreview];
        NSScrollView *scroll = [panel valueForKey:@"transcriptScroll"];
        assert([panel.transcriptText isEqual:longPreview] && scroll.documentVisibleRect.origin.y > 0);
        assert(![(NSTextView *)scroll.documentView isEditable] && ![(NSTextView *)scroll.documentView isSelectable]);
        [panel setTranscript:[@"x" stringByPaddingToLength:65537 withString:@"x" startingAtIndex:0]];
        assert([panel.transcriptText isEqual:longPreview]);
        [panel setListening:NO];
        assert(!panel.visible && !panel.statusText.length);
        assert(!panel.transcriptText.length && panel.ignoresMouseEvents && panel.frame.size.height == 44);
        [panel setTranscript:@"late preview"];
        assert(!panel.visible && !panel.transcriptText.length);
        for (NSUInteger failure = MSIMEVoiceFailureMicrophonePermission; failure <= MSIMEVoiceFailureSession; ++failure) {
            [panel setListening:YES]; [panel setTranscript:@"synthetic discard on failure"];
            [panel showFailure:(MSIMEVoiceFailure)failure];
            [panel setTranscript:@"late preview during failure"];
            assert(!panel.transcriptText.length);
            assert(panel.visible && panel.statusText.length);
            CGFloat textWidth = [panel.statusText sizeWithAttributes:@{NSFontAttributeName:[NSFont systemFontOfSize:13]}].width;
            assert(textWidth <= panel.contentView.bounds.size.width - 42);
            assert([panel.contentView.accessibilityLabel isEqual:panel.statusText]);
            [panel dismissFailure]; assert(!panel.visible);
        }
        BriefFailureOverlay *brief = [BriefFailureOverlay new];
        [brief showFailure:MSIMEVoiceFailureCapture];
        [NSRunLoop.currentRunLoop runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.05]];
        assert(!brief.visible);
        [brief showFailure:MSIMEVoiceFailureProvider];
        [brief setListening:YES];
        [NSRunLoop.currentRunLoop runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.05]];
        assert(brief.visible && [brief.statusText isEqual:@"正在录音…"]);
        [brief dismissFailure]; assert(brief.visible);
        [brief setListening:NO];
        [panel setListening:YES];
        assert([panel.statusText isEqual:@"正在录音…"]);
        [panel setListening:NO];
    }
    return 0;
}
