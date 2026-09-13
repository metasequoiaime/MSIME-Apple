#import "VoiceWaveOverlay.h"
@interface MSIMEVoiceWaveView : NSView
@property(nonatomic) float level;
@property(nonatomic) BOOL listening;
@end
@implementation MSIMEVoiceWaveView
- (void)drawRect:(NSRect)r { (void)r; [[NSColor colorWithWhite:0 alpha:.88] setFill]; NSRectFill(self.bounds); [[NSColor systemBlueColor] setFill]; CGFloat h=MAX(3, MIN(self.bounds.size.height-8, self.level*(self.bounds.size.height-8))); NSRectFill(NSMakeRect(self.bounds.size.width/2-3, (self.bounds.size.height-h)/2, 6, h)); }
@end
@implementation MSIMEVoiceWaveOverlay { MSIMEVoiceWaveView *_view; }
- (instancetype)init { self=[super initWithContentRect:NSMakeRect(0,0,42,42) styleMask:NSWindowStyleMaskBorderless backing:NSBackingStoreBuffered defer:NO]; if(self){ self.opaque=NO; self.backgroundColor=NSColor.clearColor; self.level=NSFloatingWindowLevel; self.ignoresMouseEvents=YES; self.floatingPanel=YES; self.hidesOnDeactivate=NO; _view=[MSIMEVoiceWaveView new]; self.contentView=_view; } return self; }
- (void)setListening:(BOOL)listening { _view.listening=listening; if(listening){ [self orderFront:nil]; } else [self orderOut:nil]; }
- (void)setInputLevel:(float)level { dispatch_async(dispatch_get_main_queue(), ^{ self->_view.level=MAX(0,MIN(1,level)); [self->_view setNeedsDisplay:YES]; }); }
@end
