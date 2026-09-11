#import "../InputController.mm"
#include <cassert>

@interface ShortcutSession : NSObject
@property(nonatomic) uint32_t lastCommand;
@property(nonatomic) uint8_t lastCharacter;
@property(nonatomic) BOOL characterHandled;
@property(nonatomic, copy) NSString *editingText;
@property(nonatomic) BOOL finishFails;
@property(nonatomic) NSUInteger finishCount;
@property(nonatomic) BOOL englishMode;
@end
@implementation ShortcutSession
- (NSDictionary *)setEnglishMode:(BOOL)enabled error:(NSError **)error {
    (void)error;
    self.englishMode = enabled;
    return @{
        @"handled": @NO,
        @"commit": NSNull.null,
        @"view": @{@"editing_text": @"", @"caret_position": @0, @"candidates": @[]},
    };
}
- (NSDictionary *)setFocused:(BOOL)focused error:(NSError **)error {
    (void)error;
    return @{
        @"handled": @NO,
        @"commit": NSNull.null,
        @"view": @{@"focused": @(focused), @"editing_text": @"", @"caret_position": @0, @"candidates": @[]},
    };
}
- (NSDictionary *)setCharacterWidthFull:(BOOL)fullwidth error:(NSError **)error {
    (void)error;
    return @{@"handled": @NO, @"commit": NSNull.null,
             @"view": @{ @"full_width": @(fullwidth), @"editing_text": @"", @"caret_position": @0, @"candidates": @[] }};
}
- (NSDictionary *)setChinesePunctuationEnabled:(BOOL)enabled error:(NSError **)error {
    (void)error;
    return @{@"handled": @NO, @"commit": NSNull.null,
             @"view": @{ @"chinese_punctuation": @(enabled), @"editing_text": @"", @"caret_position": @0, @"candidates": @[] }};
}
- (NSDictionary *)command:(uint32_t)command error:(NSError **)error {
    (void)error;
    self.lastCommand = command;
    if (command == MSIME_FINISH_COMPOSITION) {
        self.finishCount += 1;
        if (self.finishFails) return nil;
    }
    return @{@"handled": @YES, @"commit": @"测试", @"view": @{@"editing_text": @"", @"caret_position": @0, @"candidates": @[]}};
}
- (NSDictionary *)typeASCII:(uint8_t)character shift:(BOOL)shift error:(NSError **)error {
    (void)shift;
    (void)error;
    self.lastCharacter = character;
    return @{
        @"handled": @(self.characterHandled),
        @"commit": self.characterHandled ? @"引擎" : NSNull.null,
        @"view": @{@"editing_text": self.editingText ?: @"", @"caret_position": @0, @"candidates": @[]},
    };
}
@end

@interface ShortcutClient : NSObject <MSIMETextClient>
@property(nonatomic, copy) NSString *committed;
@property(nonatomic, copy) NSString *marked;
@property(nonatomic, strong) NSMutableArray<NSString *> *commits;
@property(nonatomic) NSRect caret;
@end
@implementation ShortcutClient
- (instancetype)init {
    self = [super init];
    if (self) self.commits = [NSMutableArray array];
    return self;
}
- (NSDictionary *)attributesForCharacterIndex:(NSUInteger)index lineHeightRectangle:(NSRect *)rect {
    (void)index;
    *rect = self.caret;
    return @{};
}
- (void)insertText:(id)text replacementRange:(NSRange)range {
    (void)range;
    self.committed = text;
    if ([text isKindOfClass:NSString.class]) [self.commits addObject:text];
}
- (void)setMarkedText:(id)text selectionRange:(NSRange)selection replacementRange:(NSRange)range {
    (void)selection;
    (void)range;
    self.marked = text;
}
@end

@interface TestCandidatePanel : NSObject
@property(nonatomic, getter=isVisible) BOOL visible;
@end
@implementation TestCandidatePanel
- (void)orderOut:(id)sender { (void)sender; self.visible = NO; }
@end

@interface HiddenCandidatePanel : MSIMECandidatePanel
@property(nonatomic) BOOL requestedVisible;
@end
@implementation HiddenCandidatePanel
- (void)orderFrontRegardless { self.requestedVisible = YES; }
- (void)orderOut:(id)sender { (void)sender; self.requestedVisible = NO; }
@end

