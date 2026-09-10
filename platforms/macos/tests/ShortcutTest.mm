#import "../InputController.mm"
#include <cassert>
#include <fstream>


@interface ShortcutSession : NSObject
@property(nonatomic) uint32_t lastCommand;
@property(nonatomic, copy) NSDictionary *nextTransition;
@property(nonatomic) NSUInteger asciiCalls;
@property(nonatomic) uint8_t lastASCII;
@property(nonatomic) BOOL lastShift;
@property(nonatomic) uint8_t requestedPageSize;
@end
@implementation ShortcutSession
- (NSDictionary *)setCandidatePageSize:(uint8_t)size error:(NSError **)error {
    (void)error;
    self.requestedPageSize = size;
    return nil;
}
- (NSDictionary *)typeASCII:(uint8_t)ascii shift:(BOOL)shift error:(NSError **)error {
    (void)error;
    ++self.asciiCalls;
    self.lastASCII = ascii;
    self.lastShift = shift;
    return self.nextTransition;
}
- (NSDictionary *)command:(uint32_t)command error:(NSError **)error {
    (void)error;
    self.lastCommand = command;
    if (self.nextTransition) return self.nextTransition;
    return @{@"handled": @YES, @"commit": @"测试", @"view": @{@"editing_text": @"", @"caret_position": @0, @"candidates": @[]}};
}
@end

