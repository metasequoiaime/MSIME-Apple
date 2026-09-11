#pragma once
#import <AppKit/AppKit.h>
// Drawing adapted from MSIME-Apple b637828e15eafcb5e459edd270a962dd14517285.
@interface MSIMECandidateButton : NSButton
@property(nonatomic, copy) NSDictionary *candidateID;
@property(nonatomic) BOOL candidateHighlighted;
@property(nonatomic, copy) NSColor *fillColor;
@property(nonatomic, copy) NSColor *titleColor;
@property(nonatomic, copy) NSColor *numberColor;
@property(nonatomic, copy) NSColor *barColor;
@property(nonatomic) BOOL showSelectedBar;
@end
@implementation MSIMECandidateButton
- (BOOL)acceptsFirstResponder
{
    return NO;
}
- (BOOL)acceptsFirstMouse:(NSEvent *)event
{
    (void)event;
    return YES;
}
- (void)drawRect:(NSRect)dirtyRect
{
    if (self.tag < 0) { [super drawRect:dirtyRect]; return; }
    (void)dirtyRect;
    NSRectClip(self.bounds);
    if (self.candidateHighlighted && self.fillColor.alphaComponent > 0.01)
    {
        [self.fillColor setFill];
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
        NSFontAttributeName : self.font,
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
    const CGFloat y = (self.bounds.size.height - MAX(numberSize.height, wordSize.height)) / 2;
    [number drawAtPoint:NSMakePoint(textLeft, y) withAttributes:numberAttributes];
    const CGFloat wordX = textLeft + numberSize.width + 6.0;
    const CGFloat maxWidth = MAX(0.0, self.bounds.size.width - wordX - 8.0);
    [word drawInRect:NSMakeRect(wordX, y, maxWidth, wordSize.height) withAttributes:titleAttributes];
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
