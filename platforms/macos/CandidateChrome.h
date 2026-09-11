#pragma once

#import <AppKit/AppKit.h>

@interface MSIMECandidateButton : NSButton
@property(nonatomic, copy) NSDictionary *candidateID;
@property(nonatomic) BOOL candidateHighlighted;
@property(nonatomic, copy) NSColor *fillColor;
@property(nonatomic, copy) NSColor *titleColor;
@property(nonatomic, copy) NSColor *numberColor;
@property(nonatomic, copy) NSColor *barColor;
@property(nonatomic) BOOL showSelectedBar;
@end

@interface MSIMECandidateChromeView : NSView
@property(nonatomic, copy) NSColor *fillColor;
@property(nonatomic, copy) NSColor *strokeColor;
@property(nonatomic) CGFloat cornerRadius;
@property(nonatomic) CGFloat lineWidth;
@end

@implementation MSIMECandidateButton
- (BOOL)acceptsFirstResponder { return NO; }
- (BOOL)acceptsFirstMouse:(NSEvent *)event { (void)event; return YES; }
- (void)drawRect:(NSRect)dirtyRect
{
    if (self.tag < 0) { [super drawRect:dirtyRect]; return; }
    (void)dirtyRect;
    NSRectClip(self.bounds);
    if (self.candidateHighlighted && self.fillColor.alphaComponent > 0.01) {
        [self.fillColor setFill];
        [[NSBezierPath bezierPathWithRoundedRect:NSInsetRect(self.bounds, 1, 1) xRadius:6 yRadius:6] fill];
    }
    if (self.candidateHighlighted && self.showSelectedBar) {
        const CGFloat barHeight = MAX(10.0, self.font.pointSize * 0.8);
        [self.barColor setFill];
        [[NSBezierPath bezierPathWithRoundedRect:NSMakeRect(3, (self.bounds.size.height - barHeight) / 2, 3, barHeight)
                                         xRadius:1.5 yRadius:1.5] fill];
    }
    NSMutableParagraphStyle *paragraph = [NSMutableParagraphStyle new];
    paragraph.lineBreakMode = NSLineBreakByTruncatingTail;
    NSDictionary *numberAttributes = @{NSFontAttributeName: self.font,
                                       NSForegroundColorAttributeName: self.numberColor ?: NSColor.tertiaryLabelColor};
    NSDictionary *titleAttributes = @{NSFontAttributeName: self.font,
                                      NSForegroundColorAttributeName: self.titleColor ?: NSColor.labelColor,
                                      NSParagraphStyleAttributeName: paragraph};
    NSRange split = [self.title rangeOfString:@"  "];
    const CGFloat left = 8 + (self.showSelectedBar ? 6 : 0);
    if (split.location == NSNotFound) {
        NSSize size = [self.title sizeWithAttributes:titleAttributes];
        [self.title drawInRect:NSMakeRect(left, (self.bounds.size.height - size.height) / 2,
                                          MAX(0, self.bounds.size.width - left - 8), size.height)
                 withAttributes:titleAttributes];
        return;
    }
    NSString *number = [self.title substringToIndex:split.location];
    NSString *word = [self.title substringFromIndex:NSMaxRange(split)];
    NSSize numberSize = [number sizeWithAttributes:numberAttributes];
    NSSize wordSize = [word sizeWithAttributes:titleAttributes];
    CGFloat y = (self.bounds.size.height - MAX(numberSize.height, wordSize.height)) / 2;
    [number drawAtPoint:NSMakePoint(left, y) withAttributes:numberAttributes];
    CGFloat wordX = left + numberSize.width + 6;
    [word drawInRect:NSMakeRect(wordX, y, MAX(0, self.bounds.size.width - wordX - 8), wordSize.height)
      withAttributes:titleAttributes];
}
@end

@implementation MSIMECandidateChromeView
- (BOOL)isOpaque { return NO; }
- (void)drawRect:(NSRect)dirtyRect
{
    (void)dirtyRect;
    NSBezierPath *path = [NSBezierPath bezierPathWithRoundedRect:self.bounds
                                                           xRadius:self.cornerRadius yRadius:self.cornerRadius];
    [(self.fillColor ?: NSColor.windowBackgroundColor) setFill];
    [path fill];
    if (self.lineWidth > 0 && self.strokeColor.alphaComponent > 0.01) {
        [self.strokeColor setStroke];
        path.lineWidth = self.lineWidth;
        [path stroke];
    }
}
@end