@interface ShortcutClient : NSObject <MSIMETextClient>
@property(nonatomic, copy) NSString *committed;
@property(nonatomic, copy) NSString *marked;
@property(nonatomic) NSRect caret;
@end
@implementation ShortcutClient
- (NSDictionary *)attributesForCharacterIndex:(NSUInteger)index lineHeightRectangle:(NSRect *)rect {
    (void)index;
    *rect = self.caret;
    return @{};
}
- (void)insertText:(id)text replacementRange:(NSRange)range {
    (void)range;
    self.committed = text;
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
- (BOOL)isVisible { return self.requestedVisible; }
- (void)orderFrontRegardless { self.requestedVisible = YES; }
- (void)orderOut:(id)sender { (void)sender; self.requestedVisible = NO; }
@end

static MSIMECandidateButton *PageButton(NSView *content, NSInteger tag) {
    for (NSView *view in content.subviews) {
        if ([view isKindOfClass:MSIMECandidateButton.class] && view.tag == tag) return (id)view;
    }
    return nil;
}

static void TestExternalSkin(MSIMEInputController *controller, HiddenCandidatePanel *panel, NSUserDefaults *defaults) {
    char temporary[] = "/tmp/msime-native-skin-XXXXXX";
    assert(mkdtemp(temporary));
    const std::filesystem::path root(temporary);
    std::filesystem::create_directory(root / "synthetic");
    {
        std::ofstream manifest(root / "synthetic" / "skin.toml");
        manifest << R"toml(schema_version = 1
id = "synthetic"
name = "Synthetic Skin"
version = "1.0"
base = "fluent"
preview = "decoration.png"
[supports]
layouts = ["horizontal", "vertical"]
themes = ["dark", "light"]
[candidate_window]
min_width_dip = 240
[candidate_window.decoration]
top_inset_dip = 48
width_dip = 120
[candidate.light]
surface = "#fff7fa"
selected = "#111111"
show_selected_bar = false
[candidate.dark]
surface = "#121314"
selected = "#ffffff"
show_selected_bar = true
)toml";
        assert(manifest.good());
    }
    NSBitmapImageRep *image = [[NSBitmapImageRep alloc] initWithBitmapDataPlanes:nullptr pixelsWide:4 pixelsHigh:4 bitsPerSample:8 samplesPerPixel:4 hasAlpha:YES isPlanar:NO colorSpaceName:NSDeviceRGBColorSpace bytesPerRow:0 bitsPerPixel:0];
    for (NSInteger y = 0; y < 4; ++y) for (NSInteger x = 0; x < 4; ++x) {
        unsigned char *pixel = image.bitmapData + y * image.bytesPerRow + x * 4;
        pixel[0] = 255; pixel[1] = 0; pixel[2] = 0; pixel[3] = 255;
    }
    image = [image bitmapImageRepByRetaggingWithColorSpace:NSColorSpace.sRGBColorSpace];
    assert(image);
    assert([[image representationUsingType:NSBitmapImageFileTypePNG properties:@{}] writeToFile:@((root / "synthetic" / "decoration.png").c_str()) atomically:YES]);
    MSIMEAppearancePreferences *external = [[MSIMEAppearancePreferences alloc] initWithDefaults:defaults skinsRoot:[NSURL fileURLWithPath:@(root.c_str()) isDirectory:YES]];
    NSGridView *grid = (id)external.window.contentView.subviews.firstObject;
    NSPopUpButton *control = (id)[grid cellAtColumnIndex:1 rowIndex:4].contentView;
    assert(control.numberOfItems == 5 && [control.lastItem.title isEqual:@"Synthetic Skin"]);
    [control selectItemAtIndex:4];
    [NSApp sendAction:control.action to:control.target from:control];
    assert([external.skinID isEqual:@"synthetic"] && external.decorationImage);
    MSIMEAppearancePreferences *loaded = [[MSIMEAppearancePreferences alloc] initWithDefaults:defaults skinsRoot:external.skinsRoot];
    assert([loaded.skinID isEqual:@"synthetic"] && [loaded resolvedSkinForDark:NO].id == "synthetic");
    NSDictionary *before = [[controller valueForKey:@"view"] copy];
    [controller setValue:external forKey:@"appearance"];
    for (NSNumber *vertical in @[@NO, @YES]) {
        external.vertical = vertical.boolValue;
        for (NSString *theme in @[NSAppearanceNameAqua, NSAppearanceNameDarkAqua]) {
            panel.appearance = [NSAppearance appearanceNamed:theme];
            [controller appearanceChanged:nil];
            MSIMECandidateChromeView *chrome = (id)panel.contentView;
            NSImageView *decoration = (id)chrome.subviews.lastObject;
            assert([decoration isKindOfClass:NSImageView.class] && decoration.image);
            assert(panel.frame.size.width >= 240);
            assert(decoration.frame.size.width == 120 && decoration.frame.size.height == 48);
            assert(NSMaxX(decoration.frame) == chrome.bounds.size.width && NSMaxY(decoration.frame) == chrome.bounds.size.height);
            MSIMECandidateButton *first = PageButton(chrome, 0);
            assert(NSMaxY(first.frame) <= NSMinY(decoration.frame));
            assert(first.showSelectedBar == [theme isEqual:NSAppearanceNameDarkAqua]);
            const auto tokens = [external resolvedSkinForDark:[theme isEqual:NSAppearanceNameDarkAqua]].tokens;
            assert([chrome.fillColor isEqual:SkinColor(tokens.surface)]);
            assert([first.titleColor isEqual:SkinColor(tokens.selectedText)]);
            NSBitmapImageRep *bitmap = [chrome bitmapImageRepForCachingDisplayInRect:chrome.bounds];
            [chrome cacheDisplayInRect:chrome.bounds toBitmapImageRep:bitmap];
            assert(bitmap && [[controller valueForKey:@"view"] isEqual:before]);
        }
    }
    // No disk reads while typing/rendering: removal takes effect only on explicit reload.
    std::filesystem::remove_all(root / "synthetic");
    [controller renderCandidates];
    assert([external resolvedSkinForDark:NO].id == "synthetic" && external.decorationImage);
    NSButton *reload = (id)[grid cellAtColumnIndex:1 rowIndex:5].contentView;
    [NSApp sendAction:reload.action to:reload.target from:reload];
    assert([external.skinID isEqual:@"synthetic"]);
    assert([external resolvedSkinForDark:NO].id == "fluent" && !external.decorationImage);
    assert(control.numberOfItems == 4 && [control.selectedItem.representedObject isEqual:@"fluent"]);
    [controller appearanceChanged:nil];
    for (NSView *view in panel.contentView.subviews) assert(![view isKindOfClass:NSImageView.class]);
    panel.appearance = nil;
    std::filesystem::remove_all(root);
}

