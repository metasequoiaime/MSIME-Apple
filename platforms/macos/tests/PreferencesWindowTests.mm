#import "../src/PreferencesWindowController.h"
#import "../src/UpdateController.h"
#import "../src/CandidateAppearancePreferences.h"
#import "../src/InputBehaviorPreferences.h"

#import <AppKit/AppKit.h>

#include <algorithm>
#include <cmath>
#include <stdexcept>

@interface MetasequoiaPreferencesWindowController (Testing)
- (instancetype)initWithUpdateController:(MetasequoiaUpdateController *)updateController;
- (void)refreshControls;
- (void)refreshUpdateControls;
- (void)selectPreferencesPage:(NSButton *)sender;
- (void)openWebsite:(id)sender;
- (void)openFeedback:(id)sender;
@end

@interface PreferencesFakeUpdateDriver : NSObject <MetasequoiaUpdateDriver>
@property(nonatomic) BOOL canCheckForUpdates;
@property(nonatomic) BOOL automaticallyChecksForUpdates;
@end

@implementation PreferencesFakeUpdateDriver
- (void)checkForUpdates:(id)sender
{
    (void)sender;
}
@end

namespace
{
void require(bool condition, const char *message)
{
    if (!condition)
    {
        throw std::runtime_error(message);
    }
}

double RelativeLuminance(NSColor *color)
{
    NSColor *srgb = [color colorUsingColorSpace:[NSColorSpace sRGBColorSpace]];
    CGFloat red = 0.0;
    CGFloat green = 0.0;
    CGFloat blue = 0.0;
    CGFloat alpha = 0.0;
    require(srgb != nil, "A candidate preview color could not be converted to sRGB.");
    [srgb getRed:&red green:&green blue:&blue alpha:&alpha];
    auto linearChannel = [](CGFloat component) {
        return component <= 0.03928 ? component / 12.92 : std::pow((component + 0.055) / 1.055, 2.4);
    };
    return (0.2126 * linearChannel(red)) + (0.7152 * linearChannel(green)) + (0.0722 * linearChannel(blue));
}

double ContrastRatio(NSColor *first, NSColor *second)
{
    const double firstLuminance = RelativeLuminance(first);
    const double secondLuminance = RelativeLuminance(second);
    const double lighter = std::max(firstLuminance, secondLuminance);
    const double darker = std::min(firstLuminance, secondLuminance);
    return (lighter + 0.05) / (darker + 0.05);
}

bool WaitUntil(BOOL (^condition)(void))
{
    NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:1.0];
    while (!condition())
    {
        if ([deadline timeIntervalSinceNow] <= 0.0)
        {
            return false;
        }
        [[NSRunLoop currentRunLoop] runMode:NSDefaultRunLoopMode beforeDate:[NSDate dateWithTimeIntervalSinceNow:0.01]];
    }
    return true;
}

NSView *FindViewWithAccessibilityLabel(NSView *view, NSString *label)
{
    if ([view.accessibilityLabel isEqualToString:label])
    {
        return view;
    }
    for (NSView *subview in view.subviews)
    {
        NSView *match = FindViewWithAccessibilityLabel(subview, label);
        if (match != nil)
        {
            return match;
        }
    }
    return nil;
}

NSButton *FindButtonWithTitle(NSView *view, NSString *title)
{
    if ([view isKindOfClass:[NSButton class]] && [((NSButton *)view).title isEqualToString:title])
    {
        return (NSButton *)view;
    }
    for (NSView *subview in view.subviews)
    {
        NSButton *match = FindButtonWithTitle(subview, title);
        if (match != nil)
        {
            return match;
        }
    }
    return nil;
}

NSInteger CountButtonsWithAction(NSView *view, SEL action)
{
    NSInteger count = 0;
    if ([view isKindOfClass:[NSButton class]] && ((NSButton *)view).action == action)
    {
        ++count;
    }
    for (NSView *subview in view.subviews)
    {
        count += CountButtonsWithAction(subview, action);
    }
    return count;
}
} // namespace

