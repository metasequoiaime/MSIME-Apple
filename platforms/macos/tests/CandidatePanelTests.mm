#import "../src/CandidatePanel.h"
#import "../src/CandidateSkinAppearance.h"
#import "../src/CandidateAppearancePreferences.h"
#include "../src/CandidateGlossLayout.h"
#include "../src/StringConversion.h"
#include <stdexcept>

static void Require(bool condition, const char *message)
{
    if (!condition)
        throw std::runtime_error(message);
}

static NSButton *FirstCandidateButton(MetasequoiaCandidatePanel *panel)
{
    for (NSView *view in panel.window.contentView.subviews)
        if ([view isKindOfClass:NSButton.class] && view.tag == 0)
            return (NSButton *)view;
    Require(false, "The candidate window did not render its first candidate.");
    return nil;
}

static NSFont *CandidateButtonFont(MetasequoiaCandidatePanel *panel)
{
    return FirstCandidateButton(panel).font;
}

static NSBitmapImageRep *RenderCandidateButton(MetasequoiaCandidatePanel *panel)
{
    NSButton *button = FirstCandidateButton(panel);
    NSBitmapImageRep *render = [button bitmapImageRepForCachingDisplayInRect:button.bounds];
    [button cacheDisplayInRect:button.bounds toBitmapImageRep:render];
    return render;
}

// Whether two candidate renders paint the leading `width` points, where the candidate text goes, identically.
static bool CandidateRegionsMatch(NSBitmapImageRep *left, NSBitmapImageRep *right, CGFloat width)
{
    Require(left.size.width > 0.0 && right.size.width > 0.0, "A candidate render came back empty.");
    const CGFloat scale = left.pixelsWide / left.size.width;
    Require(fabs(right.pixelsWide / right.size.width - scale) < 0.01,
            "The two candidate renders used different backing scales.");
    const NSInteger columns = MIN(static_cast<NSInteger>(width * scale), MIN(left.pixelsWide, right.pixelsWide));
    const NSInteger rows = MIN(left.pixelsHigh, right.pixelsHigh);
    for (NSInteger y = 0; y < rows; ++y)
        for (NSInteger x = 0; x < columns; ++x)
            if (![[left colorAtX:x y:y] isEqual:[right colorAtX:x y:y]])
                return false;
    return true;
}

@interface CandidatePanelTestDelegate : NSObject <MetasequoiaCandidatePanelDelegate>
@property(nonatomic, strong) NSAttributedString *selection;
@property(nonatomic, strong) NSAttributedString *pinned;
@property(nonatomic) NSUInteger nextPages;
@end
@implementation CandidatePanelTestDelegate
- (void)candidateSelected:(NSAttributedString *)candidate
{
    self.selection = candidate;
}
- (void)candidatePinToggled:(NSAttributedString *)candidate
{
    self.pinned = candidate;
}
- (void)candidatePanelNextPage
{
    ++self.nextPages;
}
- (void)candidatePanelPreviousPage
{
}
@end

