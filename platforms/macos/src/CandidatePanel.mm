#import "CandidatePanel.h"
#import "CandidateAppearancePreferences.h"
#import "CandidateSkinAppearance.h"
#include "CandidateGlossLayout.h"
#include "StringConversion.h"

#include <cmath>

@interface MetasequoiaCandidateWindow : NSPanel
@end
@implementation MetasequoiaCandidateWindow
- (BOOL)canBecomeKeyWindow
{
    return NO;
}
- (BOOL)canBecomeMainWindow
{
    return NO;
}
@end

@interface MetasequoiaCandidateButton : NSButton
@property(nonatomic) BOOL candidateHighlighted;
@property(nonatomic, copy) NSColor *fillColor;
@property(nonatomic, copy) NSColor *titleColor;
@property(nonatomic, copy) NSColor *numberColor;
@property(nonatomic, copy) NSColor *barColor;
@property(nonatomic) BOOL showSelectedBar;
@property(nonatomic, copy) NSString *candidateTranslation;
@end
@implementation MetasequoiaCandidateButton
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
    NSString *translation = self.candidateTranslation;
    CGFloat translationWidth = 0.0;
    NSDictionary *translationAttributes = nil;
    if (translation.length > 0)
    {
        NSFont *translationFont = [NSFont systemFontOfSize:MAX(12.0, self.font.pointSize - 3.0)];
        NSColor *base = self.titleColor != nil ? self.titleColor : NSColor.labelColor;
        NSColor *translationColor =
            self.candidateHighlighted ? [base colorWithAlphaComponent:0.82] : NSColor.secondaryLabelColor;
        translationAttributes = @{
            NSFontAttributeName : translationFont,
            NSForegroundColorAttributeName : translationColor,
            NSParagraphStyleAttributeName : paragraph,
        };
        const NSSize translationSize = [translation sizeWithAttributes:translationAttributes];
        translationWidth =
            metasequoia::mac::CandidateGlossDrawnWidth(translationSize.width, self.bounds.size.width - textLeft - 8.0);
    }
    const CGFloat gap = translationWidth > 0.0 ? metasequoia::mac::kCandidateGlossGap : 0.0;
    const CGFloat rightPad = 8.0 + translationWidth + gap;
    if (split.location == NSNotFound)
    {
        const NSSize size = [title sizeWithAttributes:titleAttributes];
        const CGFloat maxWidth = MAX(0.0, self.bounds.size.width - textLeft - rightPad);
        [title drawInRect:NSMakeRect(textLeft, (self.bounds.size.height - size.height) / 2, maxWidth, size.height)
            withAttributes:titleAttributes];
    }
    else
    {
        NSString *number = [title substringToIndex:split.location];
        NSString *word = [title substringFromIndex:NSMaxRange(split)];
        const NSSize numberSize = [number sizeWithAttributes:numberAttributes];
        const NSSize wordSize = [word sizeWithAttributes:titleAttributes];
        const CGFloat y = (self.bounds.size.height - MAX(numberSize.height, wordSize.height)) / 2;
        [number drawAtPoint:NSMakePoint(textLeft, y) withAttributes:numberAttributes];
        const CGFloat wordX = textLeft + numberSize.width + 6.0;
        const CGFloat maxWidth = MAX(0.0, self.bounds.size.width - wordX - rightPad);
        [word drawInRect:NSMakeRect(wordX, y, maxWidth, wordSize.height) withAttributes:titleAttributes];
    }
    if (translationWidth > 0.0)
    {
        const NSSize translationSize = [translation sizeWithAttributes:translationAttributes];
        const CGFloat translationY = (self.bounds.size.height - translationSize.height) / 2;
        [translation drawInRect:NSMakeRect(self.bounds.size.width - 8.0 - translationWidth, translationY,
                                           translationWidth, translationSize.height)
                 withAttributes:translationAttributes];
    }
}
@end

@interface MetasequoiaCandidateChromeView : NSView
@property(nonatomic, weak) id appearanceTarget;
@property(nonatomic) SEL appearanceAction;
@property(nonatomic, copy) NSColor *fillColor;
@property(nonatomic, copy) NSColor *strokeColor;
@property(nonatomic) CGFloat cornerRadius;
@property(nonatomic) CGFloat lineWidth;
@end
@implementation MetasequoiaCandidateChromeView
- (BOOL)isOpaque
{
    return self.fillColor.alphaComponent >= 0.99;
}
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