int main()
{
    @autoreleasepool
    {
        [NSApplication sharedApplication];
        const char *showSettingsArguments[] = {"MetasequoiaIME", "--show-settings"};
        const char *extraSettingsArguments[] = {"MetasequoiaIME", "--show-settings", "unexpected"};
        const char *serverArguments[] = {"MetasequoiaIME"};
        require(MetasequoiaShouldShowPreferences(2, showSettingsArguments),
                "The standalone settings argument was not recognized.");
        require(!MetasequoiaShouldShowPreferences(3, extraSettingsArguments),
                "Standalone settings accepted unexpected arguments.");
        require(!MetasequoiaShouldShowPreferences(1, serverArguments),
                "A normal input-method launch was treated as standalone settings.");
        [[NSUserDefaults standardUserDefaults] removeObjectForKey:@"MetasequoiaImeFloatingToolbarEnabled"];
        [NSUserDefaults.standardUserDefaults removeObjectForKey:MetasequoiaInputBehaviorKey];
        MetasequoiaSetInputBehavior(@"pageBrackets", 1);
        MetasequoiaSetInputBehavior(@"pageComma", 1);
        MetasequoiaSetInputBehavior(@"edgeSelection", 1);
        require(MetasequoiaCandidateKeyOptions(0).edgeSelection && !MetasequoiaCandidateKeyOptions(0).brackets &&
                    MetasequoiaCandidateKeyOptions(0).commaPeriod,
                "Enabling edge selection must disable only bracket paging.");
        MetasequoiaSetInputBehavior(@"pageBrackets", 1);
        require(!MetasequoiaCandidateKeyOptions(0).edgeSelection && MetasequoiaCandidateKeyOptions(0).brackets,
                "Enabling bracket paging must disable edge selection.");
        MetasequoiaSetInputBehavior(@"englishMinimumPrefix", 99);
        require(MetasequoiaInputInteger(@"englishMinimumPrefix", 2, 1, 10) == 2,
                "Invalid English prefix must use the safe default.");
        MetasequoiaSetInputBehavior(@"defaultEnglish", 1);
        MetasequoiaSetInputBehavior(@"perApplicationMode", 1);
        require(MetasequoiaRememberedEnglishMode(@"test.app.one"), "New apps must use the default input mode.");
        MetasequoiaRememberEnglishMode(@"test.app.one", NO);
        require(!MetasequoiaRememberedEnglishMode(@"test.app.one") && MetasequoiaRememberedEnglishMode(@"test.app.two"),
                "Per-app language memory leaked into another application.");
        [NSUserDefaults.standardUserDefaults removeObjectForKey:MetasequoiaInputBehaviorKey];
        require([MetasequoiaPreferencesWindowController storedFloatingToolbarEnabled],
                "The floating toolbar was not enabled by default.");
        [[NSUserDefaults standardUserDefaults] removeObjectForKey:@"MetasequoiaImeTraditionalChineseOutput"];
        require(![MetasequoiaPreferencesWindowController storedTraditionalChineseOutputEnabled],
                "Traditional Chinese output was unexpectedly enabled by default.");
        [MetasequoiaPreferencesWindowController setTraditionalChineseOutputEnabled:YES];
        require([MetasequoiaPreferencesWindowController storedTraditionalChineseOutputEnabled],
                "The traditional Chinese output preference was not stored.");
        __block NSUInteger traditionalOutputNotificationCount = 0;
        id traditionalOutputObserver = [[NSNotificationCenter defaultCenter]
            addObserverForName:MetasequoiaTraditionalChineseOutputDidChangeNotification
                        object:nil
                         queue:nil
                    usingBlock:^(NSNotification *notification) {
                      (void)notification;
                      ++traditionalOutputNotificationCount;
                    }];
        [MetasequoiaPreferencesWindowController setTraditionalChineseOutputEnabled:YES];
        require(traditionalOutputNotificationCount == 0,
                "Selecting the active output script emitted a destructive no-op refresh.");
        [MetasequoiaPreferencesWindowController setTraditionalChineseOutputEnabled:NO];
        require(traditionalOutputNotificationCount == 1,
                "Changing the output script did not emit exactly one refresh notification.");
        [[NSNotificationCenter defaultCenter] removeObserver:traditionalOutputObserver];
        [MetasequoiaPreferencesWindowController setFloatingToolbarEnabled:NO];
        [MetasequoiaPreferencesWindowController setCandidatePanelStyle:1];
        [MetasequoiaPreferencesWindowController setCandidatePageSize:5];
        [MetasequoiaPreferencesWindowController setCandidateFontSize:16];
        [MetasequoiaPreferencesWindowController setCandidatePageShortcut:1];
        [MetasequoiaPreferencesWindowController setCandidateLearningEnabled:NO];
        [MetasequoiaPreferencesWindowController setFrequencyAdjustmentMode:@"pin"];
        [MetasequoiaPreferencesWindowController setFrequencyTriggerCount:3];
        [MetasequoiaPreferencesWindowController setFrequencyLinearStep:2];
        [MetasequoiaPreferencesWindowController setEnglishInputMode:YES];
        [MetasequoiaPreferencesWindowController setInputModeShortcutEnabled:NO];
        [MetasequoiaPreferencesWindowController setFullWidthInputEnabled:NO];
        [MetasequoiaPreferencesWindowController setWubiAutoCommitUniqueEnabled:NO];
        [MetasequoiaPreferencesWindowController setWubiMixedPinyinEnabled:NO];
        [[NSUserDefaults standardUserDefaults] setBool:YES forKey:@"MetasequoiaImeShuangpinKeymapEnabled"];
        [MetasequoiaPreferencesWindowController setHelpcodeEnabled:YES];
        [[NSUserDefaults standardUserDefaults] setInteger:1 forKey:@"MetasequoiaImeQuanpinHelpcodeSchema"];
        [[NSUserDefaults standardUserDefaults] setInteger:3 forKey:@"MetasequoiaImeShuangpinHelpcodeSchema"];
        [MetasequoiaPreferencesWindowController setStoredScheme:2];
        require([MetasequoiaPreferencesWindowController storedScheme] == 2,
                "The Wubi input scheme preference was not stored.");
        [MetasequoiaPreferencesWindowController setStoredScheme:99];
        require([MetasequoiaPreferencesWindowController storedScheme] == 0,
                "An unsupported input scheme preference was not normalized safely.");
        [MetasequoiaPreferencesWindowController setShuangpinSchema:@"microsoft"];
        require([[MetasequoiaPreferencesWindowController storedShuangpinSchema] isEqualToString:@"microsoft"],
                "The Microsoft Shuangpin schema preference was not stored.");
        [MetasequoiaPreferencesWindowController setShuangpinSchema:@"bogus"];
        require([[MetasequoiaPreferencesWindowController storedShuangpinSchema] isEqualToString:@"xiaohe"],
                "An unsupported Shuangpin schema preference was not normalized safely.");
        [MetasequoiaPreferencesWindowController setStoredScheme:2];
        require([MetasequoiaPreferencesWindowController storedCandidatePanelStyle] == 1,
                "The vertical candidate layout preference was not stored.");
        require([MetasequoiaPreferencesWindowController storedCandidatePageSize] == 5,
                "The five-candidate page-size preference was not stored.");
        require([MetasequoiaPreferencesWindowController storedCandidateFontSize] == 16,
                "The small candidate font-size preference was not stored.");
        require([MetasequoiaPreferencesWindowController storedCandidatePageShortcut] == 1,
                "The bracket candidate page shortcut preference was not stored.");
        require(![MetasequoiaPreferencesWindowController storedCandidateLearningEnabled],
                "The disabled candidate-learning preference was not stored.");
        require([[MetasequoiaPreferencesWindowController storedFrequencyAdjustmentMode] isEqualToString:@"pin"],
                "The pin frequency-adjustment preference was not stored.");
        require([MetasequoiaPreferencesWindowController storedFrequencyTriggerCount] == 3,
                "The frequency trigger-count preference was not stored.");
        require([MetasequoiaPreferencesWindowController storedFrequencyLinearStep] == 2,
                "The frequency linear-step preference was not stored.");
        [MetasequoiaPreferencesWindowController setFrequencyAdjustmentMode:@"nope"];
        require([[MetasequoiaPreferencesWindowController storedFrequencyAdjustmentMode] isEqualToString:@"promote"],
                "An unsupported frequency mode was not normalized to promote.");
        [MetasequoiaPreferencesWindowController setFrequencyTriggerCount:99];
        require([MetasequoiaPreferencesWindowController storedFrequencyTriggerCount] == 1,
                "An unsupported frequency trigger count was not normalized safely.");
        [MetasequoiaPreferencesWindowController setFrequencyLinearStep:0];
        require([MetasequoiaPreferencesWindowController storedFrequencyLinearStep] == 1,
                "An unsupported frequency linear step was not normalized safely.");
        [MetasequoiaPreferencesWindowController setFrequencyAdjustmentMode:@"pin"];
        [MetasequoiaPreferencesWindowController setFrequencyTriggerCount:3];
        [MetasequoiaPreferencesWindowController setFrequencyLinearStep:2];
        require([MetasequoiaPreferencesWindowController storedEnglishInputMode],
                "The English input-mode state was not stored.");
        require(![MetasequoiaPreferencesWindowController storedInputModeShortcutEnabled],
                "The disabled input-mode shortcut preference was not stored.");
        require(![MetasequoiaPreferencesWindowController storedFullWidthInputEnabled],
                "The disabled full-width input preference was not stored.");
        require(![MetasequoiaPreferencesWindowController storedWubiMixedPinyinEnabled],
                "Mixed wubi input was on before anyone asked for it.");
        require(![MetasequoiaPreferencesWindowController storedWubiAutoCommitUniqueEnabled],
                "The disabled Wubi auto-commit preference was not stored.");
        require([MetasequoiaPreferencesWindowController storedInputModeHUDEnabled],
                "The input-mode badge was off without anyone turning it off.");
        [MetasequoiaPreferencesWindowController setInputModeHUDEnabled:NO];
        require(![MetasequoiaPreferencesWindowController storedInputModeHUDEnabled],
                "The disabled input-mode badge preference was not stored.");
        [MetasequoiaPreferencesWindowController setInputModeHUDEnabled:YES];
        require([MetasequoiaPreferencesWindowController storedWubiCodeHintEnabled],
                "The Wubi code hint was off without anyone turning it off.");
        [MetasequoiaPreferencesWindowController setWubiCodeHintEnabled:NO];
        require(![MetasequoiaPreferencesWindowController storedWubiCodeHintEnabled],
                "The disabled Wubi code-hint preference was not stored.");
        [MetasequoiaPreferencesWindowController setWubiCodeHintEnabled:YES];

        PreferencesFakeUpdateDriver *updateDriver = [[PreferencesFakeUpdateDriver alloc] init];
        updateDriver.canCheckForUpdates = YES;
        updateDriver.automaticallyChecksForUpdates = YES;
        MetasequoiaUpdateController *updateController = [[MetasequoiaUpdateController alloc] initWithDriver:updateDriver
                                                                                          activationHandler:^{
                                                                                          }];
        MetasequoiaPreferencesWindowController *controller =
            [[MetasequoiaPreferencesWindowController alloc] initWithUpdateController:updateController];
        [controller refreshControls];
        require(controller.window.titleVisibility == NSWindowTitleVisible &&
                    !controller.window.titlebarAppearsTransparent && !controller.window.movableByWindowBackground,
                "The settings window did not use standard macOS window chrome.");
        NSView *navigation = FindViewWithAccessibilityLabel(controller.window.contentView, @"水杉输入法导航");
        require(navigation != nil && controller.window.toolbar == nil,
                "The settings window did not expose sidebar navigation.");
        NSButton *generalNavigationItem = FindButtonWithTitle(navigation, @"输入");
        NSButton *appearanceNavigationItem = FindButtonWithTitle(navigation, @"外观");
        NSButton *skinNavigationItem = FindButtonWithTitle(navigation, @"皮肤");
        NSButton *dataNavigationItem = FindButtonWithTitle(navigation, @"词库");
        NSButton *updatesNavigationItem = FindButtonWithTitle(navigation, @"关于与更新");
        require(generalNavigationItem != nil && appearanceNavigationItem != nil && skinNavigationItem != nil &&
                    dataNavigationItem != nil && updatesNavigationItem != nil,
                "The settings window did not expose all sidebar destinations.");
        require(appearanceNavigationItem.state == NSControlStateValueOn,
                "The settings sidebar did not select appearance initially.");
        NSView *generalPage = FindViewWithAccessibilityLabel(controller.window.contentView, @"键盘输入设置页");
        NSView *appearancePage = FindViewWithAccessibilityLabel(controller.window.contentView, @"外观设置页");
        NSView *skinPage = FindViewWithAccessibilityLabel(controller.window.contentView, @"皮肤设置页");
        NSView *dataPage = FindViewWithAccessibilityLabel(controller.window.contentView, @"词库与数据设置页");
        NSView *updatesPage = FindViewWithAccessibilityLabel(controller.window.contentView, @"更新与反馈设置页");
        require(generalPage != nil && appearancePage != nil && skinPage != nil && dataPage != nil && updatesPage != nil,
                "The settings window did not create all functional pages.");
        require(generalPage.hidden && !appearancePage.hidden && skinPage.hidden && dataPage.hidden &&
                    updatesPage.hidden,
                "The settings window did not open on the appearance page.");
        require([NSApp sendAction:appearanceNavigationItem.action
                               to:appearanceNavigationItem.target
                             from:appearanceNavigationItem] &&
                    generalPage.hidden && !appearancePage.hidden && skinPage.hidden && dataPage.hidden &&
                    (appearanceNavigationItem.state == NSControlStateValueOn),
                "The appearance sidebar item did not reveal and select the appearance page.");
        require([NSApp sendAction:skinNavigationItem.action to:skinNavigationItem.target from:skinNavigationItem] &&
                    generalPage.hidden && appearancePage.hidden && !skinPage.hidden && dataPage.hidden &&
                    (skinNavigationItem.state == NSControlStateValueOn),
                "The skin sidebar item did not reveal and select the skin page.");
        require([NSApp sendAction:dataNavigationItem.action to:dataNavigationItem.target from:dataNavigationItem] &&
                    generalPage.hidden && appearancePage.hidden && skinPage.hidden && !dataPage.hidden &&
                    (dataNavigationItem.state == NSControlStateValueOn),
                "The data sidebar item did not reveal and select the data page.");
        require([NSApp sendAction:updatesNavigationItem.action
                               to:updatesNavigationItem.target
                             from:updatesNavigationItem] &&
                    generalPage.hidden && appearancePage.hidden && skinPage.hidden && dataPage.hidden &&
                    !updatesPage.hidden && (updatesNavigationItem.state == NSControlStateValueOn),
                "The updates sidebar item did not reveal and select the updates page.");
        require([NSApp sendAction:generalNavigationItem.action
                               to:generalNavigationItem.target
                             from:generalNavigationItem] &&
                    !generalPage.hidden && appearancePage.hidden && skinPage.hidden && dataPage.hidden &&
                    updatesPage.hidden && (generalNavigationItem.state == NSControlStateValueOn),
                "The keyboard-input sidebar item did not reveal and select the keyboard page.");

        for (NSString *title in @[ @"辅助码", @"快捷键", @"悬浮工具栏" ])
        {
            NSButton *destination = FindButtonWithTitle(navigation, title);
            NSView *page = FindViewWithAccessibilityLabel(controller.window.contentView,
                                                          [title stringByAppendingString:@"设置页"]);
            require(destination != nil && page != nil, "A separated settings destination was missing.");
            [destination performClick:nil];
            require(!page.hidden && generalPage.hidden && destination.state == NSControlStateValueOn,
                    "Sidebar navigation did not reveal its dedicated page.");
            // Clicking the selected destination again must not deselect it.
            [destination performClick:nil];
            require(destination.state == NSControlStateValueOn, "The current navigation item could be deselected.");
        }
        [appearanceNavigationItem performClick:nil];
        NSSize originalContentSize = controller.window.contentView.frame.size;
        [controller.window setContentSize:controller.window.contentMinSize];
        [controller.window.contentView layoutSubtreeIfNeeded];
        NSScrollView *appearanceScroll = (NSScrollView *)appearancePage;
        require([appearancePage isKindOfClass:[NSScrollView class]] && appearanceScroll.hasVerticalScroller &&
                    NSHeight(appearanceScroll.documentView.frame) > NSHeight(appearanceScroll.contentView.bounds),
                "The compact window did not make overflowing appearance settings scrollable.");
        [appearanceScroll.contentView scrollToPoint:NSMakePoint(0.0, 10000.0)];
        [appearanceScroll reflectScrolledClipView:appearanceScroll.contentView];
        require(NSMinY(appearanceScroll.contentView.bounds) > 0.0, "The appearance document could not scroll.");
        [appearanceScroll.contentView scrollToPoint:NSZeroPoint];
        [controller.window setContentSize:originalContentSize];
        [generalNavigationItem performClick:nil];

        NSView *candidatePageShortcutView =
            FindViewWithAccessibilityLabel(controller.window.contentView, @"候选翻页快捷键");
        require([candidatePageShortcutView isKindOfClass:[NSPopUpButton class]] &&
                    ((NSPopUpButton *)candidatePageShortcutView).indexOfSelectedItem == 1,
                "The keyboard-input page did not reflect the stored candidate page shortcut.");
        NSPopUpButton *candidatePageShortcutButton = (NSPopUpButton *)candidatePageShortcutView;
        require(candidatePageShortcutButton.numberOfItems == 3 &&
                    [[candidatePageShortcutButton itemTitleAtIndex:0] isEqualToString:@"- / ="] &&
                    [[candidatePageShortcutButton itemTitleAtIndex:1] isEqualToString:@"[ / ]"] &&
                    [[candidatePageShortcutButton itemTitleAtIndex:2] isEqualToString:@"Page Up / Page Down"],
                "The candidate page shortcut control did not contain all supported key pairs.");
        [candidatePageShortcutButton selectItemAtIndex:2];
        require([NSApp sendAction:candidatePageShortcutButton.action
                               to:candidatePageShortcutButton.target
                             from:candidatePageShortcutButton] &&
                    [MetasequoiaPreferencesWindowController storedCandidatePageShortcut] == 2,
                "The candidate page shortcut choice did not persist.");

        // Off by default: turning it on hands Shift+U/T/K/J to the engine's local input modes, and
        // those keystrokes insert a bare capital today, so it must never arrive switched on.
        NSButton *localInputModesButton =
            FindButtonWithTitle(controller.window.contentView, @"启用本地输入模式（Shift+U/T/K/J）");
        require(localInputModesButton != nil, "The settings window did not expose the local input mode switch.");
        require(localInputModesButton.state == NSControlStateValueOff,
                "The local input mode switch did not default to off.");
        // A real click flips the state before the action runs, so the test has to do the same.
        localInputModesButton.state = NSControlStateValueOn;
        require([NSApp sendAction:localInputModesButton.action
                               to:localInputModesButton.target
                             from:localInputModesButton] &&
                    [MetasequoiaPreferencesWindowController storedLocalInputModesEnabled],
                "The local input mode switch did not persist.");
        localInputModesButton.state = NSControlStateValueOff;
        require([NSApp sendAction:localInputModesButton.action
                               to:localInputModesButton.target
                             from:localInputModesButton] &&
                    ![MetasequoiaPreferencesWindowController storedLocalInputModesEnabled],
                "The local input mode switch did not turn back off.");

        NSButton *quanpinSchemeButton = FindButtonWithTitle(controller.window.contentView, @"全拼输入");
        NSButton *shuangpinSchemeButton = FindButtonWithTitle(controller.window.contentView, @"双拼输入");
        NSButton *wubiSchemeButton = FindButtonWithTitle(controller.window.contentView, @"五笔输入");
        NSButton *fullWidthButton = FindButtonWithTitle(controller.window.contentView, @"Option+Shift+H 切换全半角");
        require(quanpinSchemeButton != nil && shuangpinSchemeButton != nil && wubiSchemeButton != nil,
                "The keyboard-input page did not expose every supported input scheme.");
        NSView *shuangpinSchemeView = FindViewWithAccessibilityLabel(controller.window.contentView, @"双拼方案");
        NSView *wubiSchemeView = FindViewWithAccessibilityLabel(controller.window.contentView, @"五笔方案");
        require([shuangpinSchemeView isKindOfClass:[NSPopUpButton class]] &&
                    ((NSPopUpButton *)shuangpinSchemeView).numberOfItems == 4 &&
                    [[((NSPopUpButton *)shuangpinSchemeView) itemTitleAtIndex:0] isEqualToString:@"小鹤双拼"] &&
                    [[((NSPopUpButton *)shuangpinSchemeView) itemTitleAtIndex:1] isEqualToString:@"自然码双拼"] &&
                    [[((NSPopUpButton *)shuangpinSchemeView) itemTitleAtIndex:2] isEqualToString:@"首道双拼"] &&
                    [[((NSPopUpButton *)shuangpinSchemeView) itemTitleAtIndex:3] isEqualToString:@"微软双拼"] &&
                    [wubiSchemeView isKindOfClass:[NSPopUpButton class]] &&
                    ((NSPopUpButton *)wubiSchemeView).numberOfItems == 1 &&
                    [[((NSPopUpButton *)wubiSchemeView) itemTitleAtIndex:0] isEqualToString:@"86 五笔"],
                "The input-scheme rows did not expose their concrete scheme choices.");
        NSView *wubiSettingsRow = FindViewWithAccessibilityLabel(controller.window.contentView, @"五笔功能行");
        NSView *shuangpinKeymapRow = FindViewWithAccessibilityLabel(controller.window.contentView, @"双拼键位提示行");
        NSView *shuangpinKeymapView =
            FindViewWithAccessibilityLabel(controller.window.contentView, @"显示双拼键位提示");
        require(wubiSettingsRow != nil && !wubiSettingsRow.hidden,
                "The selected Wubi scheme did not reveal its settings row.");
        require(shuangpinKeymapRow != nil && shuangpinKeymapRow.hidden &&
                    [shuangpinKeymapView isKindOfClass:[NSButton class]],
                "The input-scheme card did not create the contextual Shuangpin keymap option.");
        require(fullWidthButton != nil && fullWidthButton.state == NSControlStateValueOff,
                "The keyboard-input page did not expose the full-width input toggle.");
        fullWidthButton.state = NSControlStateValueOn;
        require([NSApp sendAction:fullWidthButton.action to:fullWidthButton.target from:fullWidthButton] &&
                    [MetasequoiaPreferencesWindowController storedFullWidthInputEnabled],
                "The full-width input toggle did not persist its enabled state.");
        require(wubiSchemeButton.state == NSControlStateValueOn,
                "The keyboard-input page did not reflect the stored Wubi scheme.");
        [shuangpinSchemeButton performClick:nil];
        require([MetasequoiaPreferencesWindowController storedScheme] == 1,
                "The Shuangpin scheme choice did not persist its selection.");
        require(wubiSettingsRow.hidden, "The Wubi settings row remained visible after another scheme was selected.");
        require(!shuangpinKeymapRow.hidden && ((NSButton *)shuangpinKeymapView).state == NSControlStateValueOn,
                "Selecting Shuangpin did not reveal the stored beginner keymap option.");
        NSPopUpButton *shuangpinSchemaButton = (NSPopUpButton *)shuangpinSchemeView;
        require(shuangpinSchemaButton.enabled, "Selecting Shuangpin left the schema menu disabled.");
        [shuangpinSchemaButton selectItemAtIndex:3];
        require([NSApp sendAction:shuangpinSchemaButton.action
                               to:shuangpinSchemaButton.target
                             from:shuangpinSchemaButton] &&
                    [[MetasequoiaPreferencesWindowController storedShuangpinSchema] isEqualToString:@"microsoft"],
                "The Shuangpin schema menu did not persist the Microsoft profile.");
        ((NSButton *)shuangpinKeymapView).state = NSControlStateValueOff;
        require([NSApp sendAction:((NSButton *)shuangpinKeymapView).action
                               to:((NSButton *)shuangpinKeymapView).target
                             from:shuangpinKeymapView] &&
                    ![[NSUserDefaults standardUserDefaults] boolForKey:@"MetasequoiaImeShuangpinKeymapEnabled"],
                "The Shuangpin keymap option did not persist its disabled state.");
        [wubiSchemeButton performClick:nil];
        require([MetasequoiaPreferencesWindowController storedScheme] == 2,
                "The Wubi scheme choice did not persist its selection.");
        require(!wubiSettingsRow.hidden, "Selecting Wubi did not reveal the inline settings entry.");
        require(shuangpinKeymapRow.hidden, "The Shuangpin keymap option remained visible after Wubi was selected.");
        NSView *wubiSettingsView = FindViewWithAccessibilityLabel(controller.window.contentView, @"五笔功能设置");
        require([wubiSettingsView isKindOfClass:[NSButton class]],
                "The keyboard-input page did not expose the Wubi settings entry.");
        NSButton *wubiSettingsButton = (NSButton *)wubiSettingsView;
        NSColor *wubiSettingsTitleColor = [wubiSettingsButton.attributedTitle attribute:NSForegroundColorAttributeName
                                                                                atIndex:0
                                                                         effectiveRange:nil];
        require(!wubiSettingsButton.bordered && [wubiSettingsButton.contentTintColor isEqual:[NSColor labelColor]] &&
                    [wubiSettingsTitleColor isEqual:[NSColor labelColor]],
                "The Wubi settings entry did not use the readable dynamic label color.");
        [wubiSettingsButton performClick:nil];
        NSView *wubiPage = FindViewWithAccessibilityLabel(controller.window.contentView, @"五笔设置页");
        require(wubiPage != nil && !wubiPage.hidden && generalPage.hidden &&
                    (generalNavigationItem.state == NSControlStateValueOn),
                "The Wubi settings entry did not open its detail page under the keyboard sidebar item.");
        NSView *wubiAutoCommitView =
            FindViewWithAccessibilityLabel(controller.window.contentView, @"四码唯一候选自动上屏");
        require([wubiAutoCommitView isKindOfClass:[NSButton class]] &&
                    ((NSButton *)wubiAutoCommitView).state == NSControlStateValueOff,
                "The Wubi detail page did not reflect the stored auto-commit preference.");
        NSButton *wubiAutoCommitButton = (NSButton *)wubiAutoCommitView;
        wubiAutoCommitButton.state = NSControlStateValueOn;
        require([NSApp sendAction:wubiAutoCommitButton.action
                               to:wubiAutoCommitButton.target
                             from:wubiAutoCommitButton] &&
                    [MetasequoiaPreferencesWindowController storedWubiAutoCommitUniqueEnabled],
                "The Wubi auto-commit option did not persist its enabled state.");
        NSView *wubiMixedPinyinView =
            FindViewWithAccessibilityLabel(controller.window.contentView, @"编码打不出时用拼音候选");
        require([wubiMixedPinyinView isKindOfClass:[NSButton class]] &&
                    ((NSButton *)wubiMixedPinyinView).state == NSControlStateValueOff,
                "The Wubi detail page did not reflect the stored mixed-pinyin preference.");
        NSButton *wubiMixedPinyinButton = (NSButton *)wubiMixedPinyinView;
        wubiMixedPinyinButton.state = NSControlStateValueOn;
        require([NSApp sendAction:wubiMixedPinyinButton.action
                               to:wubiMixedPinyinButton.target
                             from:wubiMixedPinyinButton] &&
                    [MetasequoiaPreferencesWindowController storedWubiMixedPinyinEnabled],
                "The Wubi mixed-pinyin option did not persist its enabled state.");
        [MetasequoiaPreferencesWindowController setWubiMixedPinyinEnabled:NO];

        // The code hint is the one wubi option that ships on, so the box opens checked and the
        // click being tested is the one that turns it off.
        NSView *wubiCodeHintView = FindViewWithAccessibilityLabel(controller.window.contentView, @"候选显示剩余编码");
        require([wubiCodeHintView isKindOfClass:[NSButton class]] &&
                    ((NSButton *)wubiCodeHintView).state == NSControlStateValueOn,
                "The Wubi detail page did not reflect the stored code-hint preference.");
        NSButton *wubiCodeHintButton = (NSButton *)wubiCodeHintView;
        wubiCodeHintButton.state = NSControlStateValueOff;
        require([NSApp sendAction:wubiCodeHintButton.action to:wubiCodeHintButton.target from:wubiCodeHintButton] &&
                    ![MetasequoiaPreferencesWindowController storedWubiCodeHintEnabled],
                "The Wubi code-hint option did not persist its disabled state.");
        [MetasequoiaPreferencesWindowController setWubiCodeHintEnabled:YES];

        NSButton *backToKeyboardButton = FindButtonWithTitle(controller.window.contentView, @"返回键盘输入");
        [backToKeyboardButton performClick:nil];
        require(!generalPage.hidden && wubiPage.hidden && (generalNavigationItem.state == NSControlStateValueOn),
                "The Wubi detail page did not return to keyboard-input settings under its sidebar item.");

        NSButton *websiteButton = FindButtonWithTitle(controller.window.contentView, @"访问 msime.app");
        require(websiteButton != nil && websiteButton.action == @selector(openWebsite:) &&
                    websiteButton.target == controller,
                "The updates page did not expose the canonical product website.");
        NSColor *websiteTitleColor = [websiteButton.attributedTitle attribute:NSForegroundColorAttributeName
                                                                      atIndex:0
                                                               effectiveRange:nil];
        require([websiteTitleColor isEqual:[NSColor linkColor]],
                "The canonical website link did not use the system link color.");

        [controller.window.contentView layoutSubtreeIfNeeded];
        NSView *schemeCard = FindViewWithAccessibilityLabel(controller.window.contentView, @"输入方式卡片");
        NSView *behaviorCard = FindViewWithAccessibilityLabel(controller.window.contentView, @"中英文状态切换卡片");
        NSView *candidatePageShortcutCard =
            FindViewWithAccessibilityLabel(controller.window.contentView, @"候选翻页快捷键卡片");
        NSView *learningCard = FindViewWithAccessibilityLabel(controller.window.contentView, @"候选与学习卡片");
        NSView *dataPrivacyCard = FindViewWithAccessibilityLabel(controller.window.contentView, @"数据与隐私卡片");
        NSView *softwareUpdateCard = FindViewWithAccessibilityLabel(controller.window.contentView, @"软件更新卡片");
        NSView *feedbackCard = FindViewWithAccessibilityLabel(controller.window.contentView, @"反馈与帮助卡片");
        require(schemeCard.frame.size.width == behaviorCard.frame.size.width &&
                    schemeCard.frame.size.width == candidatePageShortcutCard.frame.size.width &&
                    schemeCard.frame.size.width == learningCard.frame.size.width &&
                    schemeCard.frame.size.width == softwareUpdateCard.frame.size.width &&
                    schemeCard.frame.size.width == feedbackCard.frame.size.width,
                "The settings cards did not consistently fill the content width.");
        NSRect candidatePageShortcutCardRect = [generalPage convertRect:candidatePageShortcutCard.bounds
                                                               fromView:candidatePageShortcutCard];
        require(NSMaxY(candidatePageShortcutCardRect) <= NSMaxY(generalPage.bounds),
                "The candidate page shortcut card overflowed the keyboard-input page.");
        NSButton *footerRestoreButton = FindButtonWithTitle(controller.window.contentView, @"恢复默认设置");
        require(footerRestoreButton != nil, "The settings footer restore button was not found.");
        NSRect candidatePageShortcutRectInWindow =
            [controller.window.contentView convertRect:candidatePageShortcutCard.bounds
                                              fromView:candidatePageShortcutCard];
        NSRect footerRestoreRectInWindow = [controller.window.contentView convertRect:footerRestoreButton.bounds
                                                                             fromView:footerRestoreButton];
        require(NSMinY(candidatePageShortcutRectInWindow) >= NSMaxY(footerRestoreRectInWindow) + 8.0,
                "The keyboard-input controls overlapped the settings footer.");
        NSView *wubiSettingsRowInCard = FindViewWithAccessibilityLabel(controller.window.contentView, @"五笔功能行");
        require(wubiSettingsRowInCard != nil && !wubiSettingsRowInCard.hidden,
                "The Wubi settings row was not visible for the card width check.");
        for (NSView *cardEntry in wubiSettingsRowInCard.superview.subviews)
        {
            require(cardEntry.hidden || NSWidth(cardEntry.frame) == NSWidth(wubiSettingsRowInCard.superview.bounds),
                    "A scheme card row or separator did not fill its card width.");
        }
        NSRect feedbackCardRect = [updatesPage convertRect:feedbackCard.bounds fromView:feedbackCard];
        require(NSMaxY(feedbackCardRect) <= NSMaxY(updatesPage.bounds),
                "The feedback card overflowed the updates page.");
        require(dataPrivacyCard != nil, "The data page did not expose its final preference card.");
        NSRect dataPrivacyRectInWindow = [controller.window.contentView convertRect:dataPrivacyCard.bounds
                                                                           fromView:dataPrivacyCard];
        require(NSMinY(dataPrivacyRectInWindow) >= NSMaxY(footerRestoreRectInWindow) + 8.0,
                "The data-page controls overlapped the settings footer.");

        NSView *view = FindViewWithAccessibilityLabel(controller.window.contentView, @"候选排列");
        require([view isKindOfClass:[NSPopUpButton class]],
                "The settings window did not expose the candidate layout control.");
        NSPopUpButton *styleButton = (NSPopUpButton *)view;
        require(styleButton.numberOfItems == 2 && [[styleButton itemTitleAtIndex:0] isEqualToString:@"横向排列"] &&
                    [[styleButton itemTitleAtIndex:1] isEqualToString:@"纵向列表"],
                "The candidate layout control did not contain both supported layouts.");
        require(styleButton.indexOfSelectedItem == 1,
                "The candidate layout control did not reflect the stored vertical layout.");

        NSView *pageSizeView = FindViewWithAccessibilityLabel(controller.window.contentView, @"每页候选");
        require([pageSizeView isKindOfClass:[NSPopUpButton class]],
                "The settings window did not expose the candidate page-size control.");
        NSPopUpButton *pageSizeButton = (NSPopUpButton *)pageSizeView;
        require(pageSizeButton.numberOfItems == 9 && [[pageSizeButton itemTitleAtIndex:0] isEqualToString:@"1 个"] &&
                    [[pageSizeButton itemTitleAtIndex:5] isEqualToString:@"6 个"] &&
                    [[pageSizeButton itemTitleAtIndex:8] isEqualToString:@"9 个"],
                "The candidate page-size control did not contain all supported values.");
        require(pageSizeButton.indexOfSelectedItem == 4,
                "The candidate page-size control did not reflect the stored value.");

        require(FindViewWithAccessibilityLabel(controller.window.contentView, @"Fluent皮肤卡片") != nil &&
                    FindViewWithAccessibilityLabel(controller.window.contentView, @"微信绿皮肤卡片") != nil &&
                    FindViewWithAccessibilityLabel(controller.window.contentView, @"石墨 Graphite皮肤卡片") != nil &&
                    FindViewWithAccessibilityLabel(controller.window.contentView, @"杨柳青皮肤卡片") != nil,
                "The skin page did not expose a card for each built-in Windows skin.");
        NSView *openSkinsView = FindViewWithAccessibilityLabel(controller.window.contentView, @"打开皮肤目录");
        NSView *refreshSkinsView = FindViewWithAccessibilityLabel(controller.window.contentView, @"刷新皮肤");
        NSView *skinDirectoryView = FindViewWithAccessibilityLabel(controller.window.contentView, @"外部皮肤目录");
        NSView *emptySkinsView = FindViewWithAccessibilityLabel(controller.window.contentView, @"外部皮肤空状态");
        require([openSkinsView isKindOfClass:[NSButton class]] && [refreshSkinsView isKindOfClass:[NSButton class]],
                "The skin page did not expose open-directory and refresh actions.");
        require(skinDirectoryView != nil && emptySkinsView != nil,
                "The skin page did not expose the external-skin directory and empty state.");
        NSView *fluentSwitchView = FindViewWithAccessibilityLabel(controller.window.contentView, @"启用Fluent");
        require([fluentSwitchView isKindOfClass:[NSSwitch class]], "The Fluent card did not expose an enable switch.");
        NSSwitch *fluentSwitch = (NSSwitch *)fluentSwitchView;
        [MetasequoiaPreferencesWindowController setStoredCandidateSkin:@"fluent"];
        require(fluentSwitch.state == NSControlStateValueOn, "Fluent was not selected after activation.");
        [fluentSwitch performClick:nil];
        require(fluentSwitch.state == NSControlStateValueOn &&
                    [[MetasequoiaPreferencesWindowController storedCandidateSkin] isEqualToString:@"fluent"],
                "Clicking the active skin switch turned the skin off.");

        NSView *fontSizeView = FindViewWithAccessibilityLabel(controller.window.contentView, @"候选字号");
        require([fontSizeView isKindOfClass:[NSPopUpButton class]],
                "The settings window did not expose the candidate font-size control.");
        NSPopUpButton *fontSizeButton = (NSPopUpButton *)fontSizeView;
        require(fontSizeButton.numberOfItems == 25 && [[fontSizeButton itemTitleAtIndex:0] isEqualToString:@"12"] &&
                    [[fontSizeButton itemTitleAtIndex:6] isEqualToString:@"18"] &&
                    [[fontSizeButton itemTitleAtIndex:24] isEqualToString:@"36"],
                "The candidate font-size control did not contain all supported values.");
        require(fontSizeButton.indexOfSelectedItem == 4,
                "The candidate font-size control did not reflect the stored value.");

        NSView *candidatePreview = FindViewWithAccessibilityLabel(controller.window.contentView, @"候选窗口预览");
        NSView *appearanceCard = FindViewWithAccessibilityLabel(controller.window.contentView, @"候选窗口卡片");
        require(candidatePreview != nil, "The appearance page did not expose a candidate-window preview.");
        require(candidatePreview.frame.size.width == appearanceCard.frame.size.width,
                "The candidate preview did not fill the appearance-page content width.");
        require(candidatePreview.frame.size.height + 0.5 >=
                    [[candidatePreview valueForKey:@"previewContentHeight"] doubleValue],
                "The preview container was shorter than the configured candidate layout.");
        NSView *appearanceDocument = ((NSScrollView *)appearancePage).documentView;
        NSRect appearanceCardRect = [appearanceDocument convertRect:appearanceCard.bounds fromView:appearanceCard];
        require(NSMaxY(appearanceCardRect) <= NSMaxY(appearanceDocument.bounds),
                "The appearance controls overflowed the scrollable document.");
        require([candidatePreview.accessibilityValue isEqualToString:@"纵向列表，5 个候选，16 pt，英文释义"],
                "The candidate preview did not reflect the stored appearance settings.");
        const CGFloat verticalPreviewHeight = candidatePreview.frame.size.height;
        [styleButton selectItemAtIndex:0];
        require([NSApp sendAction:styleButton.action to:styleButton.target from:styleButton],
                "The candidate layout control did not apply the horizontal style.");
        [controller.window.contentView layoutSubtreeIfNeeded];
        require(candidatePreview.frame.size.height < verticalPreviewHeight,
                "The appearance preview did not shrink when switching from vertical to horizontal layout.");
        [styleButton selectItemAtIndex:1];
        require([NSApp sendAction:styleButton.action to:styleButton.target from:styleButton],
                "The candidate layout control did not restore the vertical style.");
        [controller.window.contentView layoutSubtreeIfNeeded];
        NSView *floatingToolbarView = FindViewWithAccessibilityLabel(controller.window.contentView, @"显示悬浮状态栏");
        NSView *floatingToolbarCard = FindViewWithAccessibilityLabel(controller.window.contentView, @"悬浮状态栏卡片");
        require([floatingToolbarView isKindOfClass:[NSButton class]],
                "The appearance page did not expose the floating-toolbar control.");
        require(floatingToolbarCard != nil, "The appearance page did not expose the floating-toolbar preference card.");
        NSRect floatingToolbarRectInWindow = [controller.window.contentView convertRect:floatingToolbarCard.bounds
                                                                               fromView:floatingToolbarCard];
        require(NSMinY(floatingToolbarRectInWindow) >= NSMaxY(footerRestoreRectInWindow) + 8.0,
                "The floating-toolbar preference overlapped the settings footer.");
        NSButton *floatingToolbarButton = (NSButton *)floatingToolbarView;
        require(floatingToolbarButton.state == NSControlStateValueOff,
                "The floating-toolbar control did not reflect the stored disabled value.");
        NSAppearance *darkAppearance = [NSAppearance appearanceNamed:NSAppearanceNameDarkAqua];
        __block NSColor *darkCanvasColor = nil;
        __block NSColor *darkPanelColor = nil;
        __block NSColor *darkTextColor = nil;
        [darkAppearance performAsCurrentDrawingAppearance:^{
          darkCanvasColor = [[candidatePreview valueForKey:@"previewCanvasFillColor"]
              colorUsingColorSpace:[NSColorSpace sRGBColorSpace]];
          darkPanelColor = [[candidatePreview valueForKey:@"previewPanelFillColor"]
              colorUsingColorSpace:[NSColorSpace sRGBColorSpace]];
          darkTextColor =
              [[candidatePreview valueForKey:@"previewTextColor"] colorUsingColorSpace:[NSColorSpace sRGBColorSpace]];
        }];
        require(std::abs(RelativeLuminance(darkPanelColor) - RelativeLuminance(darkCanvasColor)) >= 0.01,
                "The candidate panel collapsed into the preview canvas in Dark Aqua.");
        require(ContrastRatio(darkTextColor, darkPanelColor) >= 4.5,
                "The preview candidate text did not remain readable in Dark Aqua.");

        NSView *learningView = FindViewWithAccessibilityLabel(controller.window.contentView, @"记住候选词频");
        require([learningView isKindOfClass:[NSButton class]],
                "The settings window did not expose the candidate-learning control.");
        NSButton *learningButton = (NSButton *)learningView;
        require(learningButton.state == NSControlStateValueOff,
                "The candidate-learning control did not reflect the stored disabled value.");
        NSView *frequencyModeView = FindViewWithAccessibilityLabel(controller.window.contentView, @"调频方式");
        NSView *frequencyTriggerView = FindViewWithAccessibilityLabel(controller.window.contentView, @"触发频次");
        NSView *frequencyStepView = FindViewWithAccessibilityLabel(controller.window.contentView, @"线性调频步长");
        require([frequencyModeView isKindOfClass:[NSPopUpButton class]] &&
                    [frequencyTriggerView isKindOfClass:[NSPopUpButton class]] &&
                    [frequencyStepView isKindOfClass:[NSPopUpButton class]],
                "The settings window did not expose the frequency-adjustment controls.");
        NSPopUpButton *frequencyModeButton = (NSPopUpButton *)frequencyModeView;
        NSPopUpButton *frequencyTriggerButton = (NSPopUpButton *)frequencyTriggerView;
        NSPopUpButton *frequencyStepButton = (NSPopUpButton *)frequencyStepView;
        require([frequencyModeButton.itemTitles isEqualToArray:@[ @"一次置顶", @"折半调频", @"线性调频", @"一次置前" ]],
                "The frequency mode control did not contain the Windows-compatible algorithms.");
        require(frequencyModeButton.indexOfSelectedItem == 0 && frequencyTriggerButton.indexOfSelectedItem == 2 &&
                    frequencyStepButton.indexOfSelectedItem == 1 && !frequencyModeButton.enabled &&
                    !frequencyTriggerButton.enabled && !frequencyStepButton.enabled,
                "The frequency controls did not reflect the stored pin/3/2 values and disabled learning state.");
        // Quanpin and shuangpin carry their own helpcode switch, each governing its own scheme list.
        NSView *helpcodeView = FindViewWithAccessibilityLabel(controller.window.contentView, @"全拼辅助码");
        NSView *shuangpinHelpcodeView = FindViewWithAccessibilityLabel(controller.window.contentView, @"双拼辅助码");
        require([helpcodeView isKindOfClass:[NSButton class]] && [shuangpinHelpcodeView isKindOfClass:[NSButton class]],
                "The settings window did not expose a helpcode control for each scheme.");
        NSButton *helpcodeButton = (NSButton *)helpcodeView;
        NSButton *shuangpinHelpcodeButton = (NSButton *)shuangpinHelpcodeView;
        NSView *quanpinHelpcodeSchemaView =
            FindViewWithAccessibilityLabel(controller.window.contentView, @"全拼辅助码方案");
        NSView *shuangpinHelpcodeSchemaView =
            FindViewWithAccessibilityLabel(controller.window.contentView, @"双拼辅助码方案");
        require([quanpinHelpcodeSchemaView isKindOfClass:[NSPopUpButton class]] &&
                    [shuangpinHelpcodeSchemaView isKindOfClass:[NSPopUpButton class]],
                "The settings window did not expose both helpcode scheme controls.");
        NSPopUpButton *quanpinHelpcodeSchemaButton = (NSPopUpButton *)quanpinHelpcodeSchemaView;
        NSPopUpButton *shuangpinHelpcodeSchemaButton = (NSPopUpButton *)shuangpinHelpcodeSchemaView;
        NSArray<NSString *> *helpcodeSchemaTitles = @[ @"蓝天小雨点", @"自然码", @"首右2.0", @"首右plus", @"小鹤" ];
        require([quanpinHelpcodeSchemaButton.itemTitles isEqualToArray:helpcodeSchemaTitles] &&
                    [shuangpinHelpcodeSchemaButton.itemTitles isEqualToArray:helpcodeSchemaTitles],
                "The helpcode controls did not contain all five Windows-compatible schemes.");
        require(quanpinHelpcodeSchemaButton.indexOfSelectedItem == 1 &&
                    shuangpinHelpcodeSchemaButton.indexOfSelectedItem == 3 && quanpinHelpcodeSchemaButton.enabled &&
                    shuangpinHelpcodeSchemaButton.enabled,
                "The helpcode controls did not reflect the stored schemes and enabled state.");

        // The account's own model leads the providers, since it is the one needing no keys of the
        // user's own, and the language list reaches past the three the phrase services shipped with.
        NSView *translationProviderView =
            FindViewWithAccessibilityLabel(controller.window.contentView, @"候选翻译在线服务");
        NSView *translationLanguageView =
            FindViewWithAccessibilityLabel(controller.window.contentView, @"候选翻译目标语言");
        require([translationProviderView isKindOfClass:[NSPopUpButton class]] &&
                    [translationLanguageView isKindOfClass:[NSPopUpButton class]],
                "The settings window did not expose the candidate translation controls.");
        require([((NSPopUpButton *)translationProviderView).itemTitles.firstObject isEqualToString:@"水杉账号 AI"],
                "The account model was not offered first among the translation providers.");
        require([((NSPopUpButton *)translationLanguageView).itemTitles containsObject:@"西班牙语"],
                "The translation languages did not reach past the three the services shipped with.");

        // Each provider shows only what it needs. Leaving a vendor's key fields under the account
        // model reads as though it wanted them, which is how this shipped the first time.
        NSPopUpButton *translationProviderButton = (NSPopUpButton *)translationProviderView;
        NSView *tencentIdRow = FindViewWithAccessibilityLabel(controller.window.contentView, @"腾讯云 SecretId 行");
        NSView *endpointRow = FindViewWithAccessibilityLabel(controller.window.contentView, @"DeepLX Endpoint 行");
        NSView *accountStatus = FindViewWithAccessibilityLabel(controller.window.contentView, @"候选翻译账号状态行");
        require(tencentIdRow != nil && endpointRow != nil && accountStatus != nil,
                "The translation card did not expose a row for each provider's requirements.");
        const auto rowHidden = [](NSView *view) { return view.hidden; };
        for (NSInteger index = 0; index < translationProviderButton.numberOfItems; ++index)
        {
            [translationProviderButton selectItemAtIndex:index];
            require([NSApp sendAction:translationProviderButton.action
                                   to:translationProviderButton.target
                                 from:translationProviderButton],
                    "Choosing a translation provider was not acted on.");
            const BOOL account = index == 0;
            const BOOL tencent = index == 1;
            const BOOL deeplx = index == 2;
            require(rowHidden(tencentIdRow) == !tencent,
                    "The Tencent credential rows did not follow the chosen provider.");
            require(rowHidden(endpointRow) == !deeplx, "The DeepLX endpoint row did not follow the chosen provider.");
            require(rowHidden(accountStatus) == !account,
                    "The account status line did not follow the chosen provider.");
        }
        // Signed out, the row also carries the way to sign in: the entry lives on another page, and
        // naming a requirement without a route to it is how this sent someone hunting for a button
        // that was never on that page.
        NSView *signInView = FindViewWithAccessibilityLabel(controller.window.contentView, @"登录水杉账号");
        require([signInView isKindOfClass:[NSButton class]],
                "The account provider named a requirement without offering the way to meet it.");
        require(((NSButton *)signInView).target != nil && ((NSButton *)signInView).action != nullptr,
                "The sign-in button was not wired to anything.");

        [translationProviderButton selectItemAtIndex:0];
        require([NSApp sendAction:translationProviderButton.action
                               to:translationProviderButton.target
                             from:translationProviderButton],
                "Restoring the account provider was not acted on.");

        NSView *hudView = FindViewWithAccessibilityLabel(controller.window.contentView, @"切换中英文时显示提示");
        require([hudView isKindOfClass:[NSButton class]] && ((NSButton *)hudView).state == NSControlStateValueOn,
                "The settings window did not reflect the stored input-mode badge preference.");
        NSButton *hudButton = (NSButton *)hudView;
        hudButton.state = NSControlStateValueOff;
        require([NSApp sendAction:hudButton.action to:hudButton.target from:hudButton] &&
                    ![MetasequoiaPreferencesWindowController storedInputModeHUDEnabled],
                "The input-mode badge option did not persist its disabled state.");
        [MetasequoiaPreferencesWindowController setInputModeHUDEnabled:YES];

        NSView *shortcutView = FindViewWithAccessibilityLabel(controller.window.contentView, @"Shift 切换中英文");
        require([shortcutView isKindOfClass:[NSButton class]],
                "The settings window did not expose the input-mode shortcut control.");
        NSButton *shortcutButton = (NSButton *)shortcutView;
        require(shortcutButton.state == NSControlStateValueOff,
                "The input-mode shortcut control did not reflect the stored disabled value.");

        NSView *resetLearningView = FindViewWithAccessibilityLabel(controller.window.contentView, @"清除学习数据");
        require([resetLearningView isKindOfClass:[NSButton class]],
                "The settings window did not expose the learned-data reset button.");
        NSButton *resetLearningButton = (NSButton *)resetLearningView;
        NSView *versionView = FindViewWithAccessibilityLabel(controller.window.contentView, @"当前版本");
        require([versionView isKindOfClass:[NSTextField class]] && ((NSTextField *)versionView).stringValue.length > 0,
                "The updates page did not expose the installed version.");
        NSView *automaticUpdatesView = FindViewWithAccessibilityLabel(controller.window.contentView, @"自动更新状态");
        require([automaticUpdatesView isKindOfClass:[NSTextField class]] &&
                    [((NSTextField *)automaticUpdatesView).stringValue isEqualToString:@"已开启自动检查"],
                "The updates page did not show the enabled automatic-check state.");
        updateDriver.automaticallyChecksForUpdates = NO;
        [controller refreshUpdateControls];
        require([((NSTextField *)automaticUpdatesView).stringValue isEqualToString:@"自动检查已关闭"],
                "The updates page did not refresh the disabled automatic-check state.");
        NSView *checkNowView = FindViewWithAccessibilityLabel(controller.window.contentView, @"立即检查更新");
        require([checkNowView isKindOfClass:[NSButton class]] &&
                    [((NSButton *)checkNowView).title containsString:@"检查更新"] &&
                    [((NSButton *)checkNowView).accessibilityHelp containsString:@"msime.app"] &&
                    ((NSButton *)checkNowView).action == @selector(checkForUpdates:) &&
                    ((NSButton *)checkNowView).target == controller,
                "The updates page did not expose an in-place update action.");
        require(CountButtonsWithAction(controller.window.contentView, @selector(checkForUpdates:)) == 1,
                "The settings window exposed duplicate software-update actions.");
        NSView *feedbackView = FindViewWithAccessibilityLabel(controller.window.contentView, @"提交反馈");
        require([feedbackView isKindOfClass:[NSButton class]] &&
                    ((NSButton *)feedbackView).action == @selector(openFeedback:) &&
                    ((NSButton *)feedbackView).target == controller,
                "The updates page did not expose a feedback action.");
        NSColor *feedbackTitleColor =
            [((NSButton *)feedbackView).attributedTitle attribute:NSForegroundColorAttributeName
                                                          atIndex:0
                                                   effectiveRange:nil];
        require([feedbackTitleColor isEqual:[NSColor linkColor]],
                "The updates-page actions did not remain visually distinct from disabled controls.");

        __block bool resetStartedAfterCancel = false;
        id cancelObserver =
            [[NSNotificationCenter defaultCenter] addObserverForName:MetasequoiaWillResetLearnedDataNotification
                                                              object:nil
                                                               queue:nil
                                                          usingBlock:^(NSNotification *notification) {
                                                            (void)notification;
                                                            resetStartedAfterCancel = true;
                                                          }];
        [resetLearningButton performClick:nil];
        [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.01]];
        NSWindow *confirmationSheet = controller.window.attachedSheet;
        require(confirmationSheet != nil, "The learned-data reset button did not present a confirmation sheet.");
        NSButton *cancelResetButton = FindButtonWithTitle(confirmationSheet.contentView, @"取消");
        NSButton *confirmResetButton = FindButtonWithTitle(confirmationSheet.contentView, @"清除");
        require(cancelResetButton != nil && confirmationSheet.defaultButtonCell == cancelResetButton.cell,
                "The learned-data reset confirmation did not make cancellation the default action.");
        require(confirmResetButton != nil && confirmResetButton.hasDestructiveAction,
                "The learned-data reset confirmation did not mark the clear action as destructive.");
        [cancelResetButton performClick:nil];
        [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.01]];
        [[NSNotificationCenter defaultCenter] removeObserver:cancelObserver];
        require(!resetStartedAfterCancel && controller.window.attachedSheet == nil,
                "Cancelling the learned-data reset started destructive work.");

        __block bool resetNotificationReceived = false;
        id resetObserver =
            [[NSNotificationCenter defaultCenter] addObserverForName:MetasequoiaWillResetLearnedDataNotification
                                                              object:nil
                                                               queue:nil
                                                          usingBlock:^(NSNotification *notification) {
                                                            (void)notification;
                                                            resetNotificationReceived = true;
                                                          }];
        [MetasequoiaPreferencesWindowController prepareInputSessionsForLearnedDataReset];
        [[NSNotificationCenter defaultCenter] removeObserver:resetObserver];
        require(resetNotificationReceived,
                "The learned-data reset did not synchronously request input-session quiescence.");

        [styleButton selectItemAtIndex:0];
        require([NSApp sendAction:styleButton.action to:styleButton.target from:styleButton],
                "The candidate layout control did not dispatch its action.");
        require([MetasequoiaPreferencesWindowController storedCandidatePanelStyle] == 0,
                "The candidate layout control did not store the selected horizontal layout.");

        [pageSizeButton selectItemAtIndex:6];
        require([NSApp sendAction:pageSizeButton.action to:pageSizeButton.target from:pageSizeButton],
                "The candidate page-size control did not dispatch its action.");
        require([MetasequoiaPreferencesWindowController storedCandidatePageSize] == 7,
                "The candidate page-size control did not store the selected value.");

        [fontSizeButton selectItemAtIndex:8];
        require([NSApp sendAction:fontSizeButton.action to:fontSizeButton.target from:fontSizeButton],
                "The candidate font-size control did not dispatch its action.");
        require([MetasequoiaPreferencesWindowController storedCandidateFontSize] == 20,
                "The candidate font-size control did not store the selected value.");
        require([candidatePreview.accessibilityValue isEqualToString:@"横向排列，7 个候选，20 pt"],
                "The candidate preview did not update after the appearance controls changed.");
        NSButton *translationsButton = FindButtonWithTitle(controller.window.contentView, @"竖排候选显示英文释义");
        require(translationsButton != nil, "The appearance page did not expose the candidate translation toggle.");
        require([MetasequoiaPreferencesWindowController storedCandidateTranslationsEnabled] &&
                    translationsButton.state == NSControlStateValueOn,
                "Candidate translations were not enabled by default.");
        translationsButton.state = NSControlStateValueOff;
        require([NSApp sendAction:translationsButton.action to:translationsButton.target from:translationsButton] &&
                    ![MetasequoiaPreferencesWindowController storedCandidateTranslationsEnabled],
                "The candidate translation control did not persist the disabled value.");
        [styleButton selectItemAtIndex:1];
        require([NSApp sendAction:styleButton.action to:styleButton.target from:styleButton],
                "The candidate layout control did not dispatch its vertical-layout action.");
        translationsButton.state = NSControlStateValueOn;
        require([NSApp sendAction:translationsButton.action to:translationsButton.target from:translationsButton] &&
                    [candidatePreview.accessibilityValue isEqualToString:@"纵向列表，7 个候选，20 pt，英文释义"],
                "The candidate preview did not mention English glosses for a vertical list.");
        [styleButton selectItemAtIndex:0];
        require([NSApp sendAction:styleButton.action to:styleButton.target from:styleButton],
                "The candidate layout control did not restore the horizontal layout.");

        floatingToolbarButton.state = NSControlStateValueOn;
        require([NSApp sendAction:floatingToolbarButton.action
                               to:floatingToolbarButton.target
                             from:floatingToolbarButton] &&
                    [MetasequoiaPreferencesWindowController storedFloatingToolbarEnabled],
                "The floating-toolbar control did not persist the selected value.");
        [MetasequoiaPreferencesWindowController setFloatingToolbarEnabled:NO];
        require(floatingToolbarButton.state == NSControlStateValueOff,
                "The floating-toolbar control did not follow the preference after the toolbar menu hid the bar.");
        [MetasequoiaPreferencesWindowController setFloatingToolbarEnabled:YES];
        require(floatingToolbarButton.state == NSControlStateValueOn,
                "The floating-toolbar control did not follow the preference after the bar was re-enabled.");

        NSButton *chinesePunctuationButton = FindButtonWithTitle(controller.window.contentView, @"使用中文标点");
        require(chinesePunctuationButton != nil,
                "The keyboard-input page did not expose the Chinese punctuation toggle.");
        [MetasequoiaPreferencesWindowController setChinesePunctuationEnabled:NO];
        require(chinesePunctuationButton.state == NSControlStateValueOff,
                "The Chinese punctuation control did not follow the preference after the toolbar switched to ASCII "
                "punctuation.");
        [MetasequoiaPreferencesWindowController setChinesePunctuationEnabled:YES];
        require(chinesePunctuationButton.state == NSControlStateValueOn,
                "The Chinese punctuation control did not follow the preference after the toolbar restored Chinese "
                "punctuation.");

        [MetasequoiaPreferencesWindowController setFullWidthInputEnabled:NO];
        require(fullWidthButton.state == NSControlStateValueOff,
                "The full-width input control did not follow the preference after the toolbar switched to half-width "
                "input.");
        [MetasequoiaPreferencesWindowController setFullWidthInputEnabled:YES];
        require(fullWidthButton.state == NSControlStateValueOn,
                "The full-width input control did not follow the preference after the toolbar switched to full-width "
                "input.");

        learningButton.state = NSControlStateValueOn;
        require([NSApp sendAction:learningButton.action to:learningButton.target from:learningButton],
                "The candidate-learning control did not dispatch its action.");
        require([MetasequoiaPreferencesWindowController storedCandidateLearningEnabled],
                "The candidate-learning control did not store the selected value.");
        require(frequencyModeButton.enabled && frequencyTriggerButton.enabled && !frequencyStepButton.enabled,
                "Enabling learning did not enable frequency mode and trigger controls.");
        [frequencyModeButton selectItemAtIndex:2];
        require(
            [NSApp sendAction:frequencyModeButton.action to:frequencyModeButton.target from:frequencyModeButton] &&
                [[MetasequoiaPreferencesWindowController storedFrequencyAdjustmentMode] isEqualToString:@"linear"] &&
                frequencyStepButton.enabled,
            "Selecting linear frequency did not persist the mode or enable the step control.");
        [frequencyTriggerButton selectItemAtIndex:4];
        [frequencyStepButton selectItemAtIndex:5];
        require([NSApp sendAction:frequencyTriggerButton.action
                               to:frequencyTriggerButton.target
                             from:frequencyTriggerButton] &&
                    [NSApp sendAction:frequencyStepButton.action
                                   to:frequencyStepButton.target
                                 from:frequencyStepButton] &&
                    [MetasequoiaPreferencesWindowController storedFrequencyTriggerCount] == 5 &&
                    [MetasequoiaPreferencesWindowController storedFrequencyLinearStep] == 6,
                "The frequency count controls did not persist the selected values.");

        [quanpinHelpcodeSchemaButton selectItemAtIndex:4];
        [shuangpinHelpcodeSchemaButton selectItemAtIndex:2];
        require([NSApp sendAction:quanpinHelpcodeSchemaButton.action
                               to:quanpinHelpcodeSchemaButton.target
                             from:quanpinHelpcodeSchemaButton] &&
                    [NSApp sendAction:shuangpinHelpcodeSchemaButton.action
                                   to:shuangpinHelpcodeSchemaButton.target
                                 from:shuangpinHelpcodeSchemaButton] &&
                    [[NSUserDefaults standardUserDefaults] integerForKey:@"MetasequoiaImeQuanpinHelpcodeSchema"] == 4 &&
                    [[NSUserDefaults standardUserDefaults] integerForKey:@"MetasequoiaImeShuangpinHelpcodeSchema"] == 2,
                "The helpcode scheme controls did not persist independent selections.");
        // Turning one scheme's helpcodes off leaves the other's alone: they were split apart for
        // exactly that, and one switch dimming both lists would be the old behaviour wearing a new
        // label.
        helpcodeButton.state = NSControlStateValueOff;
        require([NSApp sendAction:helpcodeButton.action to:helpcodeButton.target from:helpcodeButton] &&
                    !quanpinHelpcodeSchemaButton.enabled && shuangpinHelpcodeSchemaButton.enabled,
                "Disabling quanpin helpcodes did not leave the shuangpin scheme control alone.");
        shuangpinHelpcodeButton.state = NSControlStateValueOff;
        require([NSApp sendAction:shuangpinHelpcodeButton.action
                               to:shuangpinHelpcodeButton.target
                             from:shuangpinHelpcodeButton] &&
                    !shuangpinHelpcodeSchemaButton.enabled,
                "Disabling shuangpin helpcodes left its scheme control active.");

        shortcutButton.state = NSControlStateValueOn;
        require([NSApp sendAction:shortcutButton.action to:shortcutButton.target from:shortcutButton],
                "The input-mode shortcut control did not dispatch its action.");
        require([MetasequoiaPreferencesWindowController storedInputModeShortcutEnabled],
                "The input-mode shortcut control did not store the enabled value.");

        NSButton *edgeInput = (NSButton *)FindViewWithAccessibilityLabel(controller.window.contentView, @"以词定字");
        NSButton *bracketInput =
            (NSButton *)FindViewWithAccessibilityLabel(controller.window.contentView, @"方括号（[ / ]）");
        NSButton *mixedInput = (NSButton *)FindViewWithAccessibilityLabel(controller.window.contentView, @"中英混输");
        NSPopUpButton *prefixInput =
            (NSPopUpButton *)FindViewWithAccessibilityLabel(controller.window.contentView, @"英文候选最短前缀");
        require(edgeInput && bracketInput && mixedInput && prefixInput, "Input behavior controls are missing.");
        edgeInput.state = NSControlStateValueOn;
        [NSApp sendAction:edgeInput.action to:edgeInput.target from:edgeInput];
        require(bracketInput.state == NSControlStateValueOff && MetasequoiaCandidateKeyOptions(0).edgeSelection,
                "Edge selection UI did not disable bracket paging.");
        bracketInput.state = NSControlStateValueOn;
        [NSApp sendAction:bracketInput.action to:bracketInput.target from:bracketInput];
        require(edgeInput.state == NSControlStateValueOff, "Bracket paging UI did not disable edge selection.");
        mixedInput.state = NSControlStateValueOn;
        [NSApp sendAction:mixedInput.action to:mixedInput.target from:mixedInput];
        [prefixInput selectItemAtIndex:3];
        [NSApp sendAction:prefixInput.action to:prefixInput.target from:prefixInput];
        require(prefixInput.enabled && MetasequoiaInputInteger(@"englishMinimumPrefix", 2, 1, 10) == 4,
                "Mixed English UI did not persist its minimum prefix.");

        NSPopUpButton *mainFont =
            (NSPopUpButton *)FindViewWithAccessibilityLabel(controller.window.contentView, @"候选窗主字体");
        NSPopUpButton *fallbackFont =
            (NSPopUpButton *)FindViewWithAccessibilityLabel(controller.window.contentView, @"候选窗中文补充字体");
        NSPopUpButton *preeditSize =
            (NSPopUpButton *)FindViewWithAccessibilityLabel(controller.window.contentView, @"候选窗预编辑字号");
        NSPopUpButton *theme =
            (NSPopUpButton *)FindViewWithAccessibilityLabel(controller.window.contentView, @"主题模式");
        NSSwitch *follow =
            (NSSwitch *)FindViewWithAccessibilityLabel(controller.window.contentView, @"候选窗口跟随光标");
        NSColorWell *color =
            (NSColorWell *)FindViewWithAccessibilityLabel(controller.window.contentView, @"候选文字颜色");
        require(mainFont && fallbackFont && preeditSize && theme && follow && color,
                "Advanced appearance controls are missing.");
        [mainFont selectItemWithTitle:@"Menlo"];
        [NSApp sendAction:mainFont.action to:mainFont.target from:mainFont];
        require([MetasequoiaAppearancePreferences()[@"font"] isEqualToString:@"Menlo"],
                "The main font control did not persist.");
        [preeditSize selectItemWithTitle:@"24"];
        [NSApp sendAction:preeditSize.action to:preeditSize.target from:preeditSize];
        require(MetasequoiaAppearanceInteger(@"preeditSize", 15, 10, 36) == 24, "Preedit size was not stored.");
        follow.state = NSControlStateValueOff;
        [NSApp sendAction:follow.action to:follow.target from:follow];
        require(!MetasequoiaCandidateFollowsCaret(), "Follow-caret switch did not persist.");
        [theme selectItemAtIndex:2];
        [NSApp sendAction:theme.action to:theme.target from:theme];
        require([controller.window.appearance.name isEqualToString:NSAppearanceNameDarkAqua],
                "Theme did not reach the settings window.");
        color.color = [NSColor colorWithSRGBRed:0.2 green:0.3 blue:0.4 alpha:1];
        [NSApp sendAction:color.action to:color.target from:color];
        require(MetasequoiaCandidateTextColor() != nil, "The color control did not persist.");
        [FindButtonWithTitle(controller.window.contentView, @"跟随主题") performClick:nil];
        require(MetasequoiaCandidateTextColor() == nil, "Follow-theme did not remove the color override.");
        [pageSizeButton selectItemWithTitle:@"6 个"];
        [NSApp sendAction:pageSizeButton.action to:pageSizeButton.target from:pageSizeButton];
        [fontSizeButton selectItemWithTitle:@"17"];
        [NSApp sendAction:fontSizeButton.action to:fontSizeButton.target from:fontSizeButton];
        require([MetasequoiaPreferencesWindowController storedCandidatePageSize] == 6 &&
                    [MetasequoiaPreferencesWindowController storedCandidateFontSize] == 17,
                "The expanded local candidate settings did not persist.");
        require([[MetasequoiaPreferencesWindowController
                    validateCloudSettingsSnapshot:[MetasequoiaPreferencesWindowController cloudSettingsSnapshot]]
                    boolValue],
                "Local appearance extensions broke the existing cloud contract.");
        [MetasequoiaPreferencesWindowController setCandidatePanelStyle:99];
        require([MetasequoiaPreferencesWindowController storedCandidatePanelStyle] == 0,
                "An unsupported candidate layout preference was not normalized safely.");
        [MetasequoiaPreferencesWindowController setCandidatePageSize:99];
        require([MetasequoiaPreferencesWindowController storedCandidatePageSize] == 9,
                "An unsupported candidate page size was not normalized safely.");
        [MetasequoiaPreferencesWindowController setCandidateFontSize:99];
        require([MetasequoiaPreferencesWindowController storedCandidateFontSize] == 18,
                "An unsupported candidate font size was not normalized safely.");
        [MetasequoiaPreferencesWindowController setStoredScheme:1];
        [MetasequoiaPreferencesWindowController setAutocorrectEnabled:NO];
        [MetasequoiaPreferencesWindowController setHelpcodeEnabled:NO];
        [MetasequoiaPreferencesWindowController setChinesePunctuationEnabled:NO];
        [MetasequoiaPreferencesWindowController setCandidatePanelStyle:1];
        [MetasequoiaPreferencesWindowController setStoredCandidateSkin:@"wechat"];
        [MetasequoiaPreferencesWindowController setCandidatePageSize:5];
        [MetasequoiaPreferencesWindowController setCandidateFontSize:20];
        [MetasequoiaPreferencesWindowController setCandidateTranslationsEnabled:NO];
        [MetasequoiaPreferencesWindowController setCandidatePageShortcut:2];
        [MetasequoiaPreferencesWindowController setCandidateLearningEnabled:NO];
        [MetasequoiaPreferencesWindowController setFrequencyAdjustmentMode:@"halve"];
        [MetasequoiaPreferencesWindowController setFrequencyTriggerCount:4];
        [MetasequoiaPreferencesWindowController setFrequencyLinearStep:3];
        [MetasequoiaPreferencesWindowController setInputModeShortcutEnabled:NO];
        [MetasequoiaPreferencesWindowController setFullWidthInputEnabled:YES];
        [MetasequoiaPreferencesWindowController setFloatingToolbarEnabled:NO];
        [MetasequoiaPreferencesWindowController setTraditionalChineseOutputEnabled:YES];
        [MetasequoiaPreferencesWindowController setEnglishInputMode:YES];
        [MetasequoiaPreferencesWindowController setWubiAutoCommitUniqueEnabled:YES];
        [MetasequoiaPreferencesWindowController setWubiMixedPinyinEnabled:YES];
        [MetasequoiaPreferencesWindowController setWubiCodeHintEnabled:NO];
        [MetasequoiaPreferencesWindowController setInputModeHUDEnabled:NO];
        [[NSUserDefaults standardUserDefaults] setBool:YES forKey:@"MetasequoiaImeShuangpinKeymapEnabled"];
        NSButton *restoreDefaultsButton = FindButtonWithTitle(controller.window.contentView, @"恢复默认设置");
        require(restoreDefaultsButton != nil, "The settings window did not expose the restore-defaults button.");
        [restoreDefaultsButton performClick:nil];
        require(
            [MetasequoiaPreferencesWindowController storedScheme] == 0 &&
                [MetasequoiaPreferencesWindowController storedAutocorrectEnabled] &&
                [MetasequoiaPreferencesWindowController storedHelpcodeEnabled] &&
                [MetasequoiaPreferencesWindowController storedChinesePunctuationEnabled] &&
                [MetasequoiaPreferencesWindowController storedCandidatePanelStyle] == 0 &&
                [[MetasequoiaPreferencesWindowController storedCandidateSkin] isEqualToString:@"fluent"] &&
                [MetasequoiaPreferencesWindowController storedCandidatePageSize] == 9 &&
                [MetasequoiaPreferencesWindowController storedCandidateFontSize] == 18 &&
                [MetasequoiaPreferencesWindowController storedCandidateTranslationsEnabled] &&
                [MetasequoiaPreferencesWindowController storedCandidatePageShortcut] == 0 &&
                [MetasequoiaPreferencesWindowController storedCandidateLearningEnabled] &&
                [[MetasequoiaPreferencesWindowController storedFrequencyAdjustmentMode] isEqualToString:@"promote"] &&
                [MetasequoiaPreferencesWindowController storedFrequencyTriggerCount] == 1 &&
                [MetasequoiaPreferencesWindowController storedFrequencyLinearStep] == 1 &&
                [MetasequoiaPreferencesWindowController storedInputModeShortcutEnabled] &&
                ![MetasequoiaPreferencesWindowController storedFullWidthInputEnabled] &&
                [MetasequoiaPreferencesWindowController storedFloatingToolbarEnabled] &&
                ![MetasequoiaPreferencesWindowController storedTraditionalChineseOutputEnabled] &&
                ![MetasequoiaPreferencesWindowController storedWubiAutoCommitUniqueEnabled] &&
                ![MetasequoiaPreferencesWindowController storedWubiMixedPinyinEnabled] &&
                [MetasequoiaPreferencesWindowController storedWubiCodeHintEnabled] &&
                [MetasequoiaPreferencesWindowController storedInputModeHUDEnabled] &&
                ![[NSUserDefaults standardUserDefaults] boolForKey:@"MetasequoiaImeShuangpinKeymapEnabled"] &&
                [[MetasequoiaPreferencesWindowController storedShuangpinSchema] isEqualToString:@"xiaohe"],
            "Restoring defaults did not restore every visible setting.");
        NSArray<NSString *> *preferenceKeys = @[
            @"MetasequoiaImeInputScheme",
            @"MetasequoiaImeShuangpinSchema",
            @"MetasequoiaImeQuanpinAutocorrect",
            @"MetasequoiaImeHelpcodeEnabled",
            @"MetasequoiaImeQuanpinHelpcodeSchema",
            @"MetasequoiaImeShuangpinHelpcodeSchema",
            @"MetasequoiaImeChinesePunctuation",
            @"MetasequoiaImeCandidatePanelStyle",
            @"MetasequoiaImeCandidateSkin",
            @"MetasequoiaImeCandidatePageSize",
            @"MetasequoiaImeCandidateFontSize",
            @"MetasequoiaImeCandidateTranslationsEnabled",
            @"MetasequoiaImeCandidatePageShortcut",
            @"MetasequoiaImeCandidateLearning",
            @"MetasequoiaImeFrequencyAdjustmentMode",
            @"MetasequoiaImeFrequencyTriggerCount",
            @"MetasequoiaImeFrequencyLinearStep",
            @"MetasequoiaImeInputModeShortcutEnabled",
            @"MetasequoiaImeInputModeHUD",
            @"MetasequoiaImeFullWidthInputEnabled",
            @"MetasequoiaImeFloatingToolbarEnabled",
            @"MetasequoiaImeTraditionalChineseOutput",
            @"MetasequoiaImeWubiAutoCommitUnique",
            @"MetasequoiaImeWubiMixedPinyin",
            @"MetasequoiaImeWubiCodeHint",
            @"MetasequoiaImeShuangpinKeymapEnabled",
        ];
        for (NSString *key in preferenceKeys)
        {
            require([[NSUserDefaults standardUserDefaults] objectForKey:key] == nil,
                    "Restoring defaults left a persisted override that can pin an obsolete default.");
        }
        require([MetasequoiaPreferencesWindowController storedEnglishInputMode],
                "Restoring configurable defaults unexpectedly changed the current input mode.");
        [MetasequoiaPreferencesWindowController setEnglishInputMode:NO];
        require(![MetasequoiaPreferencesWindowController storedEnglishInputMode],
                "The Chinese input-mode state was not stored.");

        __block bool standaloneCloseObserved = false;
        id standaloneCloseObserver = [[NSNotificationCenter defaultCenter]
            addObserverForName:MetasequoiaStandalonePreferencesDidCloseNotification
                        object:nil
                         queue:nil
                    usingBlock:^(NSNotification *notification) {
                      (void)notification;
                      standaloneCloseObserved = true;
                    }];
        MetasequoiaPreferencesWindowController *standaloneController =
            [[MetasequoiaPreferencesWindowController alloc] initWithUpdateController:updateController];
        [standaloneController showAndActivateForStandaloneLaunch];
        NSView *standaloneResetView =
            FindViewWithAccessibilityLabel(standaloneController.window.contentView, @"清除学习数据");
        require([standaloneResetView isKindOfClass:[NSButton class]] && !((NSButton *)standaloneResetView).enabled &&
                    [((NSButton *)standaloneResetView).accessibilityHelp containsString:@"输入菜单"],
                "Standalone settings allowed an unsafe learned-data reset.");
        NSButton *standaloneCloseButton = FindButtonWithTitle(standaloneController.window.contentView, @"关闭");
        require(standaloneCloseButton != nil, "The standalone settings window did not expose its close action.");
        [standaloneCloseButton performClick:nil];
        require(WaitUntil(^BOOL {
                  return standaloneCloseObserved && !standaloneController.window.visible;
                }),
                "Closing standalone settings did not finish or request application termination.");
        [[NSNotificationCenter defaultCenter] removeObserver:standaloneCloseObserver];
        NSDictionary *originalCloudSettings = [MetasequoiaPreferencesWindowController cloudSettingsSnapshot];
        require(originalCloudSettings.count == 20, "The cloud snapshot missed a native setting.");
        NSMutableDictionary *invalidSkinSettings = [originalCloudSettings mutableCopy];
        invalidSkinSettings[@"platform.macos.candidate_skin"] = @"../private";
        require(![[MetasequoiaPreferencesWindowController applyCloudSettingsSnapshot:invalidSkinSettings] boolValue],
                "An invalid skin identifier reached native settings.");
        require([[MetasequoiaPreferencesWindowController cloudSettingsSnapshot] isEqual:originalCloudSettings],
                "A rejected skin changed other settings.");
        invalidSkinSettings[@"platform.macos.candidate_skin"] = @"wechat\0hidden";
        require(![[MetasequoiaPreferencesWindowController applyCloudSettingsSnapshot:invalidSkinSettings] boolValue],
                "A truncated skin identifier was accepted.");
        invalidSkinSettings[@"platform.macos.candidate_skin"] = @"wechat";
        require([[MetasequoiaPreferencesWindowController applyCloudSettingsSnapshot:invalidSkinSettings] boolValue],
                "A valid skin could not be applied.");
        require([[MetasequoiaPreferencesWindowController storedCandidateSkin] isEqualToString:@"wechat"],
                "Cloud skin selection did not reach the native preference.");
        require([[MetasequoiaPreferencesWindowController applyCloudSettingsSnapshot:originalCloudSettings] boolValue],
                "Could not restore original skin settings.");
        NSMutableDictionary *invalidCloudSettings = [originalCloudSettings mutableCopy];
        invalidCloudSettings[@"platform.macos.input_scheme"] = @2;
        invalidCloudSettings[@"platform.macos.candidate_font_size"] = @17;
        require(![[MetasequoiaPreferencesWindowController applyCloudSettingsSnapshot:invalidCloudSettings] boolValue],
                "Unsupported cloud font size was accepted.");
        require([[MetasequoiaPreferencesWindowController cloudSettingsSnapshot] isEqual:originalCloudSettings],
                "Invalid cloud settings partially changed local preferences.");
        invalidCloudSettings[@"platform.macos.candidate_font_size"] = @18;
        invalidCloudSettings[@"platform.macos.candidate_learning"] = @1;
        require(![[MetasequoiaPreferencesWindowController applyCloudSettingsSnapshot:invalidCloudSettings] boolValue],
                "An integer was accepted for a boolean cloud setting.");
        invalidCloudSettings[@"platform.macos.candidate_learning"] = @YES;
        require([[MetasequoiaPreferencesWindowController applyCloudSettingsSnapshot:invalidCloudSettings] boolValue],
                "A valid full cloud settings snapshot was rejected.");
        require([[MetasequoiaPreferencesWindowController cloudSettingsSnapshot] isEqual:invalidCloudSettings],
                "Cloud settings did not roundtrip through native setters.");
        require([[MetasequoiaPreferencesWindowController applyCloudSettingsSnapshot:originalCloudSettings] boolValue],
                "The test settings could not be restored.");
    }
    return 0;
}
