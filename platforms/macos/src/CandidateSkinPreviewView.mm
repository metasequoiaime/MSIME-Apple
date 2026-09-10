#import "CandidateSkinPreviewView.h"
#import "CandidateSkinAppearance.h"

namespace
{
void DrawSkinChrome(NSRect rect, const metasequoia::mac::SkinTokens &tokens)
{
    NSBezierPath *path = [NSBezierPath bezierPathWithRoundedRect:rect xRadius:tokens.radius yRadius:tokens.radius];
    [MetasequoiaColorFromRgba(tokens.surface) setFill];
    [path fill];
    if (tokens.borderWidth > 0.0 && tokens.border.a > 0.01f)
    {
        [MetasequoiaColorFromRgba(tokens.border) setStroke];
        path.lineWidth = tokens.borderWidth;
        [path stroke];
    }
}

struct SkinPreviewMetrics
{
    CGFloat fontSize;
    CGFloat captionHeight;
    CGFloat captionGap;
    CGFloat sectionGap;
    CGFloat top;
    CGFloat bottom;
    CGFloat preeditHeight;
    CGFloat rowHeight;
    CGFloat decorationHeight;
    CGFloat panelHeight;
    CGFloat horizontalHeight;
    CGFloat verticalHeight;
    CGFloat toolbarHeight;
    CGFloat totalHeight;
};

SkinPreviewMetrics MakeShowcaseMetrics(CGFloat candidateFontSize, CGFloat decorationTop)
{
    SkinPreviewMetrics metrics;
    metrics.fontSize = MIN(candidateFontSize, 15.0);
    NSFont *font = [NSFont systemFontOfSize:metrics.fontSize weight:NSFontWeightRegular];
    metrics.captionHeight = 16.0;
    metrics.captionGap = 4.0;
    metrics.sectionGap = 10.0;
    metrics.top = 10.0;
    metrics.bottom = 14.0;
    metrics.preeditHeight = 22.0;
    metrics.rowHeight = ceil(font.ascender - font.descender + font.leading) + 8.0;
    metrics.decorationHeight = MAX(0.0, decorationTop);
    metrics.horizontalHeight = 6.0 + metrics.decorationHeight + metrics.preeditHeight + metrics.rowHeight + 6.0;
    metrics.verticalHeight = 6.0 + metrics.decorationHeight + metrics.preeditHeight + 4.0 * metrics.rowHeight + 6.0;
    metrics.toolbarHeight = 32.0;
    metrics.panelHeight = 0.0;
    metrics.totalHeight = metrics.top + metrics.captionHeight + metrics.captionGap + metrics.horizontalHeight +
                          metrics.sectionGap + metrics.captionHeight + metrics.captionGap + metrics.verticalHeight +
                          metrics.sectionGap + metrics.captionHeight + metrics.captionGap + metrics.toolbarHeight +
                          metrics.bottom;
    return metrics;
}

SkinPreviewMetrics MakeAppearanceMetrics(NSInteger panelStyle, NSInteger pageSize, CGFloat candidateFontSize,
                                         CGFloat decorationTop)
{
    SkinPreviewMetrics metrics;
    metrics.fontSize = MAX(12.0, candidateFontSize);
    NSFont *font = [NSFont systemFontOfSize:metrics.fontSize weight:NSFontWeightRegular];
    metrics.captionHeight = 16.0;
    metrics.captionGap = 4.0;
    metrics.sectionGap = 0.0;
    metrics.top = 10.0;
    metrics.bottom = 14.0;
    metrics.preeditHeight = 22.0;
    metrics.rowHeight = ceil(font.ascender - font.descender + font.leading) + 8.0;
    metrics.decorationHeight = MAX(0.0, decorationTop);
    const NSInteger visibleRows = panelStyle == 1 ? MIN(MAX(pageSize, (NSInteger)1), (NSInteger)5) : 1;
    const CGFloat footer = (panelStyle == 1 && pageSize > 5) ? 18.0 : 0.0;
    metrics.panelHeight =
        6.0 + metrics.decorationHeight + metrics.preeditHeight + visibleRows * metrics.rowHeight + footer + 6.0;
    metrics.horizontalHeight = 0.0;
    metrics.verticalHeight = 0.0;
    metrics.toolbarHeight = 0.0;
    metrics.totalHeight =
        metrics.top + metrics.captionHeight + metrics.captionGap + metrics.panelHeight + metrics.bottom;
    return metrics;
}

void DrawAlignedString(NSString *text, NSRect row, CGFloat x, NSDictionary *attributes)
{
    NSSize size = [text sizeWithAttributes:attributes];
    [text drawAtPoint:NSMakePoint(x, NSMinY(row) + (NSHeight(row) - size.height) / 2.0) withAttributes:attributes];
}

void DrawSelectedBar(NSRect row, const metasequoia::mac::SkinTokens &tokens, CGFloat fontSize)
{
    if (!tokens.showSelectedBar)
    {
        return;
    }
    const CGFloat barHeight = MAX(10.0, fontSize * 0.8);
    NSRect bar = NSMakeRect(NSMinX(row) + 3.0, NSMinY(row) + (NSHeight(row) - barHeight) / 2.0, 3.0, barHeight);
    [MetasequoiaColorFromRgba(tokens.accent) setFill];
    [[NSBezierPath bezierPathWithRoundedRect:bar xRadius:1.5 yRadius:1.5] fill];
}

void DrawDecoration(NSRect rect, const metasequoia::mac::ResolvedSkin &skin)
{
    if (skin.decorationTopDip <= 0.0 || skin.decorationPath.empty())
    {
        return;
    }
    NSImage *image = [[NSImage alloc] initWithContentsOfFile:@(skin.decorationPath.c_str())];
    if (image == nil)
    {
        return;
    }
    const CGFloat width =
        skin.decorationWidthDip > 0.0 ? skin.decorationWidthDip : MIN(NSWidth(rect), image.size.width);
    NSRect imageRect = NSMakeRect(NSMaxX(rect) - width, NSMinY(rect), width, skin.decorationTopDip);
    [image drawInRect:imageRect
              fromRect:NSZeroRect
             operation:NSCompositingOperationSourceOver
              fraction:1.0
        respectFlipped:YES
                 hints:nil];
}

void DrawPreviewCandidates(NSRect rect, const metasequoia::mac::ResolvedSkin &skin, BOOL vertical,
                           NSArray<NSString *> *words, CGFloat fontSize, NSString *footer)
{
    const metasequoia::mac::SkinTokens &tokens = skin.tokens;
    const CGFloat decorationTop = MAX(0.0, skin.decorationTopDip);
    DrawDecoration(rect, skin);
    NSRect chrome =
        NSMakeRect(NSMinX(rect), NSMinY(rect) + decorationTop, NSWidth(rect), NSHeight(rect) - decorationTop);
    DrawSkinChrome(chrome, tokens);
    NSBezierPath *clip = [NSBezierPath bezierPathWithRoundedRect:NSInsetRect(chrome, 1.0, 1.0)
                                                         xRadius:MAX(1.0, tokens.radius - 1.0)
                                                         yRadius:MAX(1.0, tokens.radius - 1.0)];
    [NSGraphicsContext saveGraphicsState];
    [clip addClip];

    NSFont *font = [NSFont systemFontOfSize:fontSize weight:NSFontWeightRegular];
    NSFont *preeditFont = [NSFont systemFontOfSize:MAX(11.0, fontSize - 3.0) weight:NSFontWeightRegular];
    NSFont *numberFont = [NSFont monospacedDigitSystemFontOfSize:MAX(10.0, fontSize - 4.0) weight:NSFontWeightRegular];
    NSDictionary *preeditAttributes = @{
        NSFontAttributeName : preeditFont,
        NSForegroundColorAttributeName : MetasequoiaColorFromRgba(tokens.text),
    };
    const CGFloat pad = 6.0;
    const CGFloat preeditHeight = 22.0;
    const CGFloat rowHeight = ceil(font.ascender - font.descender + font.leading) + 8.0;
    NSRect preeditRow =
        NSMakeRect(NSMinX(chrome) + pad, NSMinY(chrome) + pad, NSWidth(chrome) - pad * 2.0, preeditHeight);
    DrawAlignedString(@"nihao", preeditRow, NSMinX(preeditRow), preeditAttributes);
    const CGFloat caretX = NSMinX(preeditRow) + [@"nihao" sizeWithAttributes:preeditAttributes].width + 2.0;
    NSRect caret = NSMakeRect(caretX, NSMinY(preeditRow) + 3.0, 1.5, NSHeight(preeditRow) - 6.0);
    [MetasequoiaColorFromRgba(tokens.accent) setFill];
    NSRectFill(caret);

    const CGFloat textInset = 8.0 + (tokens.showSelectedBar ? 6.0 : 0.0);
    const CGFloat contentTop = NSMinY(chrome) + pad + preeditHeight;
    CGFloat x = NSMinX(chrome) + pad;
    const CGFloat maxX = NSMaxX(chrome) - pad;
    for (NSInteger index = 0; index < static_cast<NSInteger>(words.count); ++index)
    {
        const BOOL selected = index == 0;
        NSDictionary *numberAttributes = @{
            NSFontAttributeName : numberFont,
            NSForegroundColorAttributeName :
                MetasequoiaColorFromRgba(selected && tokens.selected.a >= 0.85f ? tokens.selectedText : tokens.number),
        };
        NSDictionary *wordAttributes = @{
            NSFontAttributeName : font,
            NSForegroundColorAttributeName : MetasequoiaColorFromRgba(selected ? tokens.selectedText : tokens.text),
        };
        NSString *number = [NSString stringWithFormat:@"%ld", static_cast<long>(index + 1)];
        NSString *word = words[index];
        const CGFloat numberWidth = [number sizeWithAttributes:numberAttributes].width;
        const CGFloat wordWidth = [word sizeWithAttributes:wordAttributes].width;
        const CGFloat itemWidth = textInset + numberWidth + 6.0 + wordWidth + 8.0;
        if (!vertical && x + itemWidth > maxX)
        {
            NSDictionary *ellipsisAttributes = @{
                NSFontAttributeName : font,
                NSForegroundColorAttributeName : MetasequoiaColorFromRgba(tokens.text),
            };
            NSSize ellipsisSize = [@"…" sizeWithAttributes:ellipsisAttributes];
            if (x + ellipsisSize.width <= maxX)
            {
                DrawAlignedString(@"…", NSMakeRect(x, contentTop, ellipsisSize.width, rowHeight), x,
                                  ellipsisAttributes);
            }
            break;
        }
        NSRect row = vertical ? NSMakeRect(NSMinX(chrome) + 4.0, contentTop + index * rowHeight, NSWidth(chrome) - 8.0,
                                           rowHeight)
                              : NSMakeRect(x, contentTop, itemWidth, rowHeight);
        if (NSMaxY(row) > NSMaxY(chrome) - 2.0)
        {
            break;
        }
        if (selected)
        {
            [MetasequoiaColorFromRgba(tokens.selected) setFill];
            [[NSBezierPath bezierPathWithRoundedRect:row xRadius:4.0 yRadius:4.0] fill];
            DrawSelectedBar(row, tokens, fontSize);
        }
        const CGFloat textX = NSMinX(row) + textInset;
        DrawAlignedString(number, row, textX, numberAttributes);
        DrawAlignedString(word, row, textX + numberWidth + 6.0, wordAttributes);
        if (!vertical)
        {
            x += itemWidth;
        }
    }
    if (footer.length > 0)
    {
        NSDictionary *footerAttributes = @{
            NSFontAttributeName : [NSFont systemFontOfSize:11.0 weight:NSFontWeightSemibold],
            NSForegroundColorAttributeName : [NSColor secondaryLabelColor],
        };
        NSSize footerSize = [footer sizeWithAttributes:footerAttributes];
        [footer drawAtPoint:NSMakePoint(NSMaxX(chrome) - footerSize.width - 12.0,
                                        NSMaxY(chrome) - footerSize.height - 8.0)
             withAttributes:footerAttributes];
    }
    [NSGraphicsContext restoreGraphicsState];
}

void DrawPreviewToolbar(NSRect rect, const metasequoia::mac::SkinTokens &tokens)
{
    DrawSkinChrome(rect, tokens);
    NSDictionary *attributes = @{
        NSFontAttributeName : [NSFont systemFontOfSize:13.0 weight:NSFontWeightMedium],
        NSForegroundColorAttributeName : MetasequoiaColorFromRgba(tokens.text),
    };
    NSArray<NSString *> *titles = @[ @"中", @"。", @"半", @"简", @"⚙" ];
    const CGFloat slot = NSWidth(rect) / titles.count;
    for (NSInteger index = 0; index < static_cast<NSInteger>(titles.count); ++index)
    {
        NSSize size = [titles[index] sizeWithAttributes:attributes];
        [titles[index] drawAtPoint:NSMakePoint(NSMinX(rect) + slot * index + (slot - size.width) / 2.0,
                                               NSMinY(rect) + (NSHeight(rect) - size.height) / 2.0)
                    withAttributes:attributes];
    }
}

NSArray<NSString *> *PreviewSamples()
{
    return @[
        @"水杉(Ss)", @"输入法(Sw)", @"你好(Nh)", @"世界(Sj)", @"中国(Zg)", @"水仙(Sx)", @"水山(Ss)", @"水衫(Ss)",
        @"水善(Ss)"
    ];
}
} // namespace

