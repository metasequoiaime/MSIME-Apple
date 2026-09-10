#pragma once
#import <AppKit/AppKit.h>

namespace metasequoia::mac {
inline bool ShouldPlayKeyFeedback(NSEvent *event, bool enabled)
{
    return enabled && event.type == NSEventTypeKeyDown && !event.isARepeat &&
        (event.modifierFlags & (NSEventModifierFlagCommand | NSEventModifierFlagControl | NSEventModifierFlagOption)) == 0;
}

// Called only after an Engine key action is handled, never for host passthrough.
inline void PlayHandledKeyFeedback(NSEvent *event)
{
    if (!ShouldPlayKeyFeedback(event, [NSUserDefaults.standardUserDefaults boolForKey:@"MetasequoiaImeKeySoundEnabled"])) return;
    static NSSound *sound = nil;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        sound = [NSSound soundNamed:@"Tink"];
        sound.volume = 0.15f;
    });
    if (!sound.isPlaying) [sound play];
}
} // namespace metasequoia::mac
