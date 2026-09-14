#import "VoiceWaveOverlay.h"
@interface MSIMEVoiceWaveView : NSView
@property(nonatomic) float level;
@property(nonatomic) BOOL listening;
@property(nonatomic, copy) NSString *status;
@end
@implementation MSIMEVoiceWaveView
- (void)drawRect:(NSRect)r {
    (void)r;
    [[NSColor colorWithWhite:0.08 alpha:.95] setFill];
    [[NSBezierPath bezierPathWithRoundedRect:self.bounds xRadius:10 yRadius:10] fill];
    [[NSColor systemBlueColor] setFill];
    CGFloat height = self.listening ? MAX(3, MIN(28, self.level * 28)) : 6;
    NSRectFill(NSMakeRect(16, (self.bounds.size.height - height) / 2, 6, height));
    [self.status drawInRect:NSMakeRect(34, 12, self.bounds.size.width - 42, 20)
        withAttributes:@{NSFontAttributeName:[NSFont systemFontOfSize:13], NSForegroundColorAttributeName:NSColor.whiteColor}];
}
@end
@implementation MSIMEVoiceWaveOverlay { MSIMEVoiceWaveView *_view; NSUInteger _presentationGeneration; }
- (instancetype)init {
    self = [super initWithContentRect:NSMakeRect(0,0,156,44)
        styleMask:NSWindowStyleMaskBorderless | NSWindowStyleMaskNonactivatingPanel backing:NSBackingStoreBuffered defer:NO];
    if (self) {
        self.opaque = NO; self.backgroundColor = NSColor.clearColor;
        self.level = NSFloatingWindowLevel; self.ignoresMouseEvents = YES;
        self.floatingPanel = YES; self.hidesOnDeactivate = NO;
        _view = [MSIMEVoiceWaveView new]; _view.status = @""; self.contentView = _view;
    }
    return self;
}
- (NSString *)statusText { return _view.status; }
- (void)showStatus:(NSString *)status listening:(BOOL)listening {
    ++_presentationGeneration;
    _view.listening = listening; _view.level = 0; _view.status = status;
    _view.accessibilityLabel = status; [_view setNeedsDisplay:YES];
    if (!status.length) { [self orderOut:nil]; return; }
    if (!self.visible) {
        NSRect screen = (NSScreen.mainScreen ?: NSScreen.screens.firstObject).visibleFrame;
        [self setFrameOrigin:NSMakePoint(NSMidX(screen) - self.frame.size.width / 2, NSMinY(screen) + 32)];
    }
    [self orderFront:nil];
}
- (void)setListening:(BOOL)listening { [self showStatus:listening ? @"正在录音…" : @"" listening:listening]; }
- (void)setProcessing:(BOOL)polishing { [self showStatus:polishing ? @"正在润色…" : @"正在识别…" listening:NO]; }
- (void)setInputLevel:(float)level {
    const NSUInteger generation = _presentationGeneration;
    dispatch_async(dispatch_get_main_queue(), ^{
        if (generation != self->_presentationGeneration || !self->_view.listening) return;
        self->_view.level = MAX(0,MIN(1,level)); [self->_view setNeedsDisplay:YES];
    });
}
@end
