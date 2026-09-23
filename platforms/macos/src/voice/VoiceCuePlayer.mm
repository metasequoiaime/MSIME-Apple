#import "VoiceCuePlayer.h"
#import <AppKit/AppKit.h>
NSURL *MSIMEVoiceCueResourceURL(NSBundle *bundle, BOOL start) {
    return [bundle URLForResource:start ? @"start" : @"end" withExtension:@"mp3" subdirectory:@"audios"];
}
static NSSound *MSIMEVoiceCueSound(NSBundle *bundle, BOOL start, BOOL *bundled) {
    NSURL *url = MSIMEVoiceCueResourceURL(bundle, start);
    NSSound *sound = url ? [[NSSound alloc] initWithContentsOfURL:url byReference:NO] : nil;
    *bundled = sound != nil;
    if (sound) return sound;
    // A bundle staged without the product cues (or with an undecodable file) still gives audible start/stop feedback rather than none.
    NSLog(@"MSIME voice %@ cue is missing from the bundle; using the system sound", start ? @"start" : @"end");
    return [[NSSound soundNamed:start ? @"Glass" : @"Pop"] copy];
}
// NSSound refuses to play a sound that is already playing; stopping first restarts it from the beginning, matching the Windows stop/seek-to-zero/start.
static void MSIMEVoiceCueRestart(NSSound *sound) {
    [sound stop];
    [sound play];
}
@implementation MSIMEVoiceCuePlayer
- (instancetype)init { return [self initWithBundle:NSBundle.mainBundle]; }
- (instancetype)initWithBundle:(NSBundle *)bundle {
    self = [super init];
    if (self) {
        // Loaded once, as the Windows CuePlayer does in init, so a cue never waits on decoding at the moment recording starts.
        _startSound = MSIMEVoiceCueSound(bundle, YES, &_startCueIsBundled);
        _stopSound = MSIMEVoiceCueSound(bundle, NO, &_stopCueIsBundled);
    }
    return self;
}
- (void)playStartCue { MSIMEVoiceCueRestart(_startSound); }
- (void)playStopCue { MSIMEVoiceCueRestart(_stopSound); }
@end
