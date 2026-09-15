#pragma once
#import <AppKit/AppKit.h>
#import "CandidateTypography.h"
// Drawing adapted from MSIME-Apple b637828e15eafcb5e459edd270a962dd14517285.
static const CGFloat MSIMECandidateTranslationOpacity = 0.62;

@interface MSIMECandidateButton : NSButton
@property(nonatomic, copy) NSDictionary *candidateID;
@property(nonatomic, strong) NSFont *numberFont;
@property(nonatomic) BOOL candidateHighlighted;
@property(nonatomic) BOOL candidateFixed;
@property(nonatomic, copy) NSString *translation;
@property(nonatomic, strong) NSFont *translationFont;
@property(nonatomic, copy) NSColor *translationColor;
@property(nonatomic) BOOL translationBelow;
@property(nonatomic) CGFloat translationRowHeight;
@property(nonatomic, copy) NSColor *fillColor;
@property(nonatomic, copy) NSColor *hoverColor;
@property(nonatomic, copy) NSColor *titleColor;
@property(nonatomic, copy) NSColor *numberColor;
@property(nonatomic, copy) NSColor *barColor;
@property(nonatomic) BOOL showSelectedBar;
@property(nonatomic) BOOL candidateHovered;
@end
@implementation MSIMECandidateButton
{
    NSTrackingArea *_candidateTrackingArea;
}
- (BOOL)acceptsFirstResponder
{
    return NO;
}
- (BOOL)acceptsFirstMouse:(NSEvent *)event
{
    (void)event;
    return YES;
}
- (void)resetCursorRects
{
    // Candidate rows are actionable surfaces. Keep the native macOS pointer
    // affordance used by the retained Apple panel while leaving keyboard focus
    // disabled for IMK input routing.
    [self addCursorRect:self.bounds cursor:NSCursor.pointingHandCursor];
}
- (void)updateTrackingAreas
{
    if (_candidateTrackingArea != nil)
        [self removeTrackingArea:_candidateTrackingArea];
    _candidateTrackingArea = [[NSTrackingArea alloc]
        initWithRect:NSZeroRect
             options:NSTrackingMouseEnteredAndExited | NSTrackingActiveAlways | NSTrackingInVisibleRect
               owner:self
            userInfo:nil];
    [self addTrackingArea:_candidateTrackingArea];
    [super updateTrackingAreas];
}
- (void)mouseEntered:(NSEvent *)event
{
    (void)event;
    self.candidateHovered = YES;
    self.needsDisplay = YES;
}
- (void)mouseExited:(NSEvent *)event
{
    (void)event;
    self.candidateHovered = NO;
    self.needsDisplay = YES;
}
- (void)drawRect:(NSRect)dirtyRect
{
    if (self.tag < 0) { [super drawRect:dirtyRect]; return; }
    (void)dirtyRect;
    NSRectClip(self.bounds);
    NSColor *background = self.candidateHighlighted ? self.fillColor
                                                     : (self.candidateHovered ? self.hoverColor : nil);
    if (background != nil && background.alphaComponent > 0.01)
    {
        [background setFill];
        [[NSBezierPath bezierPathWithRoundedRect:NSInsetRect(self.bounds, 1, 1) xRadius:6 yRadius:6] fill];
    }
    if (self.candidateHighlighted && self.showSelectedBar)
    {
        const CGFloat barHeight = MAX(10.0, self.font.pointSize * 0.8);
        [self.barColor setFill];
        [[NSBezierPath
            bezierPathWithRoundedRect:NSMakeRect(3.0, (self.bounds.size.height - barHeight) / 2.0, 3.0, barHeight)
                              xRadius:1.5
                              yRadius:1.5] fill];
    }
    NSMutableParagraphStyle *paragraph = [NSMutableParagraphStyle new];
    paragraph.lineBreakMode = NSLineBreakByTruncatingTail;
    NSDictionary *numberAttributes = @{
        NSFontAttributeName : self.numberFont ?: MSIMECandidateNumberFont(self.font),
        NSForegroundColorAttributeName : self.numberColor != nil ? self.numberColor : NSColor.tertiaryLabelColor,
    };
    NSDictionary *titleAttributes = @{
        NSFontAttributeName : self.font,
        NSForegroundColorAttributeName : self.titleColor != nil ? self.titleColor : NSColor.labelColor,
        NSParagraphStyleAttributeName : paragraph,
    };
    NSString *title = self.title;
    NSRange split = [title rangeOfString:@"  "];
    const CGFloat textLeft = 8.0 + (self.showSelectedBar ? 6.0 : 0.0);
    if (split.location == NSNotFound)
    {
        const NSSize size = [title sizeWithAttributes:titleAttributes];
        const CGFloat maxWidth = MAX(0.0, self.bounds.size.width - textLeft - 8.0);
        [title drawInRect:NSMakeRect(textLeft, (self.bounds.size.height - size.height) / 2, maxWidth, size.height)
            withAttributes:titleAttributes];
        return;
    }
    NSString *number = [title substringToIndex:split.location];
    NSString *word = [title substringFromIndex:NSMaxRange(split)];
    const NSSize numberSize = [number sizeWithAttributes:numberAttributes];
    const NSSize wordSize = [word sizeWithAttributes:titleAttributes];
    NSFont *glossFont = self.translationFont ?: [NSFont systemFontOfSize:self.font.pointSize * 0.78];
    NSDictionary *glossAttributes = @{NSFontAttributeName:glossFont,
        NSForegroundColorAttributeName:self.translationColor ?: [(self.titleColor ?: NSColor.labelColor) colorWithAlphaComponent:MSIMECandidateTranslationOpacity],
        NSParagraphStyleAttributeName:paragraph};
    NSSize glossSize = [self.translation ?: @"" sizeWithAttributes:glossAttributes];
    CGFloat extraHeight = self.translationBelow ? self.translationRowHeight : 0;
    const CGFloat contentHeight = self.bounds.size.height - extraHeight;
    const CGFloat numberY = extraHeight + (contentHeight - numberSize.height) / 2;
    const CGFloat wordY = extraHeight + (contentHeight - wordSize.height) / 2;
    [number drawAtPoint:NSMakePoint(textLeft, numberY) withAttributes:numberAttributes];
    const CGFloat wordX = textLeft + numberSize.width + MSIMECandidateNumberGap;
    const CGFloat maxWidth = MAX(0.0, self.bounds.size.width - wordX - 8.0);
    [word drawInRect:NSMakeRect(wordX, wordY, maxWidth, wordSize.height) withAttributes:titleAttributes];
    if (self.translation.length) {
        CGFloat glossX = self.translationBelow ? wordX : wordX + wordSize.width + self.font.pointSize * 0.65;
        CGFloat glossY = self.translationBelow ? (extraHeight - glossSize.height) / 2 : (self.bounds.size.height - glossSize.height) / 2;
        [self.translation drawInRect:NSMakeRect(glossX, glossY, MAX(0, self.bounds.size.width - glossX - 8), glossSize.height) withAttributes:glossAttributes];
    }
}
@end

