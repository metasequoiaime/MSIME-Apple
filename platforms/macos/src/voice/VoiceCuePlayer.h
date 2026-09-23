#pragma once
#import <Foundation/Foundation.h>
@class NSSound;
// The product's cues ship in the bundle's Resources/audios, the same start.mp3/end.mp3 the Windows installer stages into assets\audios. Returns nil when the resource is absent.
NSURL *MSIMEVoiceCueResourceURL(NSBundle *bundle, BOOL start);
// Plays through NSSound in the input method process. The system-audio mute is device-wide, so the controller mutes only after playStartCueThen: reports the start cue finished, and restores before the stop cue plays.
@interface MSIMEVoiceCuePlayer : NSObject
- (instancetype)init;
- (instancetype)initWithBundle:(NSBundle *)bundle NS_DESIGNATED_INITIALIZER;
// YES when the bundled product cue loaded; NO means the system fallback sound is used instead.
@property(nonatomic, readonly) BOOL startCueIsBundled;
@property(nonatomic, readonly) BOOL stopCueIsBundled;
@property(nonatomic, readonly) NSSound *startSound;
@property(nonatomic, readonly) NSSound *stopSound;
- (void)playStartCue;
// Runs `completion` once on the main thread after the start cue has finished playing, or right away when it cannot play. Restarting the cue drops a completion that has not run yet.
- (void)playStartCueThen:(void (^)(void))completion;
- (void)playStopCue;
@end
