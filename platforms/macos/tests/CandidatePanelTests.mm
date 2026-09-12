#import "../src/CandidatePanel.h"
#import "../src/CandidateSkinAppearance.h"
#import "../src/CandidateAppearancePreferences.h"
#include "../src/StringConversion.h"
#include <stdexcept>

static void Require(bool condition, const char *message)
{
    if (!condition)
        throw std::runtime_error(message);
}

@interface CandidatePanelTestDelegate : NSObject <MetasequoiaCandidatePanelDelegate>
@property(nonatomic, strong) NSAttributedString *selection;
@property(nonatomic) NSUInteger nextPages;
@end
@implementation CandidatePanelTestDelegate
- (void)candidateSelected:(NSAttributedString *)candidate
{
    self.selection = candidate;
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
        Require(horizontalButton != nil && ![horizontalButton.accessibilityLabel containsString:@"metasequoia"],
                "A horizontal candidate window still presented the vertical-only gloss.");
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