@implementation MetasequoiaCandidatePreviewView
{
    NSInteger _panelStyle;
    NSInteger _pageSize;
    CGFloat _candidateFontSize;
    NSString *_previewSkinId;
    NSString *_previewSkinsRoot;
    NSNumber *_forcedDark;
    BOOL _showsLayoutShowcase;
    NSLayoutConstraint *_heightConstraint;
}

- (instancetype)initWithFrame:(NSRect)frameRect
{
    self = [super initWithFrame:frameRect];
    if (self != nil)
    {
        self.translatesAutoresizingMaskIntoConstraints = NO;
        self.accessibilityLabel = @"候选窗口预览";
        self.accessibilityRole = NSAccessibilityGroupRole;
        _heightConstraint = [self.heightAnchor constraintEqualToConstant:190.0];
        _heightConstraint.active = YES;
        [self updatePanelStyle:0 pageSize:9 fontSize:18];
    }
    return self;
}

- (BOOL)isFlipped
{
    return YES;
}

- (void)reloadPreview
{
    _heightConstraint.constant = [self previewContentHeight];
    self.needsDisplay = YES;
}

- (void)setPreviewSkinId:(NSString *)skinId
{
    _previewSkinId = [skinId copy];
    [self reloadPreview];
}

- (NSString *)previewSkinId
{
    return _previewSkinId;
}

