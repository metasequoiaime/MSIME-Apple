#import "../VoiceWaveOverlay.h"
#include <cassert>

int main() {
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
        for (NSNumber *level in @[@0, @0.5, @1]) {
            [panel setInputLevel:level.floatValue];
        }
        NSDate *until = [NSDate dateWithTimeIntervalSinceNow:0.05];
        [NSRunLoop.currentRunLoop runUntilDate:until];
        assert([[panel.contentView valueForKey:@"level"] floatValue] == 1);
    }
    return 0;
}
