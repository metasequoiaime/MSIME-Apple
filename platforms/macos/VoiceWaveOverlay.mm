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
@implementation MSIMEVoiceWaveOverlay { MSIMEVoiceWaveView *_view; NSUInteger _presentationGeneration; BOOL _showingFailure; }
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
    _showingFailure = NO;
    _view.listening = listening; _view.level = 0; _view.status = status;
    _view.accessibilityLabel = status; [_view setNeedsDisplay:YES];
    if (!status.length) { [self orderOut:nil]; return; }
    NSRect frame = self.frame;
    CGFloat center = NSMidX(frame);
    frame.size.width = MAX(156, ceil([status sizeWithAttributes:@{NSFontAttributeName:[NSFont systemFontOfSize:13]}].width) + 50);
    frame.origin.x = center - frame.size.width / 2;
    [self setFrame:frame display:NO];
    if (!self.visible) {
        NSRect screen = (NSScreen.mainScreen ?: NSScreen.screens.firstObject).visibleFrame;
        [self setFrameOrigin:NSMakePoint(NSMidX(screen) - self.frame.size.width / 2, NSMinY(screen) + 32)];
    }
    [self orderFront:nil];
}
- (void)setListening:(BOOL)listening { [self showStatus:listening ? @"正在录音…" : @"" listening:listening]; }
- (void)setProcessing:(BOOL)polishing { [self showStatus:polishing ? @"正在润色…" : @"正在识别…" listening:NO]; }
- (NSTimeInterval)failureDisplayDuration { return 6; }
- (void)showFailure:(MSIMEVoiceFailure)failure {
    // Never surface raw transport errors, transcripts, URLs or credentials.
    NSString *message;
    switch (failure) {
        case MSIMEVoiceFailureMicrophonePermission: message = @"请在系统设置允许麦克风访问"; break;
        case MSIMEVoiceFailureSpeechPermission: message = @"请在系统设置允许语音识别"; break;
        case MSIMEVoiceFailureCapture: message = @"录音失败，请检查麦克风设置"; break;
        case MSIMEVoiceFailureProvider: message = @"识别失败，请检查语音服务设置"; break;
        case MSIMEVoiceFailureNoSpeech: message = @"未识别到语音，请重试"; break;
        case MSIMEVoiceFailureTimeout: message = @"语音处理超时，请重试"; break;
        default: message = @"语音输入未能启动，请重试"; break;
    }
    [self showStatus:message listening:NO];
    _showingFailure = YES;
    const NSUInteger generation = _presentationGeneration;
    __weak MSIMEVoiceWaveOverlay *weakSelf = self;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)([self failureDisplayDuration] * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        MSIMEVoiceWaveOverlay *panel = weakSelf;
        if (panel && panel->_presentationGeneration == generation) [panel dismissFailure];
    });
}
- (void)dismissFailure { if (_showingFailure) [self setListening:NO]; }
- (void)setInputLevel:(float)level {
    const NSUInteger generation = _presentationGeneration;
    dispatch_async(dispatch_get_main_queue(), ^{
        if (generation != self->_presentationGeneration || !self->_view.listening) return;
        self->_view.level = MAX(0,MIN(1,level)); [self->_view setNeedsDisplay:YES];
    });
}
@end