- (void)setShowsLayoutShowcase:(BOOL)showsLayoutShowcase
{
    _showsLayoutShowcase = showsLayoutShowcase;
    [self reloadPreview];
}

- (BOOL)previewUsesDark
{
    if (_forcedDark != nil)
    {
        return _forcedDark.boolValue;
    }
    return MetasequoiaAppearanceIsDark(NSAppearance.currentDrawingAppearance);
}

- (void)setPreviewSkinsRoot:(NSString *)path
{
    _previewSkinsRoot = [path copy];
    [self reloadPreview];
}

- (metasequoia::mac::ResolvedSkin)previewSkin
{
    NSString *skinId = _previewSkinId != nil ? _previewSkinId : MetasequoiaStoredCandidateSkin();
    if (_previewSkinsRoot != nil && skinId != nil)
        return metasequoia::mac::ResolveSkin(skinId.UTF8String, [self previewUsesDark], _previewSkinsRoot.fileSystemRepresentation);
    return MetasequoiaResolveCandidateSkin(skinId, [self previewUsesDark]);
}

- (NSColor *)previewCanvasFillColor
{
    return [self previewUsesDark] ? [NSColor colorWithSRGBRed:0.04 green:0.04 blue:0.05 alpha:1.0]
                                  : [NSColor colorWithSRGBRed:0.90 green:0.91 blue:0.92 alpha:1.0];
}