int main() {
    @autoreleasepool {
        [NSApplication sharedApplication];
        MSIMECandidatePanel *focusPanel = [[MSIMECandidatePanel alloc] initWithContentRect:NSZeroRect styleMask:NSWindowStyleMaskBorderless | NSWindowStyleMaskNonactivatingPanel backing:NSBackingStoreBuffered defer:NO];
        assert(!focusPanel.canBecomeKeyWindow && !focusPanel.canBecomeMainWindow);
        MSIMECandidateButton *focusButton = [[MSIMECandidateButton alloc] initWithFrame:NSZeroRect];
        assert(!focusButton.acceptsFirstResponder);
        assert([focusButton acceptsFirstMouse:nil]);
        assert(!MSIMEValidCaret(NSZeroRect));
        assert(!MSIMEValidCaret(NSMakeRect(NAN, 0, 1, 20)));
        assert(!MSIMEValidCaret(NSMakeRect(0, INFINITY, 1, 20)));
        assert(!MSIMEValidCaret(NSMakeRect(0, 0, INFINITY, 20)));
        assert(!MSIMEValidCaret(NSMakeRect(0, 0, 1, -1)));
        assert(MSIMEValidCaret(NSMakeRect(-500, -200, 0, 20)));
        assert(metasequoia::mac::NormalizeCandidateFontSize(16) == 16);
        assert(metasequoia::mac::NormalizeCandidateFontSize(20) == 20);
        assert(metasequoia::mac::NormalizeCandidateFontSize(17) == 18);
        assert(metasequoia::mac::IsVerticalCandidateOrientation(@"vertical"));
        assert(!metasequoia::mac::IsVerticalCandidateOrientation(@"horizontal"));
        NSRect bounds = NSMakeRect(0, 0, 1000, 800);
        assert(NSEqualPoints(MSIMECandidateOrigin(NSMakeRect(100, 500, 1, 20), NSMakeSize(200, 100), bounds), NSMakePoint(100, 396)));
        assert(NSEqualPoints(MSIMECandidateOrigin(NSMakeRect(950, 20, 1, 20), NSMakeSize(200, 100), bounds), NSMakePoint(800, 44)));
        // Oversized content anchors at the visible origin, never outside both edges.
        assert(NSEqualPoints(MSIMECandidateOrigin(NSMakeRect(950, 20, 1, 20), NSMakeSize(1200, 900), bounds), NSZeroPoint));
        bounds = NSMakeRect(-1000, -800, 1000, 800);
        assert(NSEqualPoints(MSIMECandidateOrigin(NSMakeRect(-50, -780, 1, 20), NSMakeSize(200, 100), bounds), NSMakePoint(-200, -756)));
        // Inject a session and client without registering a system input source.
        MSIMEInputController *controller = [MSIMEInputController alloc];
        ShortcutSession *session = [ShortcutSession new];
        ShortcutClient *client = [ShortcutClient new];
        [controller setValue:session forKey:@"session"];
        [controller setValue:client forKey:@"activeClient"];
        [controller setValue:@NO forKey:@"fullWidthInput"];
        NSEvent *fullWidthToggle = [NSEvent keyEventWithType:NSEventTypeKeyDown
                                                    location:NSZeroPoint
                                               modifierFlags:NSEventModifierFlagOption | NSEventModifierFlagShift
                                                   timestamp:0
                                                windowNumber:0
                                                     context:nil
                                                  characters:@"H"
                                 charactersIgnoringModifiers:@"h"
                                                     isARepeat:NO
                                                     keyCode:kVK_ANSI_H];
        MSIMEInputController *unpreparedController = [MSIMEInputController alloc];
        [unpreparedController setValue:@NO forKey:@"fullWidthInput"];
        assert([unpreparedController handleEvent:fullWidthToggle client:nil]);
        assert([[unpreparedController valueForKey:@"fullWidthInput"] boolValue]);
        [[NSUserDefaults standardUserDefaults] removeObjectForKey:@"MSIMEClientFullWidthInput"];
        assert([controller handleEvent:fullWidthToggle client:client]);
        assert([[NSUserDefaults standardUserDefaults] boolForKey:@"MSIMEClientFullWidthInput"]);
        assert([controller valueForKey:@"fullWidthInput"] != nil && [[controller valueForKey:@"fullWidthInput"] boolValue]);
        NSEvent *repeatToggle = [NSEvent keyEventWithType:NSEventTypeKeyDown
                                                 location:NSZeroPoint
                                            modifierFlags:NSEventModifierFlagOption | NSEventModifierFlagShift
                                                timestamp:0
                                             windowNumber:0
                                                  context:nil
                                               characters:@"H"
                              charactersIgnoringModifiers:@"h"
                                                isARepeat:YES
                                                  keyCode:kVK_ANSI_H];
        assert([controller handleEvent:repeatToggle client:client]);
        assert([[controller valueForKey:@"fullWidthInput"] boolValue]);
        session.characterHandled = NO;
        session.editingText = @"";
        client.commits = [NSMutableArray array];
        NSEvent *directCharacter = [NSEvent keyEventWithType:NSEventTypeKeyDown
                                                     location:NSZeroPoint
                                                modifierFlags:0
                                                    timestamp:0
                                                 windowNumber:0
                                                      context:nil
                                                   characters:@"a"
                                  charactersIgnoringModifiers:@"a"
                                                    isARepeat:NO
                                                      keyCode:0];
        assert([controller handleEvent:directCharacter client:client]);
        assert(session.lastCharacter == 'a');
        assert([client.commits.lastObject isEqualToString:@"ａ"]);
        session.characterHandled = YES;
        client.commits = [NSMutableArray array];
        assert([controller handleEvent:directCharacter client:client]);
        assert([client.commits.lastObject isEqualToString:@"引擎"]);
        session.characterHandled = NO;
        session.editingText = @"ni";
        client.commits = [NSMutableArray array];
        assert([controller handleEvent:directCharacter client:client]);
        assert(session.finishCount > 0);
        assert(client.commits.count == 2);
        assert([client.commits[0] isEqualToString:@"测试"] && [client.commits[1] isEqualToString:@"ａ"]);
        NSEvent *modifiedCharacter = [NSEvent keyEventWithType:NSEventTypeKeyDown
                                                        location:NSZeroPoint
                                                   modifierFlags:NSEventModifierFlagCommand
                                                       timestamp:0
                                                    windowNumber:0
                                                         context:nil
                                                      characters:@"a"
                                     charactersIgnoringModifiers:@"a"
                                                       isARepeat:NO
                                                         keyCode:0];
        client.commits = [NSMutableArray array];
        assert(![controller handleEvent:modifiedCharacter client:client]);
        assert(client.commits.count == 1 && [client.commits[0] isEqualToString:@"测试"]);
        [controller setValue:@YES forKey:@"inputModeShortcutEnabled"];
        NSEvent *inputModeToggle = [NSEvent keyEventWithType:NSEventTypeKeyDown
                                                     location:NSZeroPoint
                                                modifierFlags:NSEventModifierFlagShift
                                                    timestamp:0
                                                 windowNumber:0
                                                      context:nil
                                                   characters:@" "
                                  charactersIgnoringModifiers:@" "
                                                    isARepeat:NO
                                                      keyCode:kVK_Space];
        assert([controller handleEvent:inputModeToggle client:client]);
        assert([[controller valueForKey:@"englishMode"] boolValue] && session.englishMode);
        NSMenu *menu = [controller menu];
        #if MSIME_MACOS_VOICE_SERVICE
        assert(menu.numberOfItems == 7);
#else
        assert(menu.numberOfItems == 8);
#endif
        NSMenuItem *chineseItem = [menu itemAtIndex:0];
        NSMenuItem *englishItem = [menu itemAtIndex:1];
        assert([chineseItem.title isEqualToString:@"中文输入"] && chineseItem.state == NSControlStateValueOff);
        assert([englishItem.title isEqualToString:@"英文输入"] && englishItem.state == NSControlStateValueOn);
        session.lastCharacter = 0;
        assert(![controller handleEvent:directCharacter client:client]);
        assert(session.lastCharacter == 0);
        assert([controller handleEvent:inputModeToggle client:client]);
        assert(![[controller valueForKey:@"englishMode"] boolValue] && !session.englishMode);
        assert([menu itemAtIndex:2].isSeparatorItem);
        assert([[menu itemAtIndex:3].title isEqualToString:@"候选预览…"]);
        NSMenu *profiles = [menu itemAtIndex:7].submenu;
        assert(profiles.numberOfItems == 6);
        assert([[profiles itemAtIndex:3].representedObject isEqual:@"microsoft"]);
        [controller showShuangpinKeymap:[profiles itemAtIndex:3]];
        NSPanel *keymap = [controller valueForKey:@"keymapPanel"];
        assert(keymap.isVisible && keymap.contentView != nil);
        [controller hideShuangpinKeymap:nil];
        assert(!keymap.isVisible);
        menu = [controller menu];
        assert([menu itemAtIndex:0].state == NSControlStateValueOn && [menu itemAtIndex:1].state == NSControlStateValueOff);
        [controller setValue:@NO forKey:@"fullWidthInput"];
        [[NSUserDefaults standardUserDefaults] removeObjectForKey:@"MSIMEClientEnglishMode"];
        [[NSUserDefaults standardUserDefaults] removeObjectForKey:@"MSIMEClientFullWidthInput"];
        for (NSNumber *flags in @[@(NSEventModifierFlagCommand), @(NSEventModifierFlagControl), @(NSEventModifierFlagOption)]) {
            session.lastCommand = UINT32_MAX;
            client.committed = nil;
            client.marked = @"ceshi";
            NSEvent *event = [NSEvent keyEventWithType:NSEventTypeKeyDown location:NSZeroPoint modifierFlags:flags.unsignedIntegerValue timestamp:0 windowNumber:0 context:nil characters:@"a" charactersIgnoringModifiers:@"a" isARepeat:NO keyCode:0];
            assert(![controller handleEvent:event client:client]);
            assert(session.lastCommand == MSIME_FINISH_COMPOSITION);
            assert([client.committed isEqualToString:@"测试"]);
            assert(client.marked.length == 0);
        }
        TestCandidatePanel *panel = [TestCandidatePanel new];
        [controller setValue:panel forKey:@"panel"];
        [controller setValue:@YES forKey:@"verticalCandidates"];
        for (NSNumber *key in @[@123, @124]) {
            NSEvent *event = [NSEvent keyEventWithType:NSEventTypeKeyDown location:NSZeroPoint modifierFlags:0 timestamp:0 windowNumber:0 context:nil characters:@"" charactersIgnoringModifiers:@"" isARepeat:NO keyCode:key.unsignedShortValue];
            panel.visible = YES;
            session.lastCommand = UINT32_MAX;
            client.committed = nil;
            client.marked = @"ceshi";
            assert([controller handleEvent:event client:client]);
            assert(session.lastCommand == UINT32_MAX);
            assert(client.committed == nil && [client.marked isEqualToString:@"ceshi"]);
            panel.visible = NO;
            assert([controller handleEvent:event client:client]);
            assert(session.lastCommand == (key.unsignedShortValue == 123 ? MSIME_MOVE_LEFT : MSIME_MOVE_RIGHT));
        }
        for (NSNumber *vertical in @[@YES, @NO]) {
            [controller setValue:vertical forKey:@"verticalCandidates"];
            for (NSNumber *key in @[@123, @124, @126, @125, @115, @119]) {
                NSEvent *event = [NSEvent keyEventWithType:NSEventTypeKeyDown location:NSZeroPoint modifierFlags:0 timestamp:0 windowNumber:0 context:nil characters:@"" charactersIgnoringModifiers:@"" isARepeat:NO keyCode:key.unsignedShortValue];
                panel.visible = YES;
                session.lastCommand = UINT32_MAX;
                assert([controller handleEvent:event client:client]);
                uint32_t expected = UINT32_MAX;
                switch (key.unsignedShortValue) {
                    case 123: expected = vertical.boolValue ? UINT32_MAX : MSIME_PREVIOUS_CANDIDATE; break;
                    case 124: expected = vertical.boolValue ? UINT32_MAX : MSIME_NEXT_CANDIDATE; break;
                    case 126: expected = MSIME_PREVIOUS_CANDIDATE; break;
                    case 125: expected = MSIME_NEXT_CANDIDATE; break;
                    case 115: expected = MSIME_FIRST_CANDIDATE_ON_PAGE; break;
                    case 119: expected = MSIME_LAST_CANDIDATE_ON_PAGE; break;
                }
                assert(session.lastCommand == expected);
                if (key.intValue == 115 || key.intValue == 119) {
                    panel.visible = NO;
                    assert([controller handleEvent:event client:client]);
                    assert(session.lastCommand == (key.intValue == 115 ? MSIME_MOVE_HOME : MSIME_MOVE_END));
                }
            }
        }
        [controller setValue:@YES forKey:@"verticalCandidates"];
        HiddenCandidatePanel *layoutPanel = [[HiddenCandidatePanel alloc] initWithContentRect:NSZeroRect styleMask:NSWindowStyleMaskBorderless | NSWindowStyleMaskNonactivatingPanel backing:NSBackingStoreBuffered defer:NO];
        [controller setValue:layoutPanel forKey:@"panel"];
        client.caret = NSMakeRect(NSMidX(NSScreen.mainScreen.visibleFrame), NSMidY(NSScreen.mainScreen.visibleFrame), 1, 20);
        [controller setValue:@{@"candidates": @[@{@"text": @"测试", @"highlighted": @YES}]} forKey:@"view"];
        [controller renderCandidates];
        assert(layoutPanel.requestedVisible);
        CGFloat shortWidth = layoutPanel.frame.size.width;
        [controller setValue:@{@"candidates": @[@{@"text": @"合成候选布局测试文本", @"highlighted": @YES}]} forKey:@"view"];
        [controller renderCandidates];
        assert(layoutPanel.frame.size.width > shortWidth);
        NSButton *rendered = (NSButton *)layoutPanel.contentView.subviews.firstObject;
        assert(rendered.font.pointSize == 18);
        assert([rendered.toolTip isEqualToString:@"合成候选布局测试文本"]);
        assert(rendered.lineBreakMode == NSLineBreakByTruncatingTail);
        NSMutableDictionary *pageView = [@{
            @"session": @1,
            @"generation": @2,
            @"page": @0,
            @"page_count": @2,
            @"editing_text": @"ceshi",
            @"caret_position": @5,
            @"candidates": @[@{
                @"text": @"测试",
                @"highlighted": @YES,
                @"id": @{@"session": @1, @"generation": @2, @"index": @0},
            }],
        } mutableCopy];
        [controller setValue:pageView forKey:@"view"];
        [controller renderCandidates];
        NSButton *nextPage = nil;
        for (NSView *view in layoutPanel.contentView.subviews) {
            if ([view isKindOfClass:NSButton.class] && ((NSButton *)view).tag == -2) nextPage = (NSButton *)view;
        }
        assert(nextPage != nil && nextPage.enabled);
        session.lastCommand = UINT32_MAX;
        [controller changeCandidatePage:nextPage];
        assert(session.lastCommand == MSIME_NEXT_PAGE);
        pageView[@"page"] = @1;
        [controller setValue:pageView forKey:@"view"];
        [controller renderCandidates];
        NSButton *previousPage = nil;
        nextPage = nil;
        for (NSView *view in layoutPanel.contentView.subviews) {
            if (![view isKindOfClass:NSButton.class]) continue;
            if (((NSButton *)view).tag == -1) previousPage = (NSButton *)view;
            if (((NSButton *)view).tag == -2) nextPage = (NSButton *)view;
        }
        assert(previousPage != nil && previousPage.enabled && nextPage != nil && !nextPage.enabled);
        session.lastCommand = UINT32_MAX;
        [controller changeCandidatePage:previousPage];
        assert(session.lastCommand == MSIME_PREVIOUS_PAGE);
        pageView[@"page_count"] = @1;
        pageView[@"candidates"] = @[
            @{@"text": @"短", @"highlighted": @YES},
            @{@"text": @"一个更长的候选", @"highlighted": @NO},
        ];
        [controller setValue:@NO forKey:@"verticalCandidates"];
        [controller setValue:pageView forKey:@"view"];
        [controller renderCandidates];
        NSButton *firstHorizontal = (NSButton *)layoutPanel.contentView.subviews[0];
        NSButton *secondHorizontal = (NSButton *)layoutPanel.contentView.subviews[1];
        assert(NSMaxX(firstHorizontal.frame) <= NSMinX(secondHorizontal.frame));
        assert([secondHorizontal.toolTip isEqualToString:@"一个更长的候选"]);
        [controller setValue:@"wechat" forKey:@"candidateSkin"];
        [controller renderCandidates];
        assert([layoutPanel.contentView isKindOfClass:MSIMECandidateChromeView.class]);
        MSIMECandidateButton *skinButton = (MSIMECandidateButton *)layoutPanel.contentView.subviews.firstObject;
        assert(!skinButton.showSelectedBar);
        assert(skinButton.candidateHighlighted);
        assert(skinButton.fillColor.greenComponent > skinButton.fillColor.redComponent);
        [controller setValue:@YES forKey:@"verticalCandidates"];
        client.caret = NSZeroRect;
        [controller renderCandidates];
        assert(!layoutPanel.requestedVisible);
    }
    return 0;
}
