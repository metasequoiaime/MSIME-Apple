#pragma once
#import <Foundation/Foundation.h>

// Count presentation events without playing audio in native regression tests.
@interface MSIMEVoiceCueFixture : NSObject
@property NSUInteger starts;
@property NSUInteger stops;
@end
@implementation MSIMEVoiceCueFixture
- (void)playStartCue { ++self.starts; }
- (void)playStopCue { ++self.stops; }
@end