- (NSColor *)previewPanelFillColor
{
    return MetasequoiaColorFromRgba([self previewSkin].tokens.surface);
}

- (NSColor *)previewTextColor
{
    return MetasequoiaColorFromRgba([self previewSkin].tokens.text);
}

- (NSColor *)previewAccentColor
{
    return MetasequoiaColorFromRgba([self previewSkin].tokens.accent);
}

- (CGFloat)previewContentHeight
{
    const metasequoia::mac::ResolvedSkin skin = [self previewSkin];
    const CGFloat fontSize = _candidateFontSize > 0 ? _candidateFontSize : 18.0;
    if (_showsLayoutShowcase)
    {
        return MakeShowcaseMetrics(fontSize, skin.decorationTopDip).totalHeight;
    }
    return MakeAppearanceMetrics(_panelStyle, _pageSize, fontSize, skin.decorationTopDip).totalHeight;
}

- (void)toggleForcedTheme
{
    _forcedDark = @(![self previewUsesDark]);
    [self reloadPreview];
}

- (NSString *)forcedThemeButtonTitle
{
    return [self previewUsesDark] ? @"预览浅色" : @"预览深色";
}

- (void)updatePanelStyle:(NSInteger)panelStyle pageSize:(NSInteger)pageSize fontSize:(NSInteger)fontSize
{
    _panelStyle = panelStyle;
    _pageSize = pageSize;
    _candidateFontSize = fontSize;
    NSString *layout = panelStyle == 1 ? @"纵向列表" : @"横向排列";
    self.accessibilityValue = [NSString
        stringWithFormat:@"%@，%ld 个候选，%ld pt", layout, static_cast<long>(pageSize), static_cast<long>(fontSize)];
    self.accessibilityHelp = @"预览会随候选排列、每页候选和候选字号实时变化";
    [self reloadPreview];
}

