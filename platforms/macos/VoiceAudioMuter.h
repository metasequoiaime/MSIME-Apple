#pragma once
#import <Foundation/Foundation.h>
@interface MSIMEVoiceAudioMuter : NSObject
- (BOOL)mute:(NSError **)error;
- (void)restore;
@end