int main() {
    @autoreleasepool {
        [NSApplication sharedApplication];
        NSString *suite = [@"app.msime.test.appearance." stringByAppendingString:NSUUID.UUID.UUIDString];
        NSUserDefaults *defaults = [[NSUserDefaults alloc] initWithSuiteName:suite];
        MSIMEAppearancePreferences *appearance = [[MSIMEAppearancePreferences alloc] initWithDefaults:defaults];
        assert(!appearance.vertical && appearance.fontSize == 18);
        assert(appearance.pageShortcut == 0);
        assert(appearance.pageSize == 9);
        assert([appearance.skinID isEqual:@"fluent"]);
        appearance.skinID = @"../invalid";
        assert([appearance.skinID isEqual:@"fluent"]);
        appearance.pageSize = 6;
        assert(appearance.pageSize == 9);
        appearance.pageShortcut = 99;
        assert(appearance.pageShortcut == 0);
        appearance.fontSize = 99;
        assert(appearance.fontSize == 18);
        NSGridView *grid = (id)appearance.window.contentView.subviews.firstObject;
        NSPopUpButton *layoutControl = (id)[grid cellAtColumnIndex:1 rowIndex:0].contentView;
        NSPopUpButton *fontControl = (id)[grid cellAtColumnIndex:1 rowIndex:1].contentView;
        NSPopUpButton *shortcutControl = (id)[grid cellAtColumnIndex:1 rowIndex:2].contentView;
        NSPopUpButton *sizeControl = (id)[grid cellAtColumnIndex:1 rowIndex:3].contentView;
        NSPopUpButton *skinControl = (id)[grid cellAtColumnIndex:1 rowIndex:4].contentView;
        assert(([skinControl.itemTitles isEqual:@[@"Fluent", @"微信绿", @"石墨 Graphite", @"杨柳青"]]));
        NSArray<NSString *> *skinIDs = @[@"fluent", @"wechat", @"graphite", @"willow_green"];
        for (NSInteger option = 0; option < 4; ++option) {
            [skinControl selectItemAtIndex:option];
            [NSApp sendAction:skinControl.action to:skinControl.target from:skinControl];
            MSIMEAppearancePreferences *loaded = [[MSIMEAppearancePreferences alloc] initWithDefaults:defaults];
            assert([loaded.skinID isEqual:skinIDs[option]]);
        }
        appearance.skinID = @"fluent";
        assert(([sizeControl.itemTitles isEqual:@[@"5 个", @"7 个", @"9 个"]]));
        for (NSInteger option = 0; option < 3; ++option) {
            [sizeControl selectItemAtIndex:option];
            [NSApp sendAction:sizeControl.action to:sizeControl.target from:sizeControl];
            MSIMEAppearancePreferences *loaded = [[MSIMEAppearancePreferences alloc] initWithDefaults:defaults];
            assert(loaded.pageSize == (option == 0 ? 5 : option == 1 ? 7 : 9));
        }
        assert(([shortcutControl.itemTitles isEqual:@[@"- / =", @"[ / ]", @"Page Up / Page Down"]]));
        for (NSInteger option = 0; option < 3; ++option) {
            [shortcutControl selectItemAtIndex:option];
            [NSApp sendAction:shortcutControl.action to:shortcutControl.target from:shortcutControl];
            MSIMEAppearancePreferences *loaded = [[MSIMEAppearancePreferences alloc] initWithDefaults:defaults];
            assert(loaded.pageShortcut == option);
        }
        appearance.pageShortcut = 0;
        assert(([layoutControl.itemTitles isEqual:@[@"横向排列", @"纵向列表"]]));
        [layoutControl selectItemAtIndex:1];
        [NSApp sendAction:layoutControl.action to:layoutControl.target from:layoutControl];
        [fontControl selectItemAtIndex:0];
        [NSApp sendAction:fontControl.action to:fontControl.target from:fontControl];
        MSIMEAppearancePreferences *reopened = [[MSIMEAppearancePreferences alloc] initWithDefaults:defaults];
        assert(reopened.vertical && reopened.fontSize == 16);
        appearance.fontSize = 18;
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
        [controller setValue:appearance forKey:@"appearance"];
        [controller syncPageSize];
        assert(session.requestedPageSize == 9);
        appearance.pageSize = 5;
        [controller appearanceChanged:nil];
        assert(session.requestedPageSize == 5);
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
        HiddenCandidatePanel *layoutPanel = [[HiddenCandidatePanel alloc] initWithContentRect:NSZeroRect styleMask:NSWindowStyleMaskBorderless | NSWindowStyleMaskNonactivatingPanel backing:NSBackingStoreBuffered defer:NO];
        for (NSNumber *key in @[@115, @119]) {
            NSEvent *event = [NSEvent keyEventWithType:NSEventTypeKeyDown location:NSZeroPoint modifierFlags:0 timestamp:0 windowNumber:0 context:nil characters:@"" charactersIgnoringModifiers:@"" isARepeat:NO keyCode:key.unsignedShortValue];
            panel.visible = YES;
            assert([controller handleEvent:event client:client]);
            assert(session.lastCommand == (key.unsignedShortValue == 115 ? MSIME_FIRST_CANDIDATE_ON_PAGE : MSIME_LAST_CANDIDATE_ON_PAGE));
            panel.visible = NO;
            assert([controller handleEvent:event client:client]);
            assert(session.lastCommand == (key.unsignedShortValue == 115 ? MSIME_MOVE_HOME : MSIME_MOVE_END));
        }
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
        client.caret = NSZeroRect;
        [controller renderCandidates];
        assert(!layoutPanel.requestedVisible);
        client.caret = NSMakeRect(NSMidX(NSScreen.mainScreen.visibleFrame), NSMidY(NSScreen.mainScreen.visibleFrame), 1, 20);
        NSMutableDictionary *pageView = [@{@"session": @1, @"generation": @2, @"focused": @YES, @"page": @0, @"page_count": @3, @"editing_text": @"ceshi", @"caret_position": @5, @"candidates": @[@{@"text": @"测试", @"highlighted": @YES}]} mutableCopy];
        [controller setValue:[pageView copy] forKey:@"view"];
        [controller renderCandidates];
        MSIMECandidateButton *previous = (id)PageButton(layoutPanel.contentView, -1);
        MSIMECandidateButton *next = (id)PageButton(layoutPanel.contentView, -2);
        assert(previous && next && !previous.enabled && next.enabled);
        assert([previous.accessibilityLabel isEqual:@"上一页候选"]);
        assert([next.accessibilityLabel isEqual:@"下一页候选"]);
        assert(previous.frame.size.height == 26 && next.frame.size.width == 28);
        pageView[@"page"] = @1;
        session.nextTransition = @{@"handled": @YES, @"commit": NSNull.null, @"view": [pageView copy]};
        client.committed = nil;
        [next performClick:nil];
        assert(session.lastCommand == MSIME_NEXT_PAGE && client.committed == nil);
        assert([client.marked isEqual:@"ceshi"]);
        // A previous page's retained button must not advance the current page.
        session.lastCommand = UINT32_MAX;
        [controller changeCandidatePage:next];
        assert(session.lastCommand == UINT32_MAX);
        previous = (id)PageButton(layoutPanel.contentView, -1);
        next = (id)PageButton(layoutPanel.contentView, -2);
        assert(previous.enabled && next.enabled);
        pageView[@"page"] = @0;
        session.nextTransition = @{@"handled": @YES, @"commit": NSNull.null, @"view": [pageView copy]};
        [previous performClick:nil];
        assert(session.lastCommand == MSIME_PREVIOUS_PAGE);
        for (NSString *changed in @[@"session", @"generation", @"focused"]) {
            [controller setValue:[pageView copy] forKey:@"view"];
            [controller renderCandidates];
            next = (id)PageButton(layoutPanel.contentView, -2);
            NSMutableDictionary *stale = [pageView mutableCopy];
            stale[changed] = [changed isEqual:@"focused"] ? @NO : @99;
            [controller setValue:stale forKey:@"view"];
            session.lastCommand = UINT32_MAX;
            [controller changeCandidatePage:next];
            assert(session.lastCommand == UINT32_MAX);
        }
        pageView[@"page"] = @2;
        [controller setValue:[pageView copy] forKey:@"view"];
        [controller renderCandidates];
        previous = (id)PageButton(layoutPanel.contentView, -1);
        next = (id)PageButton(layoutPanel.contentView, -2);
        assert(previous.enabled && !next.enabled);
        session.lastCommand = UINT32_MAX;
        [controller changeCandidatePage:next];
        assert(session.lastCommand == UINT32_MAX);
        [layoutPanel orderOut:nil];
        [controller changeCandidatePage:previous];
        assert(session.lastCommand == UINT32_MAX);
        pageView[@"page"] = @0;
        pageView[@"page_count"] = @1;
        [controller setValue:pageView forKey:@"view"];
        [controller renderCandidates];
        assert(PageButton(layoutPanel.contentView, -1) == nil);
        assert(PageButton(layoutPanel.contentView, -2) == nil);
        pageView[@"candidates"] = @[@{@"text": @"测试", @"highlighted": @YES, @"id": @{@"session": @1, @"generation": @2, @"index": @0}}, @{@"text": @"布局", @"highlighted": @NO, @"id": @{@"session": @1, @"generation": @2, @"index": @1}}];
        [controller setValue:pageView forKey:@"view"];
        [controller renderCandidates];
        CGFloat verticalHeight = layoutPanel.frame.size.height;
        appearance.vertical = NO;
        session.lastCommand = UINT32_MAX;
        [controller appearanceChanged:nil];
        assert(session.lastCommand == UINT32_MAX);
        assert(layoutPanel.frame.size.height < verticalHeight);
        NSView *first = layoutPanel.contentView.subviews[0];
        NSView *second = layoutPanel.contentView.subviews[1];
        assert(first.frame.origin.y == second.frame.origin.y);
        assert(NSMaxX(first.frame) == NSMinX(second.frame));
        CGFloat normalHeight = layoutPanel.frame.size.height;
        appearance.fontSize = 20;
        [controller appearanceChanged:nil];
        assert(layoutPanel.frame.size.height > normalHeight);
        // Palette and native drawing coverage: four skins, two layouts and both appearances.
        NSDictionary *preservedView = [[controller valueForKey:@"view"] copy];
        session.lastCommand = UINT32_MAX;
        for (NSString *skinID in skinIDs) {
            appearance.skinID = skinID;
            for (NSNumber *vertical in @[@NO, @YES]) {
                appearance.vertical = vertical.boolValue;
                [controller appearanceChanged:nil];
                for (NSString *theme in @[NSAppearanceNameAqua, NSAppearanceNameDarkAqua]) {
                    MSIMECandidateChromeView *chrome = (id)layoutPanel.contentView;
                    chrome.appearance = [NSAppearance appearanceNamed:theme];
                    // Exercise the same callback AppKit uses for a system appearance change.
                    [chrome viewDidChangeEffectiveAppearance];
                    const auto tokens = msime::mac::BuiltInSkinTokens(skinID.UTF8String, [theme isEqual:NSAppearanceNameDarkAqua]);
                    assert([chrome.fillColor isEqual:SkinColor(tokens.surface)]);
                    assert([chrome.strokeColor isEqual:SkinColor(tokens.border)]);
                    assert(chrome.cornerRadius == tokens.radius && chrome.lineWidth == tokens.borderWidth);
                    assert(!chrome.isOpaque && !layoutPanel.isOpaque);
                    MSIMECandidateButton *selected = (id)chrome.subviews[0];
                    MSIMECandidateButton *unselected = (id)chrome.subviews[1];
                    assert(selected.candidateHighlighted && !unselected.candidateHighlighted);
                    assert([selected.candidateID isEqual:preservedView[@"candidates"][0][@"id"]]);
                    assert([unselected.candidateID isEqual:preservedView[@"candidates"][1][@"id"]]);
                    assert([selected.fillColor isEqual:SkinColor(tokens.selected)]);
                    assert([selected.titleColor isEqual:SkinColor(tokens.selectedText)]);
                    assert([unselected.titleColor isEqual:SkinColor(tokens.text)]);
                    assert([unselected.numberColor isEqual:SkinColor(tokens.number)]);
                    assert(selected.showSelectedBar == tokens.showSelectedBar);
                    NSBitmapImageRep *bitmap = [chrome bitmapImageRepForCachingDisplayInRect:chrome.bounds];
                    assert(bitmap);
                    [chrome cacheDisplayInRect:chrome.bounds toBitmapImageRep:bitmap];
                    assert(bitmap.pixelsWide > 0 && bitmap.pixelsHigh > 0);
                    assert([[controller valueForKey:@"view"] isEqual:preservedView]);
                    assert(session.lastCommand == UINT32_MAX);
                    assert(!layoutPanel.canBecomeKeyWindow && !selected.acceptsFirstResponder);
                }
            }
        }
        TestExternalSkin(controller, layoutPanel, defaults);
        [controller setValue:appearance forKey:@"appearance"];
        appearance.vertical = NO;
        appearance.skinID = @"fluent";
        [controller appearanceChanged:nil];
        for (NSNumber *key in @[@123, @124, @125, @126]) {
            layoutPanel.requestedVisible = YES;
            session.lastCommand = UINT32_MAX;
            NSEvent *event = [NSEvent keyEventWithType:NSEventTypeKeyDown location:NSZeroPoint modifierFlags:0 timestamp:0 windowNumber:0 context:nil characters:@"" charactersIgnoringModifiers:@"" isARepeat:NO keyCode:key.unsignedShortValue];
            assert([controller handleEvent:event client:client]);
            uint32_t expected = key.unsignedShortValue == 123 ? MSIME_PREVIOUS_CANDIDATE : key.unsignedShortValue == 124 ? MSIME_NEXT_CANDIDATE : UINT32_MAX;
            assert(session.lastCommand == expected);
        }
        assert([controller menu].numberOfItems == 1);
        for (NSInteger option = 0; option < 3; ++option) {
            appearance.pageShortcut = option;
            NSArray *plain = @[@"-", @"=", @"[", @"]"];
            NSArray *shifted = @[@"_", @"+", @"{", @"}"];
            for (NSUInteger i = 0; i < plain.count; ++i) {
                for (NSNumber *visible in @[@NO, @YES]) {
                    for (NSNumber *shift in @[@NO, @YES]) {
                        layoutPanel.requestedVisible = visible.boolValue;
                        session.lastCommand = UINT32_MAX;
                        session.asciiCalls = 0;
                        NSString *characters = shift.boolValue ? shifted[i] : plain[i];
                        NSEvent *event = [NSEvent keyEventWithType:NSEventTypeKeyDown location:NSZeroPoint modifierFlags:shift.boolValue ? NSEventModifierFlagShift : 0 timestamp:0 windowNumber:0 context:nil characters:characters charactersIgnoringModifiers:plain[i] isARepeat:NO keyCode:0];
                        assert([controller handleEvent:event client:client]);
                        BOOL paging = visible.boolValue && !shift.boolValue && ((option == 0 && i < 2) || (option == 1 && i >= 2));
                        if (paging) {
                            assert(session.lastCommand == (i % 2 == 0 ? MSIME_PREVIOUS_PAGE : MSIME_NEXT_PAGE));
                            assert(session.asciiCalls == 0);
                        } else {
                            assert(session.lastCommand == UINT32_MAX && session.asciiCalls == 1);
                            assert(session.lastASCII == [characters characterAtIndex:0] && session.lastShift == shift.boolValue);
                        }
                    }
                }
            }
            for (NSNumber *key in @[@116, @121]) {
                layoutPanel.requestedVisible = YES;
                NSEvent *event = [NSEvent keyEventWithType:NSEventTypeKeyDown location:NSZeroPoint modifierFlags:NSEventModifierFlagShift timestamp:0 windowNumber:0 context:nil characters:@"" charactersIgnoringModifiers:@"" isARepeat:NO keyCode:key.unsignedShortValue];
                assert([controller handleEvent:event client:client]);
                assert(session.lastCommand == (key.unsignedShortValue == 116 ? MSIME_PREVIOUS_PAGE : MSIME_NEXT_PAGE));
            }
        }
        appearance.pageShortcut = 0;
        for (NSNumber *modifier in @[@(NSEventModifierFlagCommand), @(NSEventModifierFlagControl), @(NSEventModifierFlagOption)]) {
            layoutPanel.requestedVisible = YES;
            NSEvent *event = [NSEvent keyEventWithType:NSEventTypeKeyDown location:NSZeroPoint modifierFlags:modifier.unsignedIntegerValue timestamp:0 windowNumber:0 context:nil characters:@"=" charactersIgnoringModifiers:@"=" isARepeat:NO keyCode:0];
            assert(![controller handleEvent:event client:client]);
            assert(session.lastCommand == MSIME_FINISH_COMPOSITION);
        }
        [defaults removePersistentDomainForName:suite];
    }
    return 0;
}
