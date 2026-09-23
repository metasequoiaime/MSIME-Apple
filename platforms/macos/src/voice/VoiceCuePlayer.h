#pragma once
#import <Foundation/Foundation.h>
@class NSSound;
// The product's cues ship in the bundle's Resources/audios, the same start.mp3/end.mp3 the Windows installer stages into assets\audios. Returns nil when the resource is absent.
NSURL *MSIMEVoiceCueResourceURL(NSBundle *bundle, BOOL start);
// Plays through NSSound, i.e. from the input method's own process, so muting other applications' audio can leave the cue audible.
@interface MSIMEVoiceCuePlayer : NSObject
- (instancetype)init;
- (instancetype)initWithBundle:(NSBundle *)bundle NS_DESIGNATED_INITIALIZER;
// YES when the bundled product cue loaded; NO means the system fallback sound is used instead.
@property(nonatomic, readonly) BOOL startCueIsBundled;
@property(nonatomic, readonly) BOOL stopCueIsBundled;
@property(nonatomic, readonly) NSSound *startSound;
@property(nonatomic, readonly) NSSound *stopSound;
- (void)playStartCue;
- (void)playStopCue;
@end
