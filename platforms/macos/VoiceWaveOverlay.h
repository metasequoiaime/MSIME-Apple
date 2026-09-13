#pragma once
#import <Cocoa/Cocoa.h>
@interface MSIMEVoiceWaveOverlay : NSPanel
- (void)setListening:(BOOL)listening;
- (void)setInputLevel:(float)level;
@end