@implementation MetasequoiaCandidatePanel
{
    NSPanel *_window;
    MetasequoiaCandidateChromeView *_chrome;
    NSImageView *_decorationView;
    NSArray<NSAttributedString *> *_data;
    NSFont *_font;
    NSInteger _selected;
    metasequoia::mac::ResolvedSkin _skin;
    NSImage *_decorationImage;
    NSRect _anchorCaret;
    NSPoint _fixedOrigin;
    BOOL _hasAnchor;
}

- (instancetype)init
{
    self = [super init];
    if (self)
    {
        _data = @[];
        _preedit = @"";
        _font = [NSFont systemFontOfSize:18];
        _selected = NSNotFound;
        _window = [[MetasequoiaCandidateWindow alloc]
            initWithContentRect:NSZeroRect
                      styleMask:NSWindowStyleMaskBorderless | NSWindowStyleMaskNonactivatingPanel
                        backing:NSBackingStoreBuffered
                          defer:NO];
        _window.releasedWhenClosed = NO;
        _window.level = NSPopUpMenuWindowLevel;
        _window.hidesOnDeactivate = NO;
        _window.opaque = NO;
        _window.backgroundColor = NSColor.clearColor;
        _window.hasShadow = YES;
        _window.collectionBehavior =
            NSWindowCollectionBehaviorCanJoinAllSpaces | NSWindowCollectionBehaviorFullScreenAuxiliary;
        _chrome = [[MetasequoiaCandidateChromeView alloc] initWithFrame:NSZeroRect];
        _chrome.appearanceTarget = self;
        _chrome.appearanceAction = @selector(reloadSkin);
        _window.contentView = _chrome;
        _decorationView = [[NSImageView alloc] initWithFrame:NSZeroRect];
        _decorationView.imageScaling = NSImageScaleProportionallyUpOrDown;
        _decorationView.imageAlignment = NSImageAlignTopRight;
        _decorationView.wantsLayer = YES;
        [self reloadSkin];
        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(reloadSkin)
                                                     name:MetasequoiaCandidateSkinDidChangeNotification
                                                   object:nil];
        [NSNotificationCenter.defaultCenter addObserver:self
                                               selector:@selector(reloadSkin)
                                                   name:MetasequoiaAppearanceDidChange
                                                 object:nil];
        [NSDistributedNotificationCenter.defaultCenter addObserver:self
                                                          selector:@selector(reloadSkin)
                                                              name:MetasequoiaAppearanceDidChange
                                                            object:nil];
    }
    return self;
}
- (void)dealloc
{
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    [NSDistributedNotificationCenter.defaultCenter removeObserver:self];
    [_window orderOut:nil];
}
- (NSPanel *)window
{
    return _window;
}
- (void)reloadSkin
{
    [NSUserDefaults.standardUserDefaults synchronize];
    NSInteger legacySize = [NSUserDefaults.standardUserDefaults integerForKey:@"MetasequoiaImeCandidateFontSize"];
    _font = MetasequoiaCandidateFont(MetasequoiaAppearanceInteger(
        @"fontSize", legacySize >= 12 && legacySize <= 36 ? legacySize : _font.pointSize, 12, 36));
    _skin = MetasequoiaResolveStoredCandidateSkin(MetasequoiaAppearanceIsDark(_chrome.effectiveAppearance));
    _decorationImage = nil;
    if (_skin.decorationTopDip > 0.0 && !_skin.decorationPath.empty())
    {
        _decorationImage = [[NSImage alloc] initWithContentsOfFile:@(_skin.decorationPath.c_str())];
    }
    [self layoutCandidates];
}
- (void)setPreedit:(NSString *)preedit
{
    _preedit = preedit ? [preedit copy] : @"";
    [self layoutCandidates];
}
- (void)setPanelType:(IMKCandidatePanelType)type
{
    _panelType = type;
    [self layoutCandidates];
}
- (void)setHasPreviousPage:(BOOL)value
{
    _hasPreviousPage = value;
    [self layoutCandidates];
}
- (void)setHasNextPage:(BOOL)value
{
    _hasNextPage = value;
    [self layoutCandidates];
}
- (void)setAttributes:(NSDictionary *)attributes
{
    NSFont *font = attributes[NSFontAttributeName];
    if ([font isKindOfClass:NSFont.class])
        _font = font;
    [self layoutCandidates];
}
- (void)setCandidateData:(NSArray<NSAttributedString *> *)candidates
{
    _data = [candidates copy];
    _selected = _data.count > 0 ? 0 : NSNotFound;
    [self layoutCandidates];
    if (_data.count == 0)
        [self hide];
}
- (NSScreen *)screenForCaret
{
    NSRect caret = _hasAnchor && !MetasequoiaCandidateFollowsCaret() ? _anchorCaret : self.caretRect;
    for (NSScreen *screen in NSScreen.screens)
        if (NSPointInRect(NSMakePoint(NSMinX(caret), NSMidY(caret)), screen.frame))
            return screen;
    return NSScreen.mainScreen;
}
- (void)layoutCandidates
{
    for (NSView *view in [_chrome.subviews copy])
        [view removeFromSuperview];
    const CGFloat inset = MAX(2.0, _skin.tokens.pad);
    const CGFloat rowHeight = ceil(_font.ascender - _font.descender + _font.leading) + 12;
    const BOOL vertical = _panelType == kIMKSingleColumnScrollingCandidatePanel;
    NSMutableArray<NSNumber *> *widths = [NSMutableArray array];
    NSMutableArray<NSString *> *titles = [NSMutableArray array];
    CGFloat width = 0;
    const BOOL paging = _hasPreviousPage || _hasNextPage;
    const CGFloat screenWidth = [self screenForCaret].visibleFrame.size.width;
    const CGFloat availableWidth = MAX(80, screenWidth - 20 - 2 * inset - (paging && !vertical ? 56 : 0));
    const CGFloat leftPad = 8.0 + (_skin.tokens.showSelectedBar ? 6.0 : 0.0);
    NSDictionary *measure = @{NSFontAttributeName : _font};
    NSMutableArray<NSString *> *translations = [NSMutableArray array];
    NSFont *translationFont = [NSFont systemFontOfSize:MAX(12.0, _font.pointSize - 3.0)];
    NSDictionary *translationMeasure = @{NSFontAttributeName : translationFont};
    for (NSUInteger index = 0; index < _data.count; ++index)
    {
        NSString *number = [NSString stringWithFormat:@"%lu", (unsigned long)index + 1];
        NSString *word = _data[index].string;
        NSString *title = [NSString stringWithFormat:@"%@  %@", number, word];
        NSString *translation = vertical ? MetasequoiaCandidateTranslation(_data[index]) : nil;
        CGFloat itemWidth = ceil(leftPad + [number sizeWithAttributes:measure].width + 6.0 +
                                 [word sizeWithAttributes:measure].width + 8.0);
        if (translation.length > 0)
            itemWidth = ceil(itemWidth + metasequoia::mac::CandidateGlossReservedWidth(
                                             [translation sizeWithAttributes:translationMeasure].width));
        [titles addObject:title];
        [translations addObject:translation.length > 0 ? translation : @""];
        [widths addObject:@(itemWidth)];
        width = vertical ? MAX(width, itemWidth) : width + itemWidth;
    }
    if (vertical)
    {
        width = MIN(width, availableWidth);
    }
    else if (width > availableWidth && width > 0)
    {
        const CGFloat scale = availableWidth / width;
        width = 0;
        for (NSUInteger index = 0; index < widths.count; ++index)
        {
            const CGFloat scaled = MAX(24.0, floor(widths[index].doubleValue * scale));
            widths[index] = @(scaled);
            width += scaled;
        }
    }
    const CGFloat navigationHeight = paging && vertical ? 26 : 0;
    if (paging)
        width = vertical ? MAX(width, 64) : width + 56;
    const CGFloat decorationHeight = _skin.decorationTopDip > 0.0 ? _skin.decorationTopDip : 0.0;
    NSFont *preeditFont = MetasequoiaCandidateFont(MetasequoiaAppearanceInteger(@"preeditSize", 15, 10, 36));
    const CGFloat preeditHeight =
        _preedit.length ? ceil(preeditFont.ascender - preeditFont.descender + preeditFont.leading) + 10 : 0;
    if (_preedit.length)
        width =
            MAX(width, MIN(availableWidth, [_preedit sizeWithAttributes:@{NSFontAttributeName : preeditFont}].width));
    const CGFloat minWidth = MAX(_skin.minWidthDip, MAX(_skin.decorationWidthDip, 20));
    NSSize size = NSMakeSize(MAX(width + 2 * inset, minWidth),
                             MAX((vertical ? _data.count : (_data.count > 0 ? 1 : 0)) * rowHeight + navigationHeight +
                                     2 * inset + decorationHeight + preeditHeight,
                                 10));
    [_window setContentSize:size];
    _chrome.fillColor = MetasequoiaColorFromRgba(_skin.tokens.surface);
    _chrome.strokeColor = MetasequoiaColorFromRgba(_skin.tokens.border);
    _chrome.cornerRadius = _skin.tokens.radius;
    _chrome.lineWidth = _skin.tokens.borderWidth;
    _chrome.needsDisplay = YES;
    if (decorationHeight > 0.0 && _decorationImage != nil)
    {
        const CGFloat decorationWidth =
            _skin.decorationWidthDip > 0.0 ? _skin.decorationWidthDip : MIN(size.width, _decorationImage.size.width);
        _decorationView.image = _decorationImage;
        _decorationView.frame =
            NSMakeRect(size.width - decorationWidth, size.height - decorationHeight, decorationWidth, decorationHeight);
        [_chrome addSubview:_decorationView];
    }
    CGFloat x = inset;
    const CGFloat contentTop = size.height - inset - decorationHeight - preeditHeight;
    if (_preedit.length)
    {
        NSTextField *label = [NSTextField labelWithString:_preedit];
        label.font = preeditFont;
        label.textColor = MetasequoiaColorFromRgba(_skin.tokens.text);
        label.lineBreakMode = NSLineBreakByTruncatingTail;
        label.frame = NSMakeRect(inset, contentTop + 4, size.width - inset * 2, preeditHeight - 4);
        label.accessibilityLabel = @"预编辑文本";
        [_chrome addSubview:label];
    }
    NSColor *selectedFill = MetasequoiaColorFromRgba(_skin.tokens.selected);
    NSColor *textColor = MetasequoiaColorFromRgba(_skin.tokens.text);
    NSColor *selectedText = MetasequoiaColorFromRgba(_skin.tokens.selectedText);
    NSColor *numberColor = MetasequoiaColorFromRgba(_skin.tokens.number);
    NSColor *accent = MetasequoiaColorFromRgba(_skin.tokens.accent);
    for (NSUInteger index = 0; index < _data.count; ++index)
    {
        const CGFloat itemWidth = vertical ? width : widths[index].doubleValue;
        const CGFloat y = vertical ? contentTop - (index + 1) * rowHeight : inset;
        MetasequoiaCandidateButton *button =
            [[MetasequoiaCandidateButton alloc] initWithFrame:NSMakeRect(x, y, itemWidth, rowHeight)];
        button.title = titles[index];
        button.font = _font;
        button.bordered = NO;
        button.tag = (NSInteger)index;
        button.target = self;
        button.action = @selector(selectFromMouse:);
        button.candidateHighlighted = (NSInteger)index == _selected;
        button.fillColor = selectedFill;
        button.titleColor = button.candidateHighlighted ? selectedText : textColor;
        button.numberColor = button.candidateHighlighted ? selectedText : numberColor;
        button.barColor = accent;
        button.showSelectedBar = _skin.tokens.showSelectedBar;
        button.candidateTranslation = translations[index];
        button.accessibilityLabel = translations[index].length > 0
                                        ? [NSString stringWithFormat:@"%@，%@", titles[index], translations[index]]
                                        : titles[index];
        button.toolTip = translations[index].length > 0
                             ? [NSString stringWithFormat:@"%@  %@", _data[index].string, translations[index]]
                             : _data[index].string;
        [_chrome addSubview:button];
        if (!vertical)
            x += itemWidth;
    }
    if (paging)
    {
        for (NSUInteger index = 0; index < 2; ++index)
        {
            NSButton *button = [NSButton buttonWithTitle:index == 0 ? @"‹" : @"›"
                                                  target:self
                                                  action:@selector(changePage:)];
            button.frame = NSMakeRect(vertical ? inset + index * 28 : x + index * 28, inset, 28,
                                      vertical ? navigationHeight : rowHeight);
            button.bordered = NO;
            button.contentTintColor = textColor;
            button.tag = index == 0 ? -1 : -2;
            button.enabled = index == 0 ? _hasPreviousPage : _hasNextPage;
            button.accessibilityLabel = index == 0 ? @"上一页候选" : @"下一页候选";
            [_chrome addSubview:button];
        }
    }
}
- (void)selectFromMouse:(NSButton *)button
{
    if ([self selectCandidateWithIdentifier:button.tag])
        [self.delegate candidateSelected:_data[button.tag]];
}
- (void)changePage:(NSButton *)button
{
    if (button.tag == -1 && _hasPreviousPage)
        [self.delegate candidatePanelPreviousPage];
    if (button.tag == -2 && _hasNextPage)
        [self.delegate candidatePanelNextPage];
}
- (void)show:(IMKCandidatesLocationHint)hint
{
    (void)hint;
    if (_data.count == 0)
    {
        [self hide];
        return;
    }
    NSRect caret = self.caretRect;
    if (_hasAnchor && !MetasequoiaCandidateFollowsCaret())
        caret = _anchorCaret;
    if (!std::isfinite(caret.origin.x) || !std::isfinite(caret.origin.y) || !std::isfinite(caret.size.width) ||
        !std::isfinite(caret.size.height) || caret.size.height <= 0)
    {
        [self hide];
        return;
    }
    [self layoutCandidates];
    NSRect bounds = [self screenForCaret].visibleFrame;
    NSSize size = _window.frame.size;
    CGFloat x = MIN(MAX(NSMinX(caret), NSMinX(bounds)), MAX(NSMinX(bounds), NSMaxX(bounds) - size.width));
    CGFloat y = NSMinY(caret) - size.height - 4;
    if (y < NSMinY(bounds))
        y = NSMaxY(caret) + 4;
    y = MIN(MAX(y, NSMinY(bounds)), MAX(NSMinY(bounds), NSMaxY(bounds) - size.height));
    if (_hasAnchor && !MetasequoiaCandidateFollowsCaret())
    {
        x = MIN(MAX(_fixedOrigin.x, NSMinX(bounds)), MAX(NSMinX(bounds), NSMaxX(bounds) - size.width));
        y = MIN(MAX(_fixedOrigin.y, NSMinY(bounds)), MAX(NSMinY(bounds), NSMaxY(bounds) - size.height));
    }
    else
    {
        _anchorCaret = caret;
        _fixedOrigin = NSMakePoint(x, y);
        _hasAnchor = YES;
    }
    [_window setFrameOrigin:NSMakePoint(x, y)];
    [_window orderFrontRegardless];
}
- (void)hide
{
    _hasAnchor = NO;
    [_window orderOut:nil];
}
- (BOOL)isVisible
{
    return _window.isVisible;
}
- (NSRect)candidateFrame
{
    return _window.frame;
}
- (NSInteger)candidateIdentifierAtLineNumber:(NSInteger)line
{
    return line >= 0 && (NSUInteger)line < _data.count ? line : NSNotFound;
}
- (NSInteger)lineNumberForCandidateWithIdentifier:(NSInteger)identifier
{
    return [self candidateIdentifierAtLineNumber:identifier];
}
- (NSInteger)candidateStringIdentifier:(NSAttributedString *)candidate
{
    return (NSInteger)[_data indexOfObjectIdenticalTo:candidate];
}
- (BOOL)selectCandidateWithIdentifier:(NSInteger)identifier
{
    if ([self candidateIdentifierAtLineNumber:identifier] == NSNotFound)
        return NO;
    _selected = identifier;
    for (NSView *view in _chrome.subviews)
        if ([view isKindOfClass:MetasequoiaCandidateButton.class])
        {
            MetasequoiaCandidateButton *button = (MetasequoiaCandidateButton *)view;
            button.candidateHighlighted = view.tag == identifier;
            button.titleColor = button.candidateHighlighted ? MetasequoiaColorFromRgba(_skin.tokens.selectedText)
                                                            : MetasequoiaColorFromRgba(_skin.tokens.text);
            button.numberColor = button.candidateHighlighted ? MetasequoiaColorFromRgba(_skin.tokens.selectedText)
                                                             : MetasequoiaColorFromRgba(_skin.tokens.number);
            view.needsDisplay = YES;
        }
    return YES;
}
- (NSInteger)selectedCandidate
{
    return _selected;
}
- (NSAttributedString *)selectedCandidateString
{
    return _selected == NSNotFound ? nil : _data[_selected];
}
@end
