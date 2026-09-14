#pragma once
#import <Cocoa/Cocoa.h>
@interface MSIMEVoiceWaveOverlay : NSPanel
// Host presentation only; all calls are made on the main thread.
- (void)setListening:(BOOL)listening;
- (void)setProcessing:(BOOL)polishing;
- (void)setInputLevel:(float)level;
@property(nonatomic, readonly, copy) NSString *statusText;
@end
