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
    NSRectFill(NSMakeRect(16, self.bounds.size.height - 22 - height / 2, 6, height));
    [self.status drawInRect:NSMakeRect(34, self.bounds.size.height - 32, self.bounds.size.width - 42, 20)
        withAttributes:@{NSFontAttributeName:[NSFont systemFontOfSize:13], NSForegroundColorAttributeName:NSColor.whiteColor}];
}
@end
@implementation MSIMEVoiceWaveOverlay {
    MSIMEVoiceWaveView *_view;
    NSScrollView *_transcriptScroll;
    NSTextView *_transcriptView;
    NSUInteger _presentationGeneration;
    BOOL _showingFailure;
    BOOL _dismissed;
    NSButton *_cancelButton;
    NSButton *_confirmButton;
}
- (instancetype)init {
    self = [super initWithContentRect:NSMakeRect(0,0,156,44)
        styleMask:NSWindowStyleMaskBorderless | NSWindowStyleMaskNonactivatingPanel backing:NSBackingStoreBuffered defer:NO];
    if (self) {
        self.opaque = NO; self.backgroundColor = NSColor.clearColor;
        self.level = NSFloatingWindowLevel; self.ignoresMouseEvents = YES;
        self.floatingPanel = YES; self.hidesOnDeactivate = NO;
        _view = [MSIMEVoiceWaveView new]; _view.status = @""; self.contentView = _view;
        _transcriptScroll = [[NSScrollView alloc] initWithFrame:NSZeroRect];
        _transcriptScroll.drawsBackground = NO; _transcriptScroll.hasVerticalScroller = YES;
        _transcriptScroll.autohidesScrollers = YES; _transcriptScroll.hidden = YES;
        _transcriptView = [[NSTextView alloc] initWithFrame:NSMakeRect(0,0,340,120)];
        _transcriptView.editable = NO; _transcriptView.selectable = NO;
        _transcriptView.richText = NO; _transcriptView.drawsBackground = NO;
        _transcriptView.textColor = NSColor.whiteColor; _transcriptView.font = [NSFont systemFontOfSize:13];
        _transcriptView.verticallyResizable = YES; _transcriptView.horizontallyResizable = NO;
        _transcriptView.autoresizingMask = NSViewWidthSizable;
        _transcriptView.textContainer.widthTracksTextView = YES;
        _transcriptView.textContainer.containerSize = NSMakeSize(340, CGFLOAT_MAX);
        _transcriptView.maxSize = NSMakeSize(CGFLOAT_MAX, CGFLOAT_MAX);
        _transcriptScroll.documentView = _transcriptView; [_view addSubview:_transcriptScroll];
        _cancelButton = [NSButton buttonWithTitle:@"取消" target:self action:@selector(cancelVoice:)];
        _confirmButton = [NSButton buttonWithTitle:@"确认" target:self action:@selector(confirmVoice:)];
        for (NSButton *button in @[_cancelButton, _confirmButton]) {
            button.hidden = YES; button.refusesFirstResponder = YES;
            button.appearance = [NSAppearance appearanceNamed:NSAppearanceNameDarkAqua];
            button.contentTintColor = NSColor.whiteColor;
            [_view addSubview:button];
        }
    }
    return self;
}
- (NSString *)statusText { return _view.status; }
- (NSString *)transcriptText { return _transcriptView.string; }
- (BOOL)canBecomeKeyWindow { return NO; }
- (BOOL)canBecomeMainWindow { return NO; }
- (void)setActionHandler:(void (^)(BOOL))handler {
    _actionHandler = [handler copy];
    [self layoutPresentation];
}
- (void)cancelVoice:(id)sender {
    (void)sender;
    if (self.visible && !_showingFailure && !_dismissed && self.actionHandler) self.actionHandler(YES);
}
- (void)confirmVoice:(id)sender {
    (void)sender;
    if (self.visible && !_showingFailure && !_dismissed && self.actionHandler) self.actionHandler(NO);
}
- (void)dismissProcessing {
    _dismissed = YES;
    ++_presentationGeneration;
    [self orderOut:nil];
}
- (void)layoutPresentation {
    const BOOL transcript = _transcriptView.string.length > 0;
    const BOOL actions = self.actionHandler && _view.status.length && !_showingFailure && !_dismissed;
    NSRect frame = self.frame;
    CGFloat center = NSMidX(frame);
    frame.size.width = MAX(transcript ? 380 : actions ? 220 : 156, ceil([_view.status sizeWithAttributes:@{NSFontAttributeName:[NSFont systemFontOfSize:13]}].width) + 50);
    frame.size.height = (transcript ? 180 : 44) + (actions ? 36 : 0);
    frame.origin.x = center - frame.size.width / 2;
    [self setFrame:frame display:NO];
    _transcriptScroll.hidden = !transcript;
    _transcriptScroll.frame = NSMakeRect(12, actions ? 48 : 12, frame.size.width - 24, transcript ? 124 : 0);
    _cancelButton.hidden = _confirmButton.hidden = !actions;
    _cancelButton.frame = NSMakeRect(frame.size.width - 156, 8, 68, 28);
    _confirmButton.frame = NSMakeRect(frame.size.width - 80, 8, 68, 28);
    // Buttons and the scrollable preview handle pointer events; this panel still
    // cannot become key/main or redirect typing away from the IMK client.
    self.ignoresMouseEvents = !transcript && !actions;
    [_view setNeedsDisplay:YES];
}
- (void)setTranscript:(NSString *)text {
    if (!self.visible || _showingFailure || ![text isKindOfClass:NSString.class] || text.length > 65536) return;
    _transcriptView.string = [text copy];
    [self layoutPresentation];
    [_transcriptView scrollRangeToVisible:NSMakeRange(text.length, 0)];
}
- (void)showStatus:(NSString *)status listening:(BOOL)listening {
    ++_presentationGeneration;
    _showingFailure = NO;
    _view.listening = listening; _view.level = 0; _view.status = status;
    _view.accessibilityLabel = status; [_view setNeedsDisplay:YES];
    [self layoutPresentation];
    if (!status.length || _dismissed) { [self orderOut:nil]; return; }
    if (!self.visible) {
        NSRect screen = (NSScreen.mainScreen ?: NSScreen.screens.firstObject).visibleFrame;
        [self setFrameOrigin:NSMakePoint(NSMidX(screen) - self.frame.size.width / 2, NSMinY(screen) + 32)];
    }
    [self orderFront:nil];
}
- (void)setListening:(BOOL)listening {
    if (listening) _dismissed = NO;
    else self.actionHandler = nil;
    _transcriptView.string = @"";
    [self showStatus:listening ? @"正在录音…" : @"" listening:listening];
}
- (void)setProcessing:(BOOL)polishing { [self showStatus:polishing ? @"正在润色…" : @"正在识别…" listening:NO]; }
- (NSTimeInterval)failureDisplayDuration { return 6; }
- (void)showFailure:(MSIMEVoiceFailure)failure {
    self.actionHandler = nil;
    _dismissed = NO;
    _transcriptView.string = @"";
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
