#import "../VoiceWaveOverlay.h"
#include <cassert>

@interface BriefFailureOverlay : MSIMEVoiceWaveOverlay
@end
@implementation BriefFailureOverlay
- (NSTimeInterval)failureDisplayDuration { return 0.02; }
@end

int main(int argc, char **argv) {
    @autoreleasepool {
        [NSApplication sharedApplication];
        MSIMEVoiceWaveOverlay *panel = [MSIMEVoiceWaveOverlay new];
        assert(panel != nil);
        assert(panel.level == NSFloatingWindowLevel);
        assert(panel.ignoresMouseEvents);
        assert(!panel.isOpaque);
        assert(!panel.canBecomeKeyWindow);
        assert(!panel.canBecomeMainWindow);
        assert(panel.contentView != nil);
        assert(!panel.isVisible);
        [panel setListening:NO];
        assert(!panel.isVisible);
        // Synthetic levels exercise the main-queue update without microphone access.
        [panel setListening:YES];
        assert([panel.statusText isEqual:@"正在录音…"]);
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
        assert([panel.contentView.accessibilityLabel isEqual:panel.statusText]);
        if (argc == 2) {
            NSBitmapImageRep *bitmap = [panel.contentView bitmapImageRepForCachingDisplayInRect:panel.contentView.bounds];
            [panel.contentView cacheDisplayInRect:panel.contentView.bounds toBitmapImageRep:bitmap];
            assert([[bitmap representationUsingType:NSBitmapImageFileTypePNG properties:@{}] writeToFile:@(argv[1]) atomically:YES]);
        }
        assert(!panel.canBecomeKeyWindow && !panel.canBecomeMainWindow);
        [panel setListening:NO];
        assert(!panel.visible && !panel.statusText.length);
        for (NSUInteger failure = MSIMEVoiceFailureMicrophonePermission; failure <= MSIMEVoiceFailureSession; ++failure) {
            [panel showFailure:(MSIMEVoiceFailure)failure];
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
