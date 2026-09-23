#pragma once
#import <Foundation/Foundation.h>

// Count presentation events without playing audio in native regression tests.
@interface MSIMEVoiceCueFixture : NSObject
@property NSUInteger starts;
@property NSUInteger stops;
// The completion handed to the latest start cue; tests run it to model the cue finishing.
@property(copy) void (^startCompletion)(void);
@end
@implementation MSIMEVoiceCueFixture
- (void)playStartCue { [self playStartCueThen:nil]; }
- (void)playStartCueThen:(void (^)(void))completion { ++self.starts; self.startCompletion = completion; }
- (void)playStopCue { ++self.stops; }
@end
