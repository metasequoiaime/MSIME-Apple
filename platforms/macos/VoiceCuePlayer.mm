#import "VoiceCuePlayer.h"
#import <AppKit/AppKit.h>
@implementation MSIMEVoiceCuePlayer
- (void)playStartCue { NSSound *sound = [NSSound soundNamed:@"Glass"]; [sound play]; }
- (void)playStopCue { NSSound *sound = [NSSound soundNamed:@"Pop"]; [sound play]; }
@end
