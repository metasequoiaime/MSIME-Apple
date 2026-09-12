#import "../FloatingToolbarPanel.h"

#include <cassert>
#include <cmath>

@interface FloatingToolbarTestDelegate : NSObject <MSIMEFloatingToolbarDelegate>
@property(nonatomic) NSUInteger inputModeToggles;
@property(nonatomic) NSUInteger punctuationToggles;
@property(nonatomic) NSUInteger fullWidthToggles;
@property(nonatomic) NSUInteger traditionalToggles;
@property(nonatomic) NSUInteger characterPaletteRequests;
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
        assert(defaultFrame.size.width == 272.0 && defaultFrame.size.height == 44.0);
        assert(defaultFrame.origin.x == NSMaxX(visible) - 292.0 && defaultFrame.origin.y == NSMinY(visible) + 20.0);
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

        NSButton *inputMode = FindButton(panel.contentView, @"MetasequoiaFloatingToolbarInputMode");
        NSButton *punctuation = FindButton(panel.contentView, @"MetasequoiaFloatingToolbarPunctuation");
        NSButton *fullWidth = FindButton(panel.contentView, @"MetasequoiaFloatingToolbarFullWidth");
        NSButton *traditional = FindButton(panel.contentView, @"MetasequoiaFloatingToolbarTraditionalOutput");
        NSButton *settings = FindButton(panel.contentView, @"MetasequoiaFloatingToolbarSettings");
        assert(inputMode && punctuation && fullWidth && traditional && settings);
        for (NSNumber *scale in @[@75, @100, @125, @150]) {
            for (NSNumber *size in @[@16, @18, @20, @22, @24, @26, @28]) {
                NSDictionary *preferences = @{@"floating_toolbar": @{@"scale_percent": scale, @"font_size": size}};
                [panel applySizingPreferences:preferences];
                const double factor = scale.doubleValue / 100.0;
                assert(panel.frame.size.width == std::ceil((272.0 + 5.0 * (size.doubleValue - 24.0)) * factor));
                assert(panel.frame.size.height == std::ceil((size.doubleValue + 20.0) * factor));
                assert(std::abs(inputMode.frame.size.width - (size.doubleValue + 18.0) * factor) < 0.01);
                assert(std::abs(inputMode.frame.size.height - (size.doubleValue + 8.0) * factor) < 0.01);
                assert(std::abs(inputMode.font.pointSize - size.doubleValue * factor * 0.833) < 0.01);
                NSRect stable = panel.frame;
                [panel applySizingPreferences:preferences];
                assert(NSEqualRects(stable, panel.frame));
            }
        }
        [panel applySizingPreferences:@{@"floating_toolbar": @{@"scale_percent": @999, @"font_size": @(-1)}}];
        assert(panel.frame.size.width == 272.0 && panel.frame.size.height == 44.0);
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
    }
}
