#import "../FloatingToolbarPanel.h"
#import "../CandidateSkinAppearance.h"

#include <cassert>
#include <cmath>

@interface FloatingToolbarTestDelegate : NSObject <MSIMEFloatingToolbarDelegate>
@property(nonatomic) NSUInteger inputModeToggles;
@property(nonatomic) NSUInteger punctuationToggles;
@property(nonatomic) NSUInteger fullWidthToggles;
@property(nonatomic) NSUInteger traditionalToggles;
@property(nonatomic) NSUInteger characterPaletteRequests;
@property(nonatomic) NSUInteger emojiRequests;
@property(nonatomic) NSUInteger keyboardRequests;
@property(nonatomic) NSUInteger settingsRequests;
@property(nonatomic) NSUInteger updateRequests;
@property(nonatomic) NSUInteger websiteRequests;
@property(nonatomic) NSUInteger hideRequests;
@end

@implementation FloatingToolbarTestDelegate
- (void)floatingToolbarDidRequestToggleInputMode:(MSIMEFloatingToolbarPanel *)toolbar { (void)toolbar; ++_inputModeToggles; }
- (void)floatingToolbarDidRequestTogglePunctuation:(MSIMEFloatingToolbarPanel *)toolbar { (void)toolbar; ++_punctuationToggles; }
- (void)floatingToolbarDidRequestToggleFullWidth:(MSIMEFloatingToolbarPanel *)toolbar { (void)toolbar; ++_fullWidthToggles; }
- (void)floatingToolbarDidRequestToggleTraditionalOutput:(MSIMEFloatingToolbarPanel *)toolbar { (void)toolbar; ++_traditionalToggles; }
- (void)floatingToolbarDidRequestOpenCharacterPalette:(MSIMEFloatingToolbarPanel *)toolbar { (void)toolbar; ++_characterPaletteRequests; }
- (void)floatingToolbarDidRequestOpenEmoji:(MSIMEFloatingToolbarPanel *)toolbar { (void)toolbar; ++_emojiRequests; }
- (void)floatingToolbarDidRequestOpenScreenKeyboard:(MSIMEFloatingToolbarPanel *)toolbar { (void)toolbar; ++_keyboardRequests; }
- (void)floatingToolbarDidRequestOpenSettings:(MSIMEFloatingToolbarPanel *)toolbar { (void)toolbar; ++_settingsRequests; }
- (void)floatingToolbarDidRequestCheckForUpdates:(MSIMEFloatingToolbarPanel *)toolbar { (void)toolbar; ++_updateRequests; }
- (void)floatingToolbarDidRequestOpenWebsite:(MSIMEFloatingToolbarPanel *)toolbar { (void)toolbar; ++_websiteRequests; }
- (void)floatingToolbarDidRequestHide:(MSIMEFloatingToolbarPanel *)toolbar { (void)toolbar; ++_hideRequests; }
@end

static NSButton *FindButton(NSView *view, NSString *identifier) {
    if ([view isKindOfClass:NSButton.class] && [view.accessibilityIdentifier isEqualToString:identifier]) {
        return (NSButton *)view;
    }
    for (NSView *subview in view.subviews) {
        NSButton *button = FindButton(subview, identifier);
        if (button) return button;
    }
    return nil;
}

static void SendButton(NSButton *button) {
    assert(button != nil && button.target != nil && button.action != nullptr);
    [NSApp sendAction:button.action to:button.target from:button];
}

