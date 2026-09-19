#pragma once
#import <AppKit/AppKit.h>

// Stands in for the IMK client the controller talks to. A bare NSObject used to be enough, and then reportVoiceFailure: started asking the client where the caret is so the overlay can pick a screen - which an NSObject answers by raising. Report an empty caret: the controller reads that as "no usable position" and leaves the overlay on its current screen, which is what a test wants.
@interface MSIMEVoiceClientFixture : NSObject
@property(nonatomic) NSRect caret;
@end

@implementation MSIMEVoiceClientFixture
- (NSDictionary *)attributesForCharacterIndex:(NSUInteger)index lineHeightRectangle:(NSRect *)rectangle
{
    (void)index;
    if (rectangle) *rectangle = self.caret;
    return @{};
}
@end