@interface MSIMECandidateChromeView : NSView
@property(nonatomic, weak) id appearanceTarget;
@property(nonatomic) SEL appearanceAction;
@property(nonatomic, copy) NSColor *fillColor;
@property(nonatomic, copy) NSColor *strokeColor;
@property(nonatomic) CGFloat cornerRadius;
@property(nonatomic) CGFloat lineWidth;
@end
@implementation MSIMECandidateChromeView
- (BOOL)isOpaque { return NO; }
- (void)viewDidChangeEffectiveAppearance
{
    [super viewDidChangeEffectiveAppearance];
    if (self.appearanceTarget != nil && self.appearanceAction != nullptr)
    {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Warc-performSelector-leaks"
        [self.appearanceTarget performSelector:self.appearanceAction];
#pragma clang diagnostic pop
    }
}
- (void)drawRect:(NSRect)dirtyRect
{
    (void)dirtyRect;
    NSBezierPath *path = [NSBezierPath bezierPathWithRoundedRect:self.bounds
                                                         xRadius:self.cornerRadius
                                                         yRadius:self.cornerRadius];
    [(self.fillColor != nil ? self.fillColor : NSColor.windowBackgroundColor) setFill];
    [path fill];
    if (self.lineWidth > 0.0 && self.strokeColor.alphaComponent > 0.01)
    {
        path.lineWidth = self.lineWidth;
        [self.strokeColor setStroke];
        [path stroke];
    }
}
@end
