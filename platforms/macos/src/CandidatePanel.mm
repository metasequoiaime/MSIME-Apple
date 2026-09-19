#import "CandidatePanel.h"
#import "CandidateAppearancePreferences.h"
#import "CandidateSkinAppearance.h"
#include "CandidateGlossLayout.h"
#include "CandidateRowFit.h"
#include "InputBehaviorPreferences.h"
#include "StringConversion.h"

#include <cmath>
#include <vector>

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

// 序号和候选词之间的间距。测量和绘制必须用同一个数 —— 分叉过一次:布局按 5 预留、同行绘制按 6 画,
// 助记码注解就被裁掉 1pt,而本机字体度量和 CI 差的那点正好被断言的 0.5 容差吃掉,只有 CI 会红。
static const CGFloat kCandidateNumberGap = 6.0;

@interface MetasequoiaCandidateButton : NSButton
@property(nonatomic) BOOL candidateHighlighted;
@property(nonatomic, copy) NSColor *fillColor;
@property(nonatomic, copy) NSColor *titleColor;
@property(nonatomic, copy) NSColor *numberColor;
@property(nonatomic, copy) NSColor *barColor;
@property(nonatomic) BOOL showSelectedBar;
@property(nonatomic, copy) NSString *candidateTranslation;
@property(nonatomic, copy) NSString *candidateSecondaryTranslation;
// 释义垂直于候选的排列方向:候选横着走就把释义叠在词下面,候选竖着走就排在同一行。反过来两种都爆——
// 九个候选把释义摆在词旁边要 2322pt(屏幕只有 1512),而把释义叠在竖排每一行下面要 639pt 高。
@property(nonatomic) BOOL stacksGlosses;
// 待上屏的那一列:0 词,1 目标语言释义,2 第二语言释义。Tab 切换,画成下划线 —— 光靠提高不透明度
// 在浅色皮肤上几乎看不出来,而按错一次就上屏了错东西。
@property(nonatomic) NSInteger armedGlossColumn;
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
// 右键走和左键同一条路:交给面板,面板再转给 delegate。A menu holding one item would cost an extra
// click for the only thing it offers.
- (void)rightMouseDown:(NSEvent *)event
{
    (void)event;
    if ([self.target respondsToSelector:@selector(pinFromMouse:)])
        [self.target performSelector:@selector(pinFromMouse:) withObject:self];
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
    if (self.candidateHighlighted && self.showSelectedBar && !self.stacksGlosses)
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
    NSColor *base = self.titleColor != nil ? self.titleColor : NSColor.labelColor;
    NSDictionary *numberAttributes = @{
        NSFontAttributeName : self.font,
        NSForegroundColorAttributeName : self.numberColor != nil ? self.numberColor : NSColor.tertiaryLabelColor,
    };
    NSDictionary *titleAttributes = @{
        NSFontAttributeName : self.font,
        NSForegroundColorAttributeName : base,
        NSParagraphStyleAttributeName : paragraph,
    };
    NSDictionary * (^glossAttributes)(CGFloat, CGFloat) = ^(CGFloat drop, CGFloat alpha) {
      NSColor *color = self.candidateHighlighted ? [base colorWithAlphaComponent:alpha] : NSColor.secondaryLabelColor;
      return @{
          NSFontAttributeName : [NSFont systemFontOfSize:MAX(11.0, self.font.pointSize - drop)],
          NSForegroundColorAttributeName : color,
          NSParagraphStyleAttributeName : paragraph,
      };
    };
    NSDictionary * (^armedAttributes)(NSDictionary *) = ^(NSDictionary *attributes) {
      NSMutableDictionary *armed = [attributes mutableCopy];
      armed[NSForegroundColorAttributeName] = base;
      armed[NSUnderlineStyleAttributeName] = @(NSUnderlineStyleSingle);
      return [armed copy];
    };
    NSDictionary *primaryAttributes = glossAttributes(5.0, 0.82);
    NSDictionary *secondaryAttributes = glossAttributes(6.0, 0.66);
    if (self.candidateHighlighted && self.armedGlossColumn == 1)
        primaryAttributes = armedAttributes(primaryAttributes);
    else if (self.candidateHighlighted && self.armedGlossColumn == 2)
        secondaryAttributes = armedAttributes(secondaryAttributes);

    NSString *title = self.title;
    NSRange split = [title rangeOfString:@"  "];
    NSString *number = split.location == NSNotFound ? @"" : [title substringToIndex:split.location];
    NSString *word = split.location == NSNotFound ? title : [title substringFromIndex:NSMaxRange(split)];
    NSString *primary = self.candidateTranslation;
    NSString *secondary = self.candidateSecondaryTranslation;
    const CGFloat textLeft = 8.0 + (self.showSelectedBar && !self.stacksGlosses ? 6.0 : 0.0);

    if (self.stacksGlosses)
    {
        // 三行叠:序号和词一行,两条释义各占一行,全部左对齐。格宽由最宽的那一行决定,所以宽度是
        // max(词, 英, 日) 而不是它们的和。
        const NSSize numberSize = [number sizeWithAttributes:numberAttributes];
        const NSSize wordSize = [word sizeWithAttributes:titleAttributes];
        const CGFloat available = MAX(0.0, self.bounds.size.width - textLeft - 8.0);
        // 按距顶端的距离排版,再按 isFlipped 换算成 y。这个绘制上下文是翻转的(y 向下增),直接从
        // bounds.height 往下减会把释义画到词的上面 —— 原来的代码全部垂直居中,从没暴露过方向。
        __block CGFloat fromTop = 6.0;
        const BOOL flipped = self.isFlipped;
        const CGFloat boxHeight = self.bounds.size.height;
        CGFloat (^lineY)(CGFloat) = ^(CGFloat lineHeight) {
          const CGFloat y = flipped ? fromTop : boxHeight - fromTop - lineHeight;
          fromTop += lineHeight;
          return y;
        };
        const CGFloat wordY = lineY(wordSize.height + 2.0);
        if (number.length > 0)
            [number drawAtPoint:NSMakePoint(textLeft, wordY) withAttributes:numberAttributes];
        const CGFloat wordX = textLeft + (number.length > 0 ? numberSize.width + kCandidateNumberGap : 0.0);
        [word drawInRect:NSMakeRect(wordX, wordY, MAX(0.0, self.bounds.size.width - wordX - 8.0), wordSize.height)
            withAttributes:titleAttributes];
        // 两行释义的位置固定,空着也占 —— 模型是几秒后才回的,等结果到了再长高会让整条候选条当场跳一下。
        const NSSize primarySize = [@"Ag" sizeWithAttributes:primaryAttributes];
        const CGFloat primaryY = lineY(primarySize.height + 1.0);
        if (primary.length > 0)
            [primary drawInRect:NSMakeRect(textLeft, primaryY, available, primarySize.height)
                 withAttributes:primaryAttributes];
        const NSSize secondarySize = [@"Ag" sizeWithAttributes:secondaryAttributes];
        const CGFloat secondaryY = lineY(secondarySize.height);
        if (secondary.length > 0)
            [secondary drawInRect:NSMakeRect(textLeft, secondaryY, available, secondarySize.height)
                   withAttributes:secondaryAttributes];
        return;
    }

    // 同一行排开:序号 词 英 日。竖排的行高不变,变的只是宽度。
    const NSSize numberSize = [number sizeWithAttributes:numberAttributes];
    const NSSize wordSize = [word sizeWithAttributes:titleAttributes];
    const CGFloat y = (self.bounds.size.height - wordSize.height) / 2;
    if (number.length > 0)
        [number drawAtPoint:NSMakePoint(textLeft, y) withAttributes:numberAttributes];
    CGFloat x = textLeft + (number.length > 0 ? numberSize.width + kCandidateNumberGap : 0.0);
    const CGFloat rightEdge = self.bounds.size.width - 8.0;
    const CGFloat wordWidth = MIN(wordSize.width, MAX(0.0, rightEdge - x));
    [word drawInRect:NSMakeRect(x, y, wordWidth, wordSize.height) withAttributes:titleAttributes];
    x += wordWidth + metasequoia::mac::kCandidateGlossGap;
    for (NSUInteger pass = 0; pass < 2; ++pass)
    {
        NSString *gloss = pass == 0 ? primary : secondary;
        if (gloss.length == 0)
            continue;
        NSDictionary *attributes = pass == 0 ? primaryAttributes : secondaryAttributes;
        const NSSize size = [gloss sizeWithAttributes:attributes];
        const CGFloat room = MAX(0.0, rightEdge - x);
        if (room <= 1.0)
            break;
        const CGFloat drawn = metasequoia::mac::CandidateGlossDrawnWidth(size.width, room);
        [gloss drawInRect:NSMakeRect(x, y + (wordSize.height - size.height) / 2, drawn, size.height)
            withAttributes:attributes];
        x += drawn + metasequoia::mac::kCandidateGlossGap;
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
    NSInteger _armedGlossColumn;
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
        _armedGlossColumn = 0;
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
    const BOOL vertical = _panelType == kIMKSingleColumnScrollingCandidatePanel;
    NSMutableArray<NSNumber *> *widths = [NSMutableArray array];
    std::vector<metasequoia::mac::CandidateRowItem> rowItems;
    rowItems.reserve(_data.count);
    NSMutableArray<NSString *> *titles = [NSMutableArray array];
    CGFloat width = 0;
    const BOOL paging = _hasPreviousPage || _hasNextPage;
    const CGFloat screenWidth = [self screenForCaret].visibleFrame.size.width;
    const CGFloat availableWidth = MAX(80, screenWidth - 20 - 2 * inset - (paging && !vertical ? 56 : 0));
    const CGFloat leftPad = 8.0 + (_skin.tokens.showSelectedBar ? 6.0 : 0.0);
    NSDictionary *measure = @{NSFontAttributeName : _font};
    NSMutableArray<NSString *> *translations = [NSMutableArray array];
    NSMutableArray<NSString *> *secondaryTranslations = [NSMutableArray array];
    NSFont *primaryFont = [NSFont systemFontOfSize:MAX(11.0, _font.pointSize - 5.0)];
    NSFont *secondaryFont = [NSFont systemFontOfSize:MAX(11.0, _font.pointSize - 6.0)];
    NSDictionary *primaryMeasure = @{NSFontAttributeName : primaryFont};
    NSDictionary *secondaryMeasure = @{NSFontAttributeName : secondaryFont};
    const CGFloat wordLine = ceil(_font.ascender - _font.descender + _font.leading);
    const CGFloat primaryLine = ceil(primaryFont.ascender - primaryFont.descender + primaryFont.leading);
    const CGFloat secondaryLine = ceil(secondaryFont.ascender - secondaryFont.descender + secondaryFont.leading);
    // 释义一律占位,有没有内容都一样高 —— 模型几秒后才回,等结果到了再长高会让面板当场跳一下。竖排的
    // 释义在同一行,所以行高不变,变的是宽度。
    // 只要开着释义就留位置,不看这一页有没有内容。原来按「有没有释义」决定留不留,结果第一次组字时
    // 模型还没回来、一条都没有,于是不留 —— 几秒后答案到了面板才长高,正是预留想避免的那一跳。
    const BOOL stacked = !vertical && MetasequoiaInputFlag(@"candidateTranslation", YES);
    const CGFloat rowHeight = stacked ? wordLine + primaryLine + secondaryLine + 12.0 : wordLine + 12.0;
    for (NSUInteger index = 0; index < _data.count; ++index)
    {
        NSString *number = [NSString stringWithFormat:@"%lu", (unsigned long)index + 1];
        NSString *word = _data[index].string;
        NSString *title = [NSString stringWithFormat:@"%@  %@", number, word];
        NSString *translation = MetasequoiaCandidateTranslation(_data[index]);
        NSString *secondary = MetasequoiaCandidateSecondaryTranslation(_data[index]);
        const CGFloat headWidth =
            [number sizeWithAttributes:measure].width + kCandidateNumberGap + [word sizeWithAttributes:measure].width;
        const CGFloat primaryWidth =
            translation.length > 0 ? [translation sizeWithAttributes:primaryMeasure].width : 0.0;
        const CGFloat secondaryWidth =
            secondary.length > 0 ? [secondary sizeWithAttributes:secondaryMeasure].width : 0.0;
        // 候选词本身要多宽,和释义想要多宽分开记:一行放不下时先砍释义、再从行尾砍起,靠前的长句最后才让宽度。
        const CGFloat textWidth = ceil(leftPad + headWidth + (stacked ? 10.0 : 8.0));
        CGFloat itemWidth;
        if (stacked)
        {
            // 三行叠:格宽是最宽那一行,不是三者之和。九个候选因此是 892pt 而不是 2322pt。
            const CGFloat widest = MAX(headWidth, MAX(MIN(primaryWidth, metasequoia::mac::kCandidateGlossMaxWidth),
                                                      MIN(secondaryWidth, metasequoia::mac::kCandidateGlossMaxWidth)));
            itemWidth = ceil(leftPad + widest + 10.0);
        }
        else
        {
            itemWidth = ceil(leftPad + headWidth + 8.0);
            for (CGFloat glossWidth : {primaryWidth, secondaryWidth})
                if (glossWidth > 0.0)
                    itemWidth = ceil(itemWidth + metasequoia::mac::CandidateGlossReservedWidth(glossWidth));
        }
        rowItems.push_back({textWidth, itemWidth});
        [titles addObject:title];
        [translations addObject:translation.length > 0 ? translation : @""];
        [secondaryTranslations addObject:secondary.length > 0 ? secondary : @""];
        [widths addObject:@(itemWidth)];
        width = vertical ? MAX(width, itemWidth) : width + itemWidth;
    }
    if (vertical)
    {
        width = MIN(width, availableWidth);
    }
    else if (width > availableWidth && width > 0)
    {
        // 一行放不下这一页时,整行等比压缩会把排在最前、最可能被选中的长句和末尾的单字候选砍掉同样的比例。
        // 完整显示比凑满一页更重要:按原宽度从头排,排不下就不排了 —— 这一页少显示几条,显示出来的都是完整的。
        const std::vector<double> fitted = metasequoia::mac::FitCandidateRowWidths(rowItems, availableWidth);
        width = 0;
        for (NSUInteger index = 0; index < widths.count; ++index)
        {
            const CGFloat fittedWidth = floor(fitted[index]);
            widths[index] = @(fittedWidth);
            width += fittedWidth;
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
        // 横排放不下的候选宽度是 0:这一页剩下的都排不下了,不画残缺的格子。
        if (itemWidth <= 0.0)
            break;
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
        button.armedGlossColumn = _armedGlossColumn;
        button.candidateTranslation = translations[index];
        button.candidateSecondaryTranslation = secondaryTranslations[index];
        button.stacksGlosses = stacked;
        NSMutableArray<NSString *> *spoken = [NSMutableArray arrayWithObject:titles[index]];
        for (NSString *gloss in @[ translations[index], secondaryTranslations[index] ])
            if (gloss.length > 0)
                [spoken addObject:gloss];
        button.accessibilityLabel = [spoken componentsJoinedByString:@"，"];
        [spoken replaceObjectAtIndex:0 withObject:_data[index].string];
        button.toolTip = [spoken componentsJoinedByString:@"  "];
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
- (void)pinFromMouse:(NSButton *)button
{
    if (button.tag >= 0 && button.tag < static_cast<NSInteger>(_data.count))
        [self.delegate candidatePinToggled:_data[button.tag]];
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
- (void)setArmedGlossColumn:(NSInteger)column
{
    if (_armedGlossColumn == column)
    {
        return;
    }
    _armedGlossColumn = column;
    // 和选中高亮走同一条路:按钮挂在 _chrome 上。走 window.contentView 眼下指的是同一个对象,但那是
    // 赋值的副产品,不是约定。
    for (NSView *view in _chrome.subviews)
    {
        if ([view isKindOfClass:MetasequoiaCandidateButton.class])
        {
            ((MetasequoiaCandidateButton *)view).armedGlossColumn = column;
            view.needsDisplay = YES;
        }
    }
}

- (NSInteger)armedGlossColumn
{
    return _armedGlossColumn;
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