int main()
{
    @autoreleasepool
    {
        [NSApplication sharedApplication];
        MetasequoiaSetStoredCandidateSkin(@"fluent");
        MetasequoiaCandidatePanel *panel = [MetasequoiaCandidatePanel new];
        CandidatePanelTestDelegate *delegate = [CandidatePanelTestDelegate new];
        panel.delegate = delegate;
        NSMutableArray *candidates = [NSMutableArray array];
        for (NSUInteger index = 0; index < 9; ++index)
            [candidates addObject:[[NSAttributedString alloc]
                                      initWithString:[NSString stringWithFormat:@"候选%lu", (unsigned long)index]]];
        panel.panelType = kIMKSingleColumnScrollingCandidatePanel;
        [panel setCandidateData:candidates];
        const CGFloat nineHeight = panel.candidateFrame.size.height;
        [panel setCandidateData:[candidates subarrayWithRange:NSMakeRange(0, 7)]];
        const CGFloat sevenHeight = panel.candidateFrame.size.height;
        [panel setCandidateData:[candidates subarrayWithRange:NSMakeRange(0, 5)]];
        const CGFloat fiveHeight = panel.candidateFrame.size.height;
        Require(fiveHeight < sevenHeight && sevenHeight < nineHeight,
                "Vertical window did not shrink with candidate count.");
        Require(fiveHeight < nineHeight * 0.75, "Five-candidate window retained substantial empty row space.");
        [panel setCandidateData:@[ candidates[0] ]];
        Require(panel.candidateFrame.size.height < fiveHeight * 0.5, "A partial page retained the full page height.");
        panel.panelType = kIMKSingleRowSteppingCandidatePanel;
        [panel setCandidateData:candidates];
        const CGFloat nineWidth = panel.candidateFrame.size.width;
        [panel setCandidateData:[candidates subarrayWithRange:NSMakeRange(0, 5)]];
        Require(panel.candidateFrame.size.width < nineWidth, "Horizontal window did not shrink with candidate count.");
        const CGFloat smallHeight = panel.candidateFrame.size.height;
        [panel setAttributes:@{NSFontAttributeName : [NSFont systemFontOfSize:20]}];
        Require(panel.candidateFrame.size.height > smallHeight, "Candidate font size did not relayout the window.");
        Require(!panel.window.canBecomeKeyWindow && !panel.window.canBecomeMainWindow,
                "The candidate window can steal input focus.");
        Require([panel selectCandidateWithIdentifier:3] && panel.selectedCandidate == 3 &&
                    [panel.selectedCandidateString isEqual:candidates[3]],
                "Selection and displayed highlight disagree.");
        Require(![panel selectCandidateWithIdentifier:8], "A nonvisible candidate could be selected.");
        NSButton *candidateButton = nil;
        for (NSView *view in panel.window.contentView.subviews)
            if ([view isKindOfClass:NSButton.class] && view.tag == 3)
                candidateButton = (NSButton *)view;
        Require(candidateButton != nil, "No clickable candidate was rendered.");
        [candidateButton performClick:nil];
        Require([delegate.selection isEqual:candidates[3]], "Click did not return the original attributed candidate.");
        panel.hasNextPage = YES;
        for (NSView *view in panel.window.contentView.subviews)
            if ([view isKindOfClass:NSButton.class] && view.tag == -2)
                [(NSButton *)view performClick:nil];
        Require(delegate.nextPages == 1, "The visible next-page button did not route to the controller.");
        NSMutableString *longText = [NSMutableString string];
        for (NSUInteger index = 0; index < 200; ++index)
            [longText appendString:@"长候选"];
        NSAttributedString *longCandidate = [[NSAttributedString alloc] initWithString:longText];
        [panel setCandidateData:@[ longCandidate, longCandidate, longCandidate, longCandidate, longCandidate ]];
        Require(panel.candidateFrame.size.width <= NSScreen.mainScreen.visibleFrame.size.width,
                "Long candidates pushed the window beyond the screen width.");
        panel.panelType = kIMKSingleRowSteppingCandidatePanel;
        NSAttributedString *annotated = [[NSAttributedString alloc] initWithString:@"水杉(Ss)"];
        [panel setCandidateData:@[ annotated, annotated, annotated ]];
        NSButton *annotatedButton = nil;
        for (NSView *view in panel.window.contentView.subviews)
            if ([view isKindOfClass:NSButton.class] && view.tag == 0)
                annotatedButton = (NSButton *)view;
        Require(annotatedButton != nil, "The annotated candidate was not rendered.");
        NSDictionary *measure = @{NSFontAttributeName : annotatedButton.font};
        const CGFloat needed = 8.0 + 6.0 + [@"1" sizeWithAttributes:measure].width + 6.0 +
                               [@"水杉(Ss)" sizeWithAttributes:measure].width + 8.0;
        Require(annotatedButton.frame.size.width + 0.5 >= needed, "Fluent layout truncated helpcode annotations.");
        panel.panelType = kIMKSingleColumnScrollingCandidatePanel;
        NSAttributedString *plain = MetasequoiaIndexedCandidateString(@"水杉", 0);
        NSAttributedString *translated = MetasequoiaCandidateStringByAddingTranslation(
            MetasequoiaIndexedCandidateString(@"水杉", 0), @"metasequoia");
        [panel setCandidateData:@[ plain ]];
        const CGFloat withoutGloss = panel.candidateFrame.size.width;
        [panel setCandidateData:@[ translated ]];
        Require(panel.candidateFrame.size.width > withoutGloss, "A vertical gloss did not widen the candidate window.");
        Require([panel.selectedCandidateString.string isEqualToString:@"水杉"],
                "A gloss replaced the visible candidate text used for selection.");
        NSButton *translatedButton = nil;
        for (NSView *view in panel.window.contentView.subviews)
            if ([view isKindOfClass:NSButton.class] && view.tag == 0)
                translatedButton = (NSButton *)view;
        Require(translatedButton != nil && [translatedButton.accessibilityLabel containsString:@"metasequoia"],
                "The vertical gloss was not exposed to accessibility.");
        panel.panelType = kIMKSingleRowSteppingCandidatePanel;
        [panel setCandidateData:@[ translated ]];
        Require(![translatedButton.superview isEqual:panel.window.contentView],
                "Relayout did not replace the previous candidate buttons.");
        NSButton *horizontalButton = nil;
        for (NSView *view in panel.window.contentView.subviews)
            if ([view isKindOfClass:NSButton.class] && view.tag == 0)
                horizontalButton = (NSButton *)view;
        // 横排和竖排一样要出释义。
        Require(horizontalButton != nil && [horizontalButton.accessibilityLabel containsString:@"metasequoia"],
                "A horizontal candidate window dropped the gloss.");
        const CGFloat horizontalWithGloss = panel.candidateFrame.size.width;
        [panel setCandidateData:@[ plain ]];
        Require(horizontalWithGloss > panel.candidateFrame.size.width,
                "A horizontal gloss did not widen the candidate window.");
        [panel setCandidateData:@[ translated ]];
        // 释义垂直于候选的排列方向。横排把释义叠在词下面 —— 格宽是最宽那一行而不是三者之和,九个候选
        // 因此是 892pt 而不是放不下的 2322pt;竖排把释义排在同一行 —— 行高不变,只是变宽。反过来两种
        // 都爆,所以这两条断言各自钉住一个方向。
        {
            NSAttributedString *plainWord = MetasequoiaIndexedCandidateString(@"翻译", 0);
            NSAttributedString *glossed = MetasequoiaCandidateStringByAddingSecondaryTranslation(
                MetasequoiaCandidateStringByAddingTranslation(plainWord, @"translate"), @"翻訳");
            NSArray *plainPage = @[ plainWord, plainWord, plainWord ];
            NSArray *glossedPage = @[ glossed, glossed, glossed ];

            panel.panelType = kIMKSingleRowSteppingCandidatePanel;
            [panel setCandidateData:plainPage];
            const NSSize bareRow = panel.candidateFrame.size;
            [panel setCandidateData:glossedPage];
            const NSSize glossedRow = panel.candidateFrame.size;
            // 释义行一律占位,有没有内容都一样高 —— 模型几秒后才回,等答案到了再长高会让整条候选条
            // 在光标下当场跳一下。所以这里要的是「相等」,不是「更高」。
            Require(fabs(glossedRow.height - bareRow.height) < 0.5,
                    "A gloss changed the row height, so the strip jumps when the model answers.");
            Require(glossedRow.width < bareRow.width + 3.0 * metasequoia::mac::kCandidateGlossMaxWidth,
                    "A horizontal gloss widened the row as if it sat beside the word.");

            panel.panelType = kIMKSingleColumnScrollingCandidatePanel;
            [panel setCandidateData:plainPage];
            const NSSize bareColumn = panel.candidateFrame.size;
            // 按布局自己的公式算下界:词一行 + 两条释义各一行。插入的内边距只会让实际更高,所以这是
            // 一个安全的下界,同时把「三行叠」这件事本身钉住。
            NSFont *candidateFont = CandidateButtonFont(panel);
            NSFont *primaryFont = [NSFont systemFontOfSize:MAX(11.0, candidateFont.pointSize - 5.0)];
            NSFont *secondaryFont = [NSFont systemFontOfSize:MAX(11.0, candidateFont.pointSize - 6.0)];
            const CGFloat stackedLines =
                ceil(candidateFont.ascender - candidateFont.descender + candidateFont.leading) +
                ceil(primaryFont.ascender - primaryFont.descender + primaryFont.leading) +
                ceil(secondaryFont.ascender - secondaryFont.descender + secondaryFont.leading);
            Require(glossedRow.height >= stackedLines,
                    "A horizontal row is not tall enough to stack a word over two glosses.");
            [panel setCandidateData:glossedPage];
            const NSSize glossedColumn = panel.candidateFrame.size;
            Require(glossedColumn.width > bareColumn.width + 1.0, "A vertical gloss did not widen the window.");
            Require(glossedColumn.height < bareColumn.height + 3.0,
                    "A vertical gloss took its own line instead of sharing the row.");
        }

        // 一行放不下这一页时,整行等比压缩会把排在最前的长句和末尾的单字候选砍掉同样的比例 —— 用户看到的
        // 是第一条句子被省略号吃掉一截。完整显示比凑满一页更重要:显示出来的候选都是完整的,放不下的就不显示。
        {
            panel.panelType = kIMKSingleRowSteppingCandidatePanel;
            [panel setCandidateData:@[ MetasequoiaIndexedCandidateString(@"候选", 0) ]];
            NSFont *rowFont = CandidateButtonFont(panel);
            const CGFloat glyph = [@"水" sizeWithAttributes:@{NSFontAttributeName : rowFont}].width;
            Require(glyph > 0.0, "The candidate font measured an empty glyph.");
            const CGFloat available = MAX(80.0, NSScreen.mainScreen.visibleFrame.size.width - 20.0);
            NSString *sentence = [@"" stringByPaddingToLength:(NSUInteger)MAX(4.0, floor(available * 0.4 / glyph))
                                                   withString:@"水杉输入法" startingAtIndex:0];
            NSString *shortWord = [@"" stringByPaddingToLength:(NSUInteger)MAX(2.0, floor(available * 0.12 / glyph))
                                                    withString:@"候选" startingAtIndex:0];
            NSMutableArray *overflowing =
                [NSMutableArray arrayWithObject:MetasequoiaIndexedCandidateString(sentence, 0)];
            while (overflowing.count < 9)
                [overflowing addObject:MetasequoiaIndexedCandidateString(shortWord, overflowing.count)];
            [panel setCandidateData:overflowing];
            NSButton *sentenceButton = nil;
            NSUInteger rendered = 0;
            for (NSView *view in panel.window.contentView.subviews)
            {
                if (![view isKindOfClass:NSButton.class] || view.tag < 0)
                    continue;
                ++rendered;
                if (view.tag == 0)
                    sentenceButton = (NSButton *)view;
            }
            Require(sentenceButton != nil, "An overflowing row dropped the candidate at its head.");
            Require(sentenceButton.frame.size.width >=
                        [sentence sizeWithAttributes:@{NSFontAttributeName : rowFont}].width,
                    "An overflowing row truncated the sentence at its head.");
            Require(rendered < overflowing.count,
                    "An overflowing row kept every candidate instead of showing fewer whole ones.");
            Require(panel.candidateFrame.size.width <= NSScreen.mainScreen.visibleFrame.size.width,
                    "The fitted row pushed the window past the screen.");
            // 排在前面、能放下的候选都保持原宽度,不因为后面放不下而被压缩。
            for (NSView *view in panel.window.contentView.subviews)
            {
                if (![view isKindOfClass:NSButton.class] || view.tag <= 0)
                    continue;
                Require(view.frame.size.width >= [shortWord sizeWithAttributes:@{NSFontAttributeName : rowFont}].width,
                        "A candidate the row did show was still squeezed.");
            }
        }

        for (const CGFloat measured : {0.0, 40.0, 208.0, 292.0, 1000.0})
            Require(metasequoia::mac::CandidateGlossDrawnWidth(measured, 10000.0) +
                            2.0 * metasequoia::mac::kCandidateGlossGap <=
                        metasequoia::mac::CandidateGlossReservedWidth(measured) + 0.5,
                    "A gloss drew wider than the room the candidate layout reserves for it.");
        // english.db ships senses far wider than the room the layout sets aside for them, so what the button paints
        // over the candidate itself has to stay the same whether or not a gloss follows it.
        panel.panelType = kIMKSingleColumnScrollingCandidatePanel;
        NSString *longGloss = @"Huazhong University of Science and Technology";
        NSAttributedString *longWord = MetasequoiaIndexedCandidateString(@"华中科技大学", 0);
        [panel setCandidateData:@[ MetasequoiaCandidateStringByAddingTranslation(longWord, @"HUST") ]];
        NSFont *candidateFont = CandidateButtonFont(panel);
        NSBitmapImageRep *withShortGloss = RenderCandidateButton(panel);
        NSDictionary *glossMeasure =
            @{NSFontAttributeName : [NSFont systemFontOfSize:MAX(12.0, candidateFont.pointSize - 3.0)]};
        Require([longGloss sizeWithAttributes:glossMeasure].width > metasequoia::mac::kCandidateGlossMaxWidth,
                "The long-gloss fixture no longer exceeds the width a gloss may be drawn at.");
        [panel setCandidateData:@[ MetasequoiaCandidateStringByAddingTranslation(longWord, longGloss) ]];
        NSBitmapImageRep *withLongGloss = RenderCandidateButton(panel);
        const CGFloat textWidth =
            8.0 + 6.0 + [@"1  华中科技大学" sizeWithAttributes:@{NSFontAttributeName : candidateFont}].width;
        Require(CandidateRegionsMatch(withShortGloss, withLongGloss, textWidth),
                "A gloss longer than the reserved width overdrew the candidate itself.");
        panel.panelType = kIMKSingleRowSteppingCandidatePanel;
        [panel setCandidateData:[candidates subarrayWithRange:NSMakeRange(0, 5)]];
        for (NSScreen *screen in NSScreen.screens)
        {
            NSRect bounds = screen.visibleFrame;
            panel.caretRect = NSMakeRect(NSMaxX(bounds) - 2, NSMinY(bounds) + 2, 0, 20);
            [panel show:kIMKLocateCandidatesBelowHint];
            Require(NSContainsRect(bounds, panel.candidateFrame),
                    "A zero-width edge caret positioned the panel outside its screen.");
            [panel hide];
        }
        panel.caretRect = NSZeroRect;
        [panel show:kIMKLocateCandidatesBelowHint];
        Require(!panel.isVisible, "An invalid caret displayed a misplaced candidate window.");

        NSDictionary *originalAppearance = MetasequoiaAppearancePreferences();
        NSRect screen = NSScreen.mainScreen.visibleFrame;
        panel.caretRect = NSMakeRect(NSMinX(screen) + 50, NSMidY(screen), 1, 20);
        MetasequoiaSetAppearancePreference(@"followCaret", @NO);
        [panel show:kIMKLocateCandidatesBelowHint];
        NSPoint fixed = panel.candidateFrame.origin;
        panel.caretRect = NSOffsetRect(panel.caretRect, 100, 30);
        [panel show:kIMKLocateCandidatesBelowHint];
        Require(NSEqualPoints(fixed, panel.candidateFrame.origin), "A fixed candidate window followed the caret.");
        [panel hide];
        [panel show:kIMKLocateCandidatesBelowHint];
        Require(!NSEqualPoints(fixed, panel.candidateFrame.origin), "A new composition reused an old fixed anchor.");
        fixed = panel.candidateFrame.origin;
        MetasequoiaSetAppearancePreference(@"followCaret", @YES);
        panel.caretRect = NSOffsetRect(panel.caretRect, 70, 20);
        [panel show:kIMKLocateCandidatesBelowHint];
        Require(!NSEqualPoints(fixed, panel.candidateFrame.origin), "Re-enabling follow caret did not move the panel.");
        panel.preedit = @"ni'hao";
        MetasequoiaSetAppearancePreference(@"preeditSize", @10);
        CGFloat compactPreeditHeight = panel.candidateFrame.size.height;
        MetasequoiaSetAppearancePreference(@"preeditSize", @36);
        Require(panel.candidateFrame.size.height > compactPreeditHeight,
                "Preedit size did not resize the real window.");
        NSTextField *preedit = nil;
        for (NSView *view in panel.window.contentView.subviews)
            if ([view.accessibilityLabel isEqualToString:@"预编辑文本"])
                preedit = (NSTextField *)view;
        Require(preedit && preedit.font.pointSize == 36 && [preedit.stringValue isEqualToString:@"ni'hao"],
                "The real preedit did not preserve the snapshot text and configured font size.");
        MetasequoiaSetAppearancePreference(@"font", @"Menlo");
        MetasequoiaSetAppearancePreference(@"fallbackFont", @"PingFangSC-Regular");
        NSFont *font = MetasequoiaCandidateFont(24);
        Require([font.familyName isEqualToString:@"Menlo"] && font.pointSize == 24,
                "The chosen candidate font was not resolved.");
        Require([font.fontDescriptor objectForKey:NSFontCascadeListAttribute] != nil,
                "The supplementary font was not in the font cascade.");
        MetasequoiaSetAppearancePreference(@"textColor", @[ @0.1, @0.2, @0.3 ]);
        NSColor *text = MetasequoiaColorFromRgba(MetasequoiaResolveStoredCandidateSkin(NO).tokens.text);
        Require(std::abs(text.redComponent - 0.1) < 0.001, "Text color did not override the candidate skin.");
        MetasequoiaSetAppearancePreference(@"textColor", @[ @2, @0, @0 ]);
        Require(MetasequoiaCandidateTextColor() == nil, "An invalid stored color was accepted.");
        MetasequoiaSetAppearancePreference(@"theme", @2);
        Require(MetasequoiaAppearanceIsDark([NSAppearance appearanceNamed:NSAppearanceNameAqua]),
                "Forced dark theme was ignored.");
        MetasequoiaSetAppearancePreference(@"theme", @1);
        Require(!MetasequoiaAppearanceIsDark([NSAppearance appearanceNamed:NSAppearanceNameDarkAqua]),
                "Forced light theme was ignored.");
        [NSUserDefaults.standardUserDefaults setObject:originalAppearance forKey:MetasequoiaAppearancePreferencesKey];
        [panel hide];
        [panel setCandidateData:@[]];
        Require(!panel.isVisible && panel.selectedCandidate == NSNotFound, "Empty data retained a visible selection.");
    }
}