int main() {
    @autoreleasepool {
        [NSApplication sharedApplication];

        NSRect visible = NSMakeRect(-1200.0, -800.0, 1920.0, 1080.0);
        NSRect defaultFrame = MSIMEFloatingToolbarFrame(NSMakeRect(0.0, 0.0, 1.0, 1.0), visible, NO);
        assert(defaultFrame.size.width == 322.0 && defaultFrame.size.height == 44.0);
        assert(defaultFrame.origin.x == NSMaxX(visible) - 342.0 && defaultFrame.origin.y == NSMinY(visible) + 20.0);
        NSRect restored = MSIMEFloatingToolbarFrame(NSMakeRect(-4000.0, 4000.0, 1.0, 1.0), visible, YES);
        assert(restored.origin.x == NSMinX(visible) + 12.0 && restored.origin.y == NSMaxY(visible) - 56.0);

        MSIMEFloatingToolbarPanel *panel = [[MSIMEFloatingToolbarPanel alloc] init];
        assert(panel != nil && !panel.canBecomeKeyWindow && !panel.canBecomeMainWindow);
        [panel applyThemePreferences:@{}];
        assert([panel.appearance.name isEqualToString:NSAppearanceNameDarkAqua]);
        [panel applyThemePreferences:@{@"theme": @"light", @"toolbar_theme": @"follow"}];
        assert([panel.appearance.name isEqualToString:NSAppearanceNameAqua]);
        [panel applyThemePreferences:@{@"theme": @"light", @"toolbar_theme": @"dark"}];
        assert([panel.appearance.name isEqualToString:NSAppearanceNameDarkAqua]);
        [panel applyThemePreferences:@{@"theme": @"dark", @"toolbar_theme": @"light", @"candidate_theme": @"dark", @"settings_theme": @"dark"}];
        assert([panel.appearance.name isEqualToString:NSAppearanceNameAqua]);
        [panel applyThemePreferences:@{@"theme": @"system", @"toolbar_theme": @"light"}];
        assert([panel.appearance.name isEqualToString:NSAppearanceNameAqua]);
        [panel applyThemePreferences:@{@"theme": @"system", @"toolbar_theme": @"follow"}];
        assert(panel.appearance == nil);
        assert([panel.frameAutosaveName isEqualToString:@"MetasequoiaFloatingToolbarFrame"]);
        [panel setFrameAutosaveName:@""]; // Geometry tests must not persist window placement.
        msime::mac::SkinTokens light{}, dark{};
        light.surface = {0.8, 0.7, 0.6, 1};
        light.border = {0.4, 0.3, 0.2, 1};
        light.text = {0.1, 0.2, 0.3, 1};
        dark.surface = {0.1, 0.2, 0.3, 1};
        dark.border = {0.3, 0.4, 0.5, 1};
        dark.text = {0.9, 0.8, 0.7, 1};
        [panel applyLightSkin:light darkSkin:dark];
        for (NSString *mode in @[@"light", @"dark"]) {
            const auto expected = [mode isEqual:@"dark"] ? dark : light;
            [panel applyThemePreferences:@{@"toolbar_theme": mode}];
            // Legacy notifications and size updates must not replace host-supplied colors.
            [NSNotificationCenter.defaultCenter postNotificationName:MetasequoiaCandidateSkinDidChangeNotification object:nil];
            [panel applySizingPreferences:@{}];
            id chrome = [panel valueForKey:@"chrome"];
            assert([[chrome valueForKey:@"fillColor"] isEqual:MetasequoiaColorFromRgba(expected.surface)]);
            assert([[chrome valueForKey:@"strokeColor"] isEqual:MetasequoiaColorFromRgba(expected.border)]);
            NSButton *button = FindButton(panel.contentView, @"MetasequoiaFloatingToolbarInputMode");
            assert([button.contentTintColor isEqual:MetasequoiaColorFromRgba(expected.text)]);
        }
        dark.surface = {0.3, 0.1, 0.2, 1};
        [panel applyLightSkin:light darkSkin:dark];
        assert([[[panel valueForKey:@"chrome"] valueForKey:@"fillColor"] isEqual:MetasequoiaColorFromRgba(dark.surface)]);

        NSButton *inputMode = FindButton(panel.contentView, @"MetasequoiaFloatingToolbarInputMode");
        NSButton *punctuation = FindButton(panel.contentView, @"MetasequoiaFloatingToolbarPunctuation");
        NSButton *fullWidth = FindButton(panel.contentView, @"MetasequoiaFloatingToolbarFullWidth");
        NSButton *traditional = FindButton(panel.contentView, @"MetasequoiaFloatingToolbarTraditionalOutput");
        NSButton *settings = FindButton(panel.contentView, @"MetasequoiaFloatingToolbarSettings");
        NSButton *emoji = FindButton(panel.contentView, @"MetasequoiaFloatingToolbarEmoji");
        NSButton *keyboard = FindButton(panel.contentView, @"MetasequoiaFloatingToolbarScreenKeyboard");
        assert(keyboard && keyboard.image && keyboard.hidden);
        assert([keyboard.accessibilityLabel isEqualToString:@"打开水杉屏幕键盘"]);
        assert([keyboard.toolTip isEqualToString:keyboard.accessibilityLabel]);
        assert(emoji && emoji.image && !emoji.hidden);
        assert([emoji.accessibilityLabel isEqualToString:@"打开水杉表情面板"]);
        assert([emoji.toolTip isEqualToString:emoji.accessibilityLabel]);
        assert(inputMode && punctuation && fullWidth && traditional && settings);
        for (NSNumber *scale in @[@75, @100, @125, @150]) {
            for (NSNumber *size in @[@16, @18, @20, @22, @24, @26, @28]) {
                NSDictionary *preferences = @{@"floating_toolbar": @{@"scale_percent": scale, @"font_size": size}};
                [panel applySizingPreferences:preferences];
                const double factor = scale.doubleValue / 100.0;
                assert(panel.frame.size.width == std::ceil((322.0 + 6.0 * (size.doubleValue - 24.0)) * factor));
                assert(panel.frame.size.height == std::ceil((size.doubleValue + 20.0) * factor));
                assert(std::abs(inputMode.frame.size.width - (size.doubleValue + 18.0) * factor) < 0.01);
                assert(std::abs(inputMode.frame.size.height - (size.doubleValue + 8.0) * factor) < 0.01);
                assert(std::abs(inputMode.font.pointSize - size.doubleValue * factor * 0.833) < 0.01);
                // AppKit aligns the later stack items to backing pixels at fractional positions.
                assert(std::abs(emoji.frame.size.width - (size.doubleValue + 18.0) * factor) <= 1.0 / panel.backingScaleFactor);
                for (NSLayoutConstraint *constraint in emoji.constraints) {
                    if ([constraint.identifier isEqualToString:@"ToolbarButtonWidth"])
                        assert(constraint.constant == (size.doubleValue + 18.0) * factor);
                }
                assert([emoji.contentTintColor isEqual:settings.contentTintColor]);
                assert(emoji.symbolConfiguration != nil);
                NSImage *expectedEmoji = [emoji.image imageWithSymbolConfiguration:
                    [NSImageSymbolConfiguration configurationWithPointSize:size.doubleValue * factor weight:NSFontWeightRegular]];
                NSImage *configuredEmoji = [emoji.image imageWithSymbolConfiguration:emoji.symbolConfiguration];
                assert(NSEqualSizes(expectedEmoji.size, configuredEmoji.size));
                NSRect stable = panel.frame;
                [panel applySizingPreferences:preferences];
                assert(NSEqualRects(stable, panel.frame));
                [panel applySizingPreferences:@{@"floating_toolbar": @{@"scale_percent": scale, @"font_size": size, @"screen_keyboard": @YES}}];
                assert(!keyboard.hidden && keyboard.superview != nil);
                assert(panel.frame.size.width == std::ceil((372.0 + 7.0 * (size.doubleValue - 24.0)) * factor));
                assert([keyboard.contentTintColor isEqual:settings.contentTintColor]);
                NSImage *expectedKeyboard = [keyboard.image imageWithSymbolConfiguration:
                    [NSImageSymbolConfiguration configurationWithPointSize:size.doubleValue * factor weight:NSFontWeightRegular]];
                NSImage *configuredKeyboard = [keyboard.image imageWithSymbolConfiguration:keyboard.symbolConfiguration];
                assert(NSEqualSizes(expectedKeyboard.size, configuredKeyboard.size));
            }
        }
        [panel applySizingPreferences:@{@"floating_toolbar": @{@"scale_percent": @999, @"font_size": @(-1)}}];
        assert(panel.frame.size.width == 322.0 && panel.frame.size.height == 44.0);
        [panel applySizingPreferences:@{@"floating_toolbar": @{@"scale_percent": @150, @"font_size": @28}}];
        FloatingToolbarTestDelegate *sizingDelegate = [FloatingToolbarTestDelegate new];
        const NSSize configuredSize = panel.frame.size;
        [panel activateForDelegate:sizingDelegate visible:YES];
        assert(NSEqualSizes(panel.frame.size, configuredSize));
        [panel setVisible:NO forDelegate:sizingDelegate];
        [panel setVisible:YES forDelegate:sizingDelegate];
        assert(NSEqualSizes(panel.frame.size, configuredSize));
        [panel deactivateForDelegate:sizingDelegate];
        [panel applySizingPreferences:@{}];
        NSArray<NSButton *> *optionalButtons = @[punctuation, fullWidth, traditional, emoji, keyboard, settings];
        NSArray<NSString *> *keys = @[@"punctuation", @"fullwidth", @"character_set", @"emoji", @"screen_keyboard", @"settings"];
        for (NSUInteger mask = 0; mask < 64; ++mask) {
            NSMutableDictionary *components = [@{@"scale_percent": @150, @"font_size": @28, @"english_mode": @NO} mutableCopy];
            NSUInteger count = 1;
            for (NSUInteger index = 0; index < keys.count; ++index) {
                const BOOL enabled = (mask & (1u << index)) != 0;
                components[keys[index]] = @(enabled);
                if (enabled) ++count;
            }
            [panel applySizingPreferences:@{@"floating_toolbar": components}];
            for (NSUInteger index = 0; index < keys.count; ++index)
                assert(optionalButtons[index].hidden == ((mask & (1u << index)) == 0));
            assert(!inputMode.hidden);
            assert(panel.frame.size.width == std::ceil((count * 46.0 + (count - 1) * 8.0 + 30.0) * 1.5));
            assert(inputMode.superview != nil);
            CGFloat previousRight = 0;
            for (NSButton *button in @[inputMode, punctuation, fullWidth, traditional, emoji, keyboard, settings]) {
                if (button.hidden) continue;
                const NSRect rect = [button convertRect:button.bounds toView:panel.contentView];
                assert(NSMinX(rect) >= previousRight);
                assert(NSMaxX(rect) <= panel.contentView.bounds.size.width);
                previousRight = NSMaxX(rect);
            }
        }
        [panel applySizingPreferences:@{}];
        for (NSButton *button in optionalButtons) {
            assert(button.hidden == (button == keyboard));
            if (!button.hidden) assert(button.superview != nil);
        }
        assert(panel.frame.size.width == 322.0);
        [panel applySizingPreferences:@{@"floating_toolbar": @{@"screen_keyboard": @"invalid"}}];
        assert(keyboard.hidden && panel.frame.size.width == 322.0);
        [panel applySizingPreferences:@{@"floating_toolbar": @{@"screen_keyboard": @YES}}];
        assert(!keyboard.hidden && panel.frame.size.width == 372.0);

        [panel updateEnglishInputMode:YES chinesePunctuationEnabled:NO fullWidthEnabled:YES traditionalChineseOutputEnabled:YES];
        assert([inputMode.title isEqualToString:@"英"] && [punctuation.title isEqualToString:@"."] &&
               [fullWidth.title isEqualToString:@"全"] && [traditional.title isEqualToString:@"繁"]);
        assert([inputMode.toolTip isEqualToString:inputMode.accessibilityLabel]);
        assert([punctuation.toolTip isEqualToString:punctuation.accessibilityLabel]);
        assert([fullWidth.toolTip isEqualToString:fullWidth.accessibilityLabel]);
        assert([traditional.toolTip isEqualToString:traditional.accessibilityLabel]);

        FloatingToolbarTestDelegate *delegate = [FloatingToolbarTestDelegate new];
        panel.toolbarDelegate = delegate;
        SendButton(inputMode);
        SendButton(punctuation);
        SendButton(fullWidth);
        SendButton(traditional);
        SendButton(emoji);
        assert(delegate.emojiRequests == 1 && delegate.characterPaletteRequests == 0);
        SendButton(keyboard);
        assert(delegate.keyboardRequests == 1 && delegate.emojiRequests == 1);
        for (NSString *selectorName in @[@"openCharacterPalette:", @"openSettings:", @"checkForUpdates:",
                                         @"openWebsite:", @"dismissFloatingToolbar:"]) {
            [NSApp sendAction:NSSelectorFromString(selectorName) to:panel from:nil];
        }
        assert(delegate.inputModeToggles == 1 && delegate.punctuationToggles == 1 &&
               delegate.fullWidthToggles == 1 && delegate.traditionalToggles == 1 &&
               delegate.characterPaletteRequests == 1 && delegate.settingsRequests == 1 &&
               delegate.updateRequests == 1 && delegate.websiteRequests == 1 && delegate.hideRequests == 1);

        NSMenu *menu = CreateMSIMEFloatingToolbarUtilityMenu(panel);
        [menu update];
        assert(menu.numberOfItems == 7);
        assert([menu itemAtIndex:0].action == @selector(openCharacterPalette:) &&
               [menu itemAtIndex:1].action == @selector(openSettings:) &&
               [menu itemAtIndex:2].action == @selector(checkForUpdates:) &&
               [menu itemAtIndex:4].action == @selector(openWebsite:) &&
               [menu itemAtIndex:6].action == @selector(dismissFloatingToolbar:));
        for (NSMenuItem *item in menu.itemArray) {
            if (!item.isSeparatorItem) assert(item.enabled && item.target == panel);
        }

        [panel setVisible:NO forDelegate:delegate];
        assert(!panel.visible && panel.toolbarDelegate == delegate);
        [panel setVisible:YES forDelegate:[FloatingToolbarTestDelegate new]];
        assert(!panel.visible);
        [panel deactivateForDelegate:[FloatingToolbarTestDelegate new]];
        assert(panel.toolbarDelegate == delegate);
        [panel deactivateForDelegate:delegate];
        assert(!panel.visible && panel.toolbarDelegate == nil);
        SendButton(keyboard);
        assert(delegate.keyboardRequests == 1);
        SendButton(emoji);
        assert(delegate.emojiRequests == 1);
        FloatingToolbarTestDelegate *newDelegate = [FloatingToolbarTestDelegate new];
        [panel activateForDelegate:newDelegate visible:NO];
        SendButton(keyboard);
        assert(newDelegate.keyboardRequests == 1 && delegate.keyboardRequests == 1);
        SendButton(emoji);
        assert(newDelegate.emojiRequests == 1 && delegate.emojiRequests == 1);
        [panel deactivateForDelegate:newDelegate];
    }
}