- (void)drawRect:(NSRect)dirtyRect
{
    [super drawRect:dirtyRect];
    NSRect canvas = NSInsetRect(self.bounds, 1.0, 1.0);
    NSBezierPath *canvasPath = [NSBezierPath bezierPathWithRoundedRect:canvas xRadius:12.0 yRadius:12.0];
    [[self previewCanvasFillColor] setFill];
    [canvasPath fill];
    [[NSColor separatorColor] setStroke];
    canvasPath.lineWidth = 1.0;
    [canvasPath stroke];
    [NSGraphicsContext saveGraphicsState];
    [canvasPath addClip];

    NSDictionary<NSAttributedStringKey, id> *captionAttributes = @{
        NSFontAttributeName : [NSFont systemFontOfSize:11.0 weight:NSFontWeightSemibold],
        NSForegroundColorAttributeName : [NSColor secondaryLabelColor],
    };
    const metasequoia::mac::ResolvedSkin skin = [self previewSkin];
    if (_showsLayoutShowcase)
    {
        const SkinPreviewMetrics metrics = MakeShowcaseMetrics(_candidateFontSize, skin.decorationTopDip);
        NSArray<NSString *> *samples = PreviewSamples();
        NSArray<NSString *> *horizontal = [samples subarrayWithRange:NSMakeRange(0, 5)];
        NSArray<NSString *> *vertical = [samples subarrayWithRange:NSMakeRange(0, 4)];
        CGFloat y = metrics.top;
        [@"横排候选" drawAtPoint:NSMakePoint(14.0, y) withAttributes:captionAttributes];
        y += metrics.captionHeight + metrics.captionGap;
        DrawPreviewCandidates(NSMakeRect(14.0, y, NSWidth(self.bounds) - 28.0, metrics.horizontalHeight), skin, NO,
                              horizontal, metrics.fontSize, nil);
        y += metrics.horizontalHeight + metrics.sectionGap;
        [@"竖排候选" drawAtPoint:NSMakePoint(14.0, y) withAttributes:captionAttributes];
        y += metrics.captionHeight + metrics.captionGap;
        DrawPreviewCandidates(NSMakeRect(14.0, y, NSWidth(self.bounds) - 28.0, metrics.verticalHeight), skin, YES,
                              vertical, metrics.fontSize, nil);
        y += metrics.verticalHeight + metrics.sectionGap;
        [@"悬浮状态栏" drawAtPoint:NSMakePoint(14.0, y) withAttributes:captionAttributes];
        y += metrics.captionHeight + metrics.captionGap;
        DrawPreviewToolbar(NSMakeRect(14.0, y, 252.0, metrics.toolbarHeight), skin.tokens);
        [NSGraphicsContext restoreGraphicsState];
        return;
    }

    const SkinPreviewMetrics metrics =
        MakeAppearanceMetrics(_panelStyle, _pageSize, _candidateFontSize, skin.decorationTopDip);
    NSArray<NSString *> *samples = PreviewSamples();
    const NSInteger count = MIN(MAX(_pageSize, (NSInteger)1), static_cast<NSInteger>(samples.count));
    const BOOL vertical = _panelStyle == 1;
    const NSInteger visible = vertical ? MIN(count, 5) : count;
    NSArray<NSString *> *words = [samples subarrayWithRange:NSMakeRange(0, visible)];
    NSString *footer = (vertical && count > visible)
                           ? [NSString stringWithFormat:@"另有 %ld 个", static_cast<long>(count - visible)]
                           : nil;
    CGFloat y = metrics.top;
    [@"输入效果" drawAtPoint:NSMakePoint(14.0, y) withAttributes:captionAttributes];
    NSString *pageSummary = [NSString stringWithFormat:@"每页 %ld 个", static_cast<long>(_pageSize)];
    NSSize pageSummarySize = [pageSummary sizeWithAttributes:captionAttributes];
    [pageSummary drawAtPoint:NSMakePoint(NSMaxX(canvas) - pageSummarySize.width - 14.0, y)
              withAttributes:captionAttributes];
    y += metrics.captionHeight + metrics.captionGap;
    DrawPreviewCandidates(NSMakeRect(14.0, y, NSWidth(self.bounds) - 28.0, metrics.panelHeight), skin, vertical, words,
                          metrics.fontSize, footer);
    [NSGraphicsContext restoreGraphicsState];
}

@end
