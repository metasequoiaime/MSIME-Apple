#import "AppearancePreferences.h"
#import "SettingsLayout.h"
#import "../backend/account/BackendAccountEntry.h"
#import "../candidate/CandidateSkinPreviewView.h"
#import "../candidate/SkinSettingsView.h"
#import "../cloud/CloudAppearanceSettings.h"
#import "RuntimeOptions.h"
#import "../dictionary/DictionaryWindowController.h"

extern "C" bool msime_macos_uninstall_input_source(const char *bundle_path,
                                                     const char *user_data_path,
                                                     const char *preferences_domain,
                                                     bool remove_user_data) __attribute__((weak_import));
#import "../cloud/TranslationSettingsWindow.h"
#import "../core/DesktopSettingsLauncher.h"
#import "../core/AISettingsWindow.h"
#import "../core/SharedVoicePreferences.h"
#import "../core/UpdateController.h"
#import "../core/SupportWindowController.h"
#import "../voice/VoiceSettingsEntry.h"
#include "ShuangpinProfileNames.h"
#include "../candidate/CandidatePageSize.h"

/// The voice form, looked up at runtime. Linking it here would drag the voice module — and the
/// keychain and CoreAudio with it — into every test executable that builds this window.
@protocol MSIMEVoiceSettingsForm <NSObject>
- (void)reloadSettings;
@end

extern "C" NSView *MSIMEAccountPaneView(void) __attribute__((weak_import));
extern "C" void MSIMEAccountPaneAttach(NSWindow *window) __attribute__((weak_import));
extern "C" void MSIMEAccountPaneClose(void) __attribute__((weak_import));

NSNotificationName const MSIMEAppearanceDidChangeNotification = @"MSIMEClientAppearanceDidChange";
NSNotificationName const MSIMETranslationPreferencesDidSaveNotification = @"MSIMEClientTranslationPreferencesDidSave";
static NSString *const LayoutKey = @"MSIMEClientCandidatePanelStyle";
static NSString *const CandidateFollowCursorKey = @"MSIMEClientCandidateFollowCursor";
static NSString *const InputModeHUDKey = @"MSIMEClientInputModeHUD";
static NSString *const SchemeKey = @"MSIMEClientInputScheme";
static NSString *const ShuangpinProfileKey = @"MSIMEClientShuangpinProfile";
static NSString *const ShuangpinPreeditKey = @"MSIMEClientShuangpinPreeditUsesRaw";
static NSString *const LocalModesKey = @"MSIMEClientLocalModes";
static NSArray<NSArray<NSString *> *> *LocalModeControls() {
    return @[@[@"quick_phrase", @"快捷短语（K 模式）"], @[@"date_time", @"日期与时间（T 模式）"],
             @[@"unicode", @"Unicode 录入（U 模式）"], @[@"emoji", @"Emoji（E 模式）"],
             @[@"kaomoji", @"颜文字（M 模式）"], @[@"super_jianpin", @"超级简拼（J 模式）"],
             @[@"temporary_english", @"临时英文（Y 模式）"], @[@"temporary_japanese", @"临时日语（R 模式）"]];
}
static BOOL KnownLocalMode(NSString *mode) {
    for (NSArray *entry in LocalModeControls()) if ([entry[0] isEqual:mode]) return YES;
    return NO;
}
static BOOL LocalModeBoolean(id value) {
    return [value isKindOfClass:NSNumber.class] && CFGetTypeID((__bridge CFTypeRef)value) == CFBooleanGetTypeID();
}
static BOOL ValidMixedPrefix(id value) {
    return [value isKindOfClass:NSNumber.class] && CFGetTypeID((__bridge CFTypeRef)value) != CFBooleanGetTypeID() &&
           !CFNumberIsFloatType((__bridge CFNumberRef)value) && [value integerValue] >= 1 && [value integerValue] <= 8;
}
static NSString *const FontKey = @"MSIMEClientCandidateFontSize";
static NSString *const FontFamilyKey = @"MSIMEClientCandidateFontFamily";
static NSString *const CandidateEnglishFontKey = @"MSIMEClientCandidateEnglishFont";
static NSString *const TextColorKey = @"MSIMEClientCandidateTextColor";
static BOOL ValidTextColor(id value) {
    if (![value isKindOfClass:NSString.class] || [value length] != 7 || ![value hasPrefix:@"#"]) return NO;
    return [[value substringFromIndex:1] rangeOfCharacterFromSet:[[NSCharacterSet characterSetWithCharactersInString:@"0123456789abcdefABCDEF"] invertedSet]].location == NSNotFound;
}
static NSColor *CandidateColor(id value, NSColor *fallback) {
    if (!ValidTextColor(value)) return fallback;
    unsigned int rgb = 0;
    [[NSScanner scannerWithString:[value substringFromIndex:1]] scanHexInt:&rgb];
    return [NSColor colorWithSRGBRed:((rgb >> 16) & 255) / 255.0 green:((rgb >> 8) & 255) / 255.0 blue:(rgb & 255) / 255.0 alpha:1];
}
static id SharedCandidateColor(NSDictionary *preferences, NSString *key, id current) {
    id value = preferences[key];
    if (!value || value == NSNull.null) return NSNull.null;
    return ValidTextColor(value) ? [value copy] : current;
}
static NSString *const FallbackFontsKey = @"MSIMEClientCandidateFallbackFonts";
static BOOL ValidFontFamily(id value) {
    return [value isKindOfClass:NSString.class] && [value length] > 0 &&
           [value lengthOfBytesUsingEncoding:NSUTF8StringEncoding] <= 128 &&
           [value rangeOfCharacterFromSet:[NSCharacterSet controlCharacterSet]].location == NSNotFound;
}
static BOOL ValidFallbackFonts(id value) {
    if (![value isKindOfClass:NSArray.class] || [value count] > 32) return NO;
    for (id family in value) if (!ValidFontFamily(family)) return NO;
    return YES;
}
static NSString *const PreeditFontKey = @"MSIMEClientCandidatePreeditFontSize";
static NSString *const CandidatePreeditKey = @"MSIMEClientCandidatePreeditStyle";
static NSString *const PageShortcutKey = @"MSIMEClientCandidatePageShortcut";
static NSString *const NavigationKey = @"MSIMEClientNavigation";
static NSString *const WordCharacterKey = @"MSIMEClientWordCharacter";
static NSArray<NSArray<NSString *> *> *NavigationControls() {
    return @[@[@"minus_equal", @"减号/等号翻页"], @[@"comma_period", @"逗号/句号翻页"],
             @[@"brackets", @"方括号翻页"], @[@"tab", @"Tab / Shift-Tab 翻页"],
             @[@"page_up_down", @"Page Up / Page Down 翻页"], @[@"mouse_wheel", @"鼠标滚轮翻页"],
             @[@"arrows", @"方向键选择候选"]];
}
static NSString *const PageSizeKey = @"MSIMEClientCandidatePageSize";
static NSString *const SkinKey = @"MSIMEClientCandidateSkin";
static NSString *const EnglishKey = @"MSIMEClientEnglishInputMode";
static NSString *const DefaultImeModeKey = @"MSIMEClientDefaultImeMode";
static NSString *const ImeModeScopeKey = @"MSIMEClientImeModeScope";
static NSString *const TraditionalKey = @"MSIMEClientTraditionalOutput";
static NSString *const FullWidthKey = @"MSIMEClientFullWidthInput";
static NSString *const ChinesePunctuationKey = @"MSIMEClientChinesePunctuation";
static NSString *const SmartPunctuationKey = @"MSIMEClientSmartPunctuation";
static NSString *const SmartPunctuationRepeatToChineseKey = @"MSIMEClientSmartPunctuationRepeatToChinese";
static NSString *const SmartPunctuationSpaceConvertKey = @"MSIMEClientSmartPunctuationSpaceConvert";
static NSString *const PairedPunctuationKey = @"MSIMEClientPairedPunctuation";
static NSString *const PunctuationLockKey = @"MSIMEClientPunctuationLock";
static NSString *const MixedInputKey = @"MSIMEClientMixedInput";
static NSString *const AutocorrectKey = @"MSIMEClientAutocorrect";
static NSString *const CandidateLearningKey = @"MSIMEClientCandidateLearning";
static NSString *const FrequencyModeKey = @"MSIMEClientFrequencyAdjustmentMode";
static NSString *const FrequencyTriggerCountKey = @"MSIMEClientFrequencyTriggerCount";
static NSString *const FrequencyLinearStepKey = @"MSIMEClientFrequencyLinearStep";
static NSArray<NSString *> *FrequencyModes() { return @[@"disabled", @"pin", @"halve", @"linear", @"promote"]; }
static BOOL ValidFrequencyMode(id value) { return [value isKindOfClass:NSString.class] && [FrequencyModes() containsObject:value]; }
static BOOL ValidFrequencyCount(id value) {
    return [value isKindOfClass:NSNumber.class] && CFGetTypeID((__bridge CFTypeRef)value) != CFBooleanGetTypeID() &&
           !CFNumberIsFloatType((__bridge CFNumberRef)value) && [value integerValue] >= 1 && [value integerValue] <= 10;
}
static NSString *const FuzzyPinyinKey = @"MSIMEClientFuzzyPinyinEnabled";
static NSString *const FuzzyPinyinRulesKey = @"MSIMEClientFuzzyPinyinRules";
static NSArray<NSArray<NSString *> *> *FuzzyPinyinRuleControls() {
    return @[
        @[@"z-zh", @"z / zh"], @[@"c-ch", @"c / ch"], @[@"s-sh", @"s / sh"],
        @[@"n-l", @"n / l"], @[@"f-h", @"f / h"], @[@"r-l", @"r / l"],
        @[@"an-ang", @"an / ang"], @[@"en-eng", @"en / eng"], @[@"in-ing", @"in / ing"],
        @[@"ian-iang", @"ian / iang"], @[@"uan-uang", @"uan / uang"],
    ];
}
static BOOL ValidFuzzyPinyinRules(id value) {
    if (![value isKindOfClass:NSArray.class]) return NO;
    NSMutableSet *known = [NSMutableSet set];
    for (NSArray *entry in FuzzyPinyinRuleControls()) [known addObject:entry[0]];
    NSMutableSet *seen = [NSMutableSet set];
    for (id rule in value) {
        if (![rule isKindOfClass:NSString.class] || ![known containsObject:rule] || [seen containsObject:rule]) return NO;
        [seen addObject:rule];
    }
    return YES;
}
static NSString *const CloudCandidatesKey = @"MSIMEClientCloudCandidates";
static NSString *const CandidateTranslationsKey = @"MSIMEClientCandidateTranslations";
static NSString *const CandidateEnglishGlossKey = @"MSIMEClientCandidateEnglishGloss";
static NSString *const TranspositionKey = @"MSIMEClientAutocorrectTransposition";
static NSString *const NeighborKey = @"MSIMEClientAutocorrectNeighbor";
static NSString *const HelpcodeKey = @"MSIMEClientHelpcodeEnabled";
static NSString *const HelpcodeOptionsKey = @"MSIMEClientHelpcodeOptions";
static NSArray<NSString *> *HelpcodeSchemas() { return @[@"lantian", @"ziranma", @"shouyou2_0", @"shouyouplus", @"xiaohe", @"jiajia"]; }
static BOOL ValidHelpcodeOption(NSString *key, id value) {
    return [key isEqual:@"schema"] ? [HelpcodeSchemas() containsObject:value] :
        ([key isEqual:@"show_in_candidate_window"] && LocalModeBoolean(value));
}
static NSString *const QuanpinHelpcodeKey = @"MSIMEClientQuanpinHelpcodeEnabled";
static NSString *const ShuangpinHelpcodeKey = @"MSIMEClientShuangpinHelpcodeEnabled";
static NSString *const KeymapKey = @"MSIMEClientShuangpinKeymap";
static NSString *const WubiKey = @"MSIMEClientWubiAutoCommitUnique";
static NSString *const WubiMixedPinyinKey = @"MSIMEClientWubiMixedPinyin";
static NSString *const InputModeShortcutKey = @"MSIMEClientInputModeShortcut";
static NSString *const ShiftTapShortcutKey = @"MSIMEClientShiftTapShortcut";
static NSString *const ControlTapShortcutKey = @"MSIMEClientControlTapShortcut";
static NSString *const ControlOptionSpaceShortcutKey = @"MSIMEClientControlOptionSpaceShortcut";
static NSString *const CharacterSetShortcutKey = @"MSIMEClientCharacterSetShortcut";
static NSString *const FullWidthShortcutKey = @"MSIMEClientFullWidthShortcut";
static NSString *const FloatingToolbarKey = @"MSIMEClientFloatingToolbarEnabled";
static NSString *const FloatingToolbarOptionsKey = @"MSIMEClientFloatingToolbarOptions";
static NSArray<NSString *> *FloatingToolbarComponentKeys() {
    return @[@"english_mode", @"punctuation", @"fullwidth", @"character_set", @"emoji", @"handwriting",
             @"screen_keyboard", @"voice", @"settings"];
}
static BOOL ValidToolbarScale(id value) {
    return [value isKindOfClass:NSNumber.class] && CFGetTypeID((__bridge CFTypeRef)value) != CFBooleanGetTypeID() &&
           !CFNumberIsFloatType((__bridge CFNumberRef)value) && [@[@75, @100, @125, @150] containsObject:value];
}
static BOOL ValidToolbarFontSize(id value) {
    return [value isKindOfClass:NSNumber.class] && CFGetTypeID((__bridge CFTypeRef)value) != CFBooleanGetTypeID() &&
           !CFNumberIsFloatType((__bridge CFNumberRef)value) && [value integerValue] >= 16 && [value integerValue] <= 28;
}

// Layout primitives migrated from the upstream preferences window: MSIME-Apple develop
// cd36eba4d2572f747785450959332c7f68f4715c, platforms/macos/PreferencesWindowController.mm.
// A sidebar of grouped navigation buttons drives a page container; each page is a scroll view
// whose content is section labels above bordered cards of label/control rows. The page set, the
// cards, and which setting sits on which page are upstream's and stay that way.
//
// The metrics are not upstream's any more. Upstream sizes this window like a touch surface — 42pt
// sidebar rows at 16pt, 48pt preference rows at 15pt, a 24pt page title — which fits three cards
// on an 800pt-tall window and reads nothing like System Settings sitting next to it. The values
// below are the AppKit standards instead: 13pt body, 28pt sidebar rows, 30pt preference rows. The
// colours come from the system — controlAccentColor, windowBackgroundColor and the sidebar
// material — rather than the fixed sRGB greys and the one hard-coded purple upstream draws with,
// so the window follows the user's accent colour and both appearances on its own.
//
// The client README still pins b637828e for this window. That commit predates the sidebar — it
// had an NSToolbar — so it is not what ships today; the remote default branch is authoritative
// here, per AGENTS.md.

namespace {
using namespace msime::mac::layout;
/// The account page hosts a view owned by the Swift backend, so showing and leaving it has to
/// attach and detach that view. Its position in the page list was written out at both call sites.
constexpr NSInteger kAccountPageIndex = 8;
/// The 皮肤 page is the skin browser, so the native fallback for the shared skin route shows it.
constexpr NSInteger kSkinPageIndex = 2;
/// The voice form is also reachable from the input method's toolbar, so the page reloads on entry.
constexpr NSInteger kVoicePageIndex = 11;
/// 记住上次停留的页用的是页的名字而不是下标：侧栏顺序会随版本改，一个存下来的下标在下个版本里指向的
/// 是另一页，而名字要么认得要么认不得，认不得就回到第一页。
NSString *const LastSettingsPageKey = @"MSIMEClientSettingsLastPage";
}  // namespace

/// Scroll views lay an unflipped document view out from the bottom, which would park a short
/// page against the bottom edge instead of under the title.
@interface MSIMEPreferencesDocumentView : NSView
@end
@implementation MSIMEPreferencesDocumentView
- (BOOL)isFlipped { return YES; }
@end

/// One row of the sidebar source list: a group heading when it has children, one page when it does
/// not. The outline view holds these rather than the pages themselves, so that the order the sidebar
/// reads in and the order `_preferencePages` is built in stay independent of one another.
@interface MSIMESettingsSidebarItem : NSObject
@property(nonatomic, copy) NSString *title;
@property(nonatomic, copy) NSString *symbolName;
@property(nonatomic) NSInteger pageIndex;
@property(nonatomic, copy) NSArray<MSIMESettingsSidebarItem *> *children;
@end
@implementation MSIMESettingsSidebarItem
@end

/// The toolbar items this window owns. The toggle, the flexible space and the tracking separator
/// are the system's, so only the search field and the overflow menu need names of their own.
static NSToolbarItemIdentifier const MSIMESettingsSearchItemIdentifier = @"MSIMESettingsSearchItem";
static NSToolbarItemIdentifier const MSIMESettingsSeparatorItemIdentifier = @"MSIMESettingsSidebarSeparator";
static NSToolbarItemIdentifier const MSIMESettingsMoreItemIdentifier = @"MSIMESettingsMoreItem";

/// ⌘F reaches the search field from anywhere in the window, the way it does in Finder and in System
/// Settings. It used to be a `performKeyEquivalent:` override on the window's own content view,
/// which is a key equivalent no menu knows about: nothing discoverable said the window could be
/// searched, and the shortcut was invisible to anyone who had not read the source. The search field
/// lives in the toolbar now, so the shortcut belongs where every other Mac puts it.
static void MSIMEInstallFindSettingsMenuItem(id target, SEL action) {
    NSMenu *mainMenu = NSApp.mainMenu;
    if (mainMenu == nil) {
        mainMenu = [[NSMenu alloc] initWithTitle:@""];
        // AppKit draws the first submenu of the main menu as the application menu whatever its
        // title is, so 编辑 cannot be the first one: its items would come out under the app's name.
        NSMenuItem *application = [[NSMenuItem alloc] initWithTitle:@"" action:nil keyEquivalent:@""];
        application.submenu = [[NSMenu alloc] initWithTitle:NSProcessInfo.processInfo.processName];
        [mainMenu addItem:application];
        NSApp.mainMenu = mainMenu;
    }
    NSMenu *edit = nil;
    for (NSMenuItem *item in mainMenu.itemArray)
        if ([item.submenu.title isEqualToString:@"编辑"]) { edit = item.submenu; break; }
    if (edit == nil) {
        NSMenuItem *item = [[NSMenuItem alloc] initWithTitle:@"编辑" action:nil keyEquivalent:@""];
        item.submenu = [[NSMenu alloc] initWithTitle:@"编辑"];
        [mainMenu addItem:item];
        edit = item.submenu;
    }
    for (NSMenuItem *item in edit.itemArray)
        if (item.action == action) { item.target = target; return; }
    NSMenuItem *find = [[NSMenuItem alloc] initWithTitle:@"查找设置" action:action keyEquivalent:@"f"];
    find.keyEquivalentModifierMask = NSEventModifierFlagCommand;
    find.target = target;
    [edit addItem:find];
}

/// A scheme choice: the radio on the left, its scheme-specific popup trailing and disabled until
/// that scheme is the selected one.
static NSView *SchemeChoiceRow(NSButton *choice, NSView *accessory) {
    NSView *row = [[NSView alloc] initWithFrame:NSZeroRect];
    choice.translatesAutoresizingMaskIntoConstraints = NO;
    [row addSubview:choice];
    NSMutableArray<NSLayoutConstraint *> *constraints = [NSMutableArray arrayWithArray:@[
        [row.heightAnchor constraintEqualToConstant:kRowHeight],
        [choice.leadingAnchor constraintEqualToAnchor:row.leadingAnchor],
        [choice.centerYAnchor constraintEqualToAnchor:row.centerYAnchor],
    ]];
    if (accessory == nil) {
        [constraints addObject:[choice.trailingAnchor constraintLessThanOrEqualToAnchor:row.trailingAnchor]];
    } else {
        accessory.translatesAutoresizingMaskIntoConstraints = NO;
        [row addSubview:accessory];
        [constraints addObjectsFromArray:@[
            [choice.trailingAnchor constraintLessThanOrEqualToAnchor:accessory.leadingAnchor constant:-12.0],
            [accessory.trailingAnchor constraintEqualToAnchor:row.trailingAnchor],
            [accessory.centerYAnchor constraintEqualToAnchor:row.centerYAnchor],
            [accessory.widthAnchor constraintEqualToConstant:160.0],
        ]];
    }
    [NSLayoutConstraint activateConstraints:constraints];
    return row;
}

/// The summary is not drawn: upstream carries it as accessibility help so the page opens on its
/// first card rather than a paragraph.
static NSScrollView *PreferencesPage(NSString *title, NSString *summary, NSArray<NSView *> *content) {
    NSScrollView *page = [[NSScrollView alloc] initWithFrame:NSZeroRect];
    page.translatesAutoresizingMaskIntoConstraints = NO;
    page.hasVerticalScroller = YES;
    page.autohidesScrollers = YES;
    page.drawsBackground = NO;
    page.accessibilityLabel = title;
    page.accessibilityHelp = summary;
    NSTextField *titleLabel = [NSTextField labelWithString:title];
    titleLabel.font = [NSFont systemFontOfSize:20.0 weight:NSFontWeightSemibold];
    NSStackView *stack = [NSStackView stackViewWithViews:@[titleLabel]];
    stack.orientation = NSUserInterfaceLayoutOrientationVertical;
    stack.alignment = NSLayoutAttributeLeading;
    stack.distribution = NSStackViewDistributionFill;
    stack.spacing = 10.0;
    NSView *previous = nil;
    for (NSView *view in content) {
        [stack addArrangedSubview:view];
        [view.widthAnchor constraintEqualToAnchor:stack.widthAnchor].active = YES;
        // A section label introduces the card beneath it, so it sits close to that card and away
        // from whatever came before. One even spacing throughout makes the page a single
        // undifferentiated column, which is how upstream's 18pt everywhere reads.
        if (previous != nil && [view isKindOfClass:NSTextField.class])
            [stack setCustomSpacing:20.0 afterView:previous];
        previous = view;
    }
    [stack setCustomSpacing:20.0 afterView:titleLabel];
    stack.translatesAutoresizingMaskIntoConstraints = NO;
    NSView *document = [[MSIMEPreferencesDocumentView alloc] initWithFrame:NSZeroRect];
    document.translatesAutoresizingMaskIntoConstraints = NO;
    page.documentView = document;
    [document addSubview:stack];
    [NSLayoutConstraint activateConstraints:@[
        [document.widthAnchor constraintEqualToAnchor:page.contentView.widthAnchor],
        [document.heightAnchor constraintGreaterThanOrEqualToAnchor:page.contentView.heightAnchor],
        // The document opts out of autoresizing, so its origin needs pinning too: width and
        // height alone leave its position ambiguous.
        [document.leadingAnchor constraintEqualToAnchor:page.contentView.leadingAnchor],
        [document.topAnchor constraintEqualToAnchor:page.contentView.topAnchor],
        [stack.leadingAnchor constraintEqualToAnchor:document.leadingAnchor constant:kPageMargin],
        [stack.trailingAnchor constraintEqualToAnchor:document.trailingAnchor constant:-kPageMargin],
        // The page itself is pinned under the titlebar's safe area, so what is left here is the page
        // margin. The 46pt that used to sit here was the height of the traffic lights, measured by
        // hand; it survived the window growing a toolbar as a title laid out at y = -59.
        [stack.topAnchor constraintEqualToAnchor:document.topAnchor constant:kPageMargin],
        [stack.bottomAnchor constraintLessThanOrEqualToAnchor:document.bottomAnchor constant:-kPageMargin],
    ]];
    NSLayoutConstraint *height = [document.heightAnchor constraintEqualToAnchor:page.contentView.heightAnchor];
    height.priority = NSLayoutPriorityDefaultLow;
    height.active = YES;
    return page;
}

/// One searchable setting: the words a user would type, the page it sits on, and the row to scroll
/// to and flash once they pick it. Fourteen pages of a hundred-odd switches with no way to search
/// is the window's biggest usability gap; nothing else here changes how long it takes to find one.
@interface MSIMESettingsSearchEntry : NSObject
@property(nonatomic, copy) NSString *title;
@property(nonatomic) NSInteger pageIndex;
@property(nonatomic, weak) NSView *row;
@end
@implementation MSIMESettingsSearchEntry
@end

@interface MSIMEAppearancePreferences () <NSToolbarDelegate, NSOutlineViewDataSource, NSOutlineViewDelegate>
@end

@implementation MSIMEAppearancePreferences {
    NSUserDefaults *_defaults;
    NSArray<NSView *> *_preferencePages;
    NSArray<NSString *> *_pageTitles;
    NSArray<NSString *> *_pageIdentifiers;
    NSSplitViewController *_splitViewController;
    NSOutlineView *_sidebarOutline;
    NSScrollView *_sidebarScroll;
    NSArray<MSIMESettingsSidebarItem *> *_sidebarGroups;
    /// Selecting a row shows a page, and showing a page selects its row; without this the second
    /// half of that pair would answer the first.
    BOOL _updatingSidebarSelection;
    NSSearchToolbarItem *_searchToolbarItem;
    NSSearchField *_searchField;
    NSScrollView *_searchResultsScroll;
    NSStackView *_searchResultsStack;
    NSArray<MSIMESettingsSearchEntry *> *_searchIndex;
    NSBox *_shuangpinCard;
    NSBox *_wubiCard;
    NSInteger _selectedPageIndex;
    NSArray<NSButton *> *_schemeButtons;
    NSPopUpButton *_shuangpinSchemeButton;
    NSPopUpButton *_wubiSchemeButton;
    NSTextField *_versionLabel;
    NSTextField *_automaticUpdateLabel;
    NSButton *_updatePageButton;
    NSButton *_uninstallButton;
    NSButton *_removeUserDataButton;
    MSIMEUpdateController *_updateController;
    NSString *_sharedDefaultImeMode;
    NSString *_sharedImeModeScope;
    NSString *_activeModeApplication;
    BOOL _activeModeGlobal;
    NSMutableDictionary<NSString *, NSNumber *> *_applicationInputModes;
    NSNumber *_globalInputMode;
    // Per-app punctuation and width toggles. Like the reference's thread compartments they live only in memory, and a missing entry means the saved starting value.
    NSMutableDictionary<NSString *, NSNumber *> *_runtimeChinesePunctuation;
    NSMutableDictionary<NSString *, NSNumber *> *_runtimeFullWidthInput;
    NSPopUpButton *_defaultImeModeButton;
    NSPopUpButton *_imeModeScopeButton;
    NSNumber *_sharedToolbarEnabled;
    NSMutableDictionary *_sharedToolbarOptions;
    NSButton *_toolbarPunctuationButton;
    NSButton *_toolbarFullWidthButton;
    NSButton *_toolbarCharacterSetButton;
    NSButton *_toolbarEmojiButton;
    NSButton *_toolbarScreenKeyboardButton;
    NSButton *_toolbarSettingsButton;
    NSPopUpButton *_toolbarScaleButton;
    NSPopUpButton *_toolbarFontSizeButton;
    NSNumber *_sharedInputModeShortcut;
    NSNumber *_sharedShiftTapShortcut;
    NSNumber *_sharedControlTapShortcut;
    NSSwitch *_shiftTapShortcutToggle;
    NSSwitch *_controlTapShortcutToggle;
    NSNumber *_sharedControlOptionSpaceShortcut;
    NSSwitch *_controlOptionSpaceShortcutToggle;
    NSNumber *_sharedCharacterSetShortcut;
    NSNumber *_sharedFullWidthShortcut;
    NSSwitch *_characterSetShortcutToggle;
    NSMutableDictionary *_sharedHelpcodeOptions;
    NSMutableDictionary<NSString *, NSPopUpButton *> *_helpcodeSchemaButtons;
    NSMutableDictionary<NSString *, NSSwitch *> *_helpcodeDisplayToggles;
    NSNumber *_sharedChinesePunctuation;
    NSNumber *_sharedSmartPunctuation;
    NSNumber *_sharedSmartPunctuationRepeatToChinese;
    NSNumber *_sharedSmartPunctuationSpaceConvert;
    NSNumber *_sharedPairedPunctuation;
    NSString *_sharedPunctuationLock;
    NSSwitch *_pairedPunctuationToggle;
    NSPopUpButton *_punctuationLockButton;
    NSMutableDictionary *_sharedMixedInput;
    NSSwitch *_mixedEnglishToggle;
    NSPopUpButton *_mixedEnglishPrefixButton;
    NSSwitch *_mixedEmojiToggle;
    NSSwitch *_mixedKaomojiToggle;
    NSNumber *_sharedTraditionalOutput;
    NSNumber *_sharedFullWidthInput;
    NSNumber *_sharedAutocorrect;
    NSNumber *_sharedCloudCandidates;
    NSSwitch *_cloudCandidatesToggle;
    NSNumber *_sharedCandidateTranslations;
    NSSwitch *_candidateTranslationsToggle;
    NSNumber *_sharedCandidateEnglishGloss;
    NSSwitch *_candidateEnglishGlossToggle;
    id _sharedTransposition;
    id _sharedNeighbor;
    NSNumber *_sharedQuanpinHelpcode;
    NSNumber *_sharedShuangpinHelpcode;
    NSNumber *_sharedVertical;
    NSNumber *_sharedCandidateFollowCursor;
    NSNumber *_sharedInputModeHUD;
    NSNumber *_sharedFontSize;
    NSString *_sharedFontFamily;
    id _sharedCandidateEnglishFont;
    NSArray<NSString *> *_sharedFallbackFonts;
    id _sharedTextColor;
    id _sharedNumberColor;
    id _sharedAccentColor;
    id _sharedSelectedColor;
    id _sharedHoverColor;
    id _sharedSurfaceColor;
    id _sharedBorderColor;
    NSTextField *_textColorField;
    NSColorWell *_textColorWell;
    NSNumber *_sharedPreeditFontSize;
    NSString *_sharedCandidatePreedit;
    NSNumber *_sharedPageSize;
    NSString *_sharedTheme;
    NSString *_sharedCandidateTheme;
    NSMutableDictionary *_sharedNavigation;
    NSDictionary *_sharedWordCharacter;
    NSSwitch *_wordCharacterToggle;
    NSPopUpButton *_wordCharacterKeys;
    NSMutableArray<NSButton *> *_navigationButtons;
    NSString *_sharedInputScheme;
    NSString *_sharedShuangpinProfile;
    NSNumber *_sharedShuangpinPreeditUsesRaw;
    NSNumber *_sharedWubiMixedPinyin;
    NSString *_sharedInlinePreeditStyle;
    NSMutableDictionary *_sharedLocalModes;
    NSMutableArray<NSButton *> *_localModeButtons;
    NSPopUpButton *_layoutButton;
    NSPopUpButton *_profileButton;
    NSPopUpButton *_preeditButton;
    NSPopUpButton *_fontButton;
    NSComboBox *_englishFontFamilyControl;
    NSComboBox *_fontFamilyControl;
    NSPopUpButton *_fallbackList;
    NSComboBox *_fallbackFamilyControl;
    NSPopUpButton *_preeditFontButton;
    NSPopUpButton *_candidatePreeditButton;
    NSPopUpButton *_pageShortcutButton;
    NSPopUpButton *_pageSizeButton;
    NSURL *_skinsRoot;
    NSImage *_decorationImage;
    msime::mac::ResolvedSkin _lightSkin;
    msime::mac::ResolvedSkin _darkSkin;
    std::vector<msime::mac::SkinListEntry> _skins;
    MSIMECandidatePreviewView *_preview;
    NSButton *_themeButton;
    MetasequoiaSkinSettingsView *_skinSettingsView;
    NSView *_skinPageContainer;
    NSView<MSIMEVoiceSettingsForm> *_voiceSettingsView;
    NSButton *_skinPageSharedEntry;
    NSString *_translationPreferencesDirectory;
    MSIMETranslationSettingsWindow *_translationWindow;
    MSIMEAISettingsWindow *_aiWindow;
    MSIMEDictionaryWindowController *_dictionaryWindow;
    NSSwitch *_inputModeShortcutToggle;
    NSSwitch *_fullWidthToggle;
    NSSwitch *_keymapToggle;
    NSSwitch *_wubiToggle;
    NSSwitch *_punctuationToggle;
    NSSwitch *_smartPunctuationToggle;
    NSSwitch *_smartPunctuationRepeatToggle;
    NSSwitch *_toolbarToggle;
    NSSwitch *_transpositionToggle;
    NSSwitch *_neighborToggle;
    NSSwitch *_candidateFollowCursorToggle;
    NSSwitch *_candidateLearningToggle;
    NSPopUpButton *_frequencyModeButton;
    NSPopUpButton *_frequencyTriggerButton;
    NSPopUpButton *_frequencyStepButton;
    NSNumber *_sharedFuzzyPinyinEnabled;
    NSArray<NSString *> *_sharedFuzzyPinyinRules;
    NSNumber *_sharedCandidateLearning;
    NSString *_sharedFrequencyMode;
    NSNumber *_sharedFrequencyTriggerCount;
    NSNumber *_sharedFrequencyLinearStep;
    NSSwitch *_fuzzyPinyinToggle;
    NSMutableDictionary<NSString *, NSButton *> *_fuzzyPinyinRuleButtons;
    NSSwitch *_quanpinHelpcodeToggle;
    NSSwitch *_shuangpinHelpcodeToggle;
}
+ (instancetype)sharedPreferences {
    static MSIMEAppearancePreferences *preferences;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ preferences = [[self alloc] initWithDefaults:NSUserDefaults.standardUserDefaults]; });
    return preferences;
}
- (instancetype)initWithDefaults:(NSUserDefaults *)defaults {
    const auto root = msime::mac::DefaultSkinsRoot();
    return [self initWithDefaults:defaults skinsRoot:root.empty() ? nil : [NSURL fileURLWithPath:@(root.c_str()) isDirectory:YES]];
}
- (instancetype)initWithDefaults:(NSUserDefaults *)defaults skinsRoot:(NSURL *)root {
    self = [super initWithWindow:nil];
    if (self) {
        _defaults = defaults;
        _skinsRoot = [root copy];
        [self reloadSkins];
    }
    return self;
}
- (NSURL *)skinsRoot { return _skinsRoot; }
- (void)setTranslationPreferencesDirectory:(NSString *)directory {
    if ([_translationPreferencesDirectory isEqual:directory]) return;
    [_translationWindow close]; _translationWindow = nil;
    _translationPreferencesDirectory = [directory copy];
}
- (void)showTranslationSettings:(id)sender {
    __weak MSIMEAppearancePreferences *weakSelf = self;
    MSIMEOpenDesktopSettings(MSIMEDesktopSettingsPage::Translation, [self desktopSettingsWorkspace], ^{
        [weakSelf showNativeTranslationSettings:sender];
    });
}
- (NSWorkspace *)desktopSettingsWorkspace { return NSWorkspace.sharedWorkspace; }
- (void)showNativeTranslationSettings:(id)sender {
    if (!_translationWindow) {
        __weak MSIMEAppearancePreferences *weakSelf = self;
        _translationWindow = [[MSIMETranslationSettingsWindow alloc] initWithDirectory:_translationPreferencesDirectory saved:^(NSDictionary *preferences) {
            MSIMEAppearancePreferences *current = weakSelf;
            if (!current) return;
            [current applySharedInputPreferences:preferences];
            [[NSNotificationCenter defaultCenter] postNotificationName:MSIMETranslationPreferencesDidSaveNotification object:current userInfo:preferences];
        }];
    }
    [_translationWindow showWindow:sender];
}
- (void)showAISettings:(id)sender {
    __weak MSIMEAppearancePreferences *weakSelf = self;
    MSIMEOpenDesktopSettings(MSIMEDesktopSettingsPage::AI, [self desktopSettingsWorkspace], ^{
        [weakSelf showNativeAISettings:sender];
    });
}
- (void)showNativeAISettings:(id)sender {
    if (!_aiWindow) _aiWindow = [[MSIMEAISettingsWindow alloc] initWithDirectory:_translationPreferencesDirectory saved:^(NSDictionary *preferences) {
        [[NSNotificationCenter defaultCenter] postNotificationName:MSIMEAppearanceDidChangeNotification object:self userInfo:preferences];
    }];
    [_aiWindow showWindow:sender];
}
- (NSDictionary<NSString *, id> *)sharedPreferencesByMerging:(NSDictionary<NSString *, id> *)snapshot {
    if (![snapshot isKindOfClass:NSDictionary.class]) return nil;
    NSMutableDictionary *merged = [snapshot mutableCopy];
    if ([_defaults objectForKey:DefaultImeModeKey] != nil) merged[@"default_ime_mode"] = self.defaultImeMode;
    if ([_defaults objectForKey:ImeModeScopeKey] != nil) merged[@"ime_mode_scope"] = self.imeModeScope;
    // Apple exposes one switch for both a solitary Shift tap and Shift+Space.
    // Keep the legacy native keys independent when no shared snapshot exists,
    // but publish one shared value for both routes.
    if ([_defaults objectForKey:InputModeShortcutKey] != nil || [_defaults objectForKey:ShiftTapShortcutKey] != nil) {
        id existing = merged[@"keybindings"];
        NSMutableDictionary *keys = [existing isKindOfClass:NSDictionary.class] ? [existing mutableCopy] : [NSMutableDictionary dictionary];
        keys[@"switch_language_shift"] = @(([_defaults objectForKey:ShiftTapShortcutKey] != nil) ? self.shiftTapShortcut : self.inputModeShortcut);
        merged[@"keybindings"] = keys;
    }
    for (NSArray *entry in @[@[ControlTapShortcutKey, @"switch_language_ctrl", @(self.controlTapShortcut)]]) {
        if ([_defaults objectForKey:entry[0]] == nil) continue;
        id existing = merged[@"keybindings"];
        NSMutableDictionary *keys = [existing isKindOfClass:NSDictionary.class] ? [existing mutableCopy] : [NSMutableDictionary dictionary];
        keys[entry[1]] = entry[2];
        merged[@"keybindings"] = keys;
    }
    if ([_defaults objectForKey:ControlOptionSpaceShortcutKey] != nil) {
        id existing = merged[@"keybindings"];
        NSMutableDictionary *keys = [existing isKindOfClass:NSDictionary.class] ? [existing mutableCopy] : [NSMutableDictionary dictionary];
        keys[@"switch_language_ctrl_alt_space"] = @(self.controlOptionSpaceShortcut);
        merged[@"keybindings"] = keys;
    }
    if ([_defaults objectForKey:TraditionalKey] != nil)
        merged[@"traditional_chinese_output"] = @(self.traditionalOutput);
    merged[@"character_width"] = self.fullWidthInput ? @"fullwidth" : @"halfwidth";
    if ([_defaults objectForKey:CloudCandidatesKey] != nil)
        merged[@"cloud_candidates"] = @(self.cloudCandidates);
    if ([_defaults objectForKey:CandidateTranslationsKey] != nil)
        merged[@"candidate_translations"] = @(self.candidateTranslations);
    if ([_defaults objectForKey:CandidateEnglishGlossKey] != nil)
        merged[@"candidate_english_gloss"] = @(self.candidateEnglishGloss);
    if ([_defaults objectForKey:CharacterSetShortcutKey] != nil) {
        id existing = merged[@"keybindings"];
        NSMutableDictionary *keys = [existing isKindOfClass:NSDictionary.class] ? [existing mutableCopy] : [NSMutableDictionary dictionary];
        keys[@"toggle_character_set_ctrl_shift_f"] = @(self.characterSetShortcut);
        merged[@"keybindings"] = keys;
    }
    if ([_defaults objectForKey:FullWidthShortcutKey] != nil) {
        id existing = merged[@"keybindings"];
        NSMutableDictionary *keys = [existing isKindOfClass:NSDictionary.class] ? [existing mutableCopy] : [NSMutableDictionary dictionary];
        keys[@"toggle_fullwidth_option_shift_h"] = @(self.fullWidthShortcut);
        merged[@"keybindings"] = keys;
    }
    merged[@"candidate_layout"] = self.vertical ? @"vertical" : @"horizontal";
    merged[@"candidate_follow_cursor"] = @(self.candidateFollowCursor);
    merged[@"input_mode_hud"] = @(self.inputModeHUD);
    merged[@"scheme"] = self.inputScheme;
    // Leaving for Japanese has to leave a way back. `last_chinese_scheme` is what every other host
    // writes when the scheme changes - Fcitx5, IBus, iOS and HarmonyOS all do - and what the shared
    // settings page reads to put the user back on 五笔 rather than 全拼. This window sets the scheme
    // itself, Japanese included, so without this the field keeps whatever a different surface wrote
    // and the way back points at the wrong scheme.
    if (![self.inputScheme isEqual:@"japanese"]) merged[@"last_chinese_scheme"] = self.inputScheme;
    merged[@"shuangpin_profile"] = self.shuangpinProfile;
    merged[@"shuangpin_preedit_uses_raw"] = @(self.shuangpinPreeditUsesRaw);
    merged[@"wubi_mixed_pinyin"] = @(self.wubiMixedPinyinEnabled);
    NSMutableDictionary *qh = [merged[@"quanpin_helpcode"] mutableCopy] ?: [NSMutableDictionary dictionary];
    qh[@"enabled"] = @(self.quanpinHelpcodeEnabled);
    merged[@"quanpin_helpcode"] = qh;
    NSMutableDictionary *sh = [merged[@"shuangpin_helpcode"] mutableCopy] ?: [NSMutableDictionary dictionary];
    sh[@"enabled"] = @(self.shuangpinHelpcodeEnabled);
    merged[@"shuangpin_helpcode"] = sh;
    for (NSString *scheme in @[@"quanpin", @"shuangpin"]) {
        NSDictionary *stored = [_defaults dictionaryForKey:HelpcodeOptionsKey][scheme];
        if (![stored isKindOfClass:NSDictionary.class]) continue;
        NSMutableDictionary *target = merged[[scheme stringByAppendingString:@"_helpcode"]];
        NSDictionary *effective = [self helpcodeOptionsForScheme:scheme];
        for (NSString *key in @[@"schema", @"show_in_candidate_window"])
            if (ValidHelpcodeOption(key, stored[key])) target[key] = effective[key];
    }
    merged[@"candidate_page_size"] = @(self.pageSize);
    if ([_defaults dictionaryForKey:WordCharacterKey]) merged[@"word_character"] = [self wordCharacterOptions];
    NSDictionary *navigationOverrides = [_defaults dictionaryForKey:NavigationKey];
    if (navigationOverrides.count) {
        NSMutableDictionary *navigation = [merged[@"navigation"] mutableCopy] ?: [NSMutableDictionary dictionary];
        for (NSArray *entry in NavigationControls())
            if (LocalModeBoolean(navigationOverrides[entry[0]])) navigation[entry[0]] = @([self navigationEnabled:entry[0]]);
        merged[@"navigation"] = navigation;
    }
    merged[@"candidate_font_size"] = @(self.fontSize);
    if (_sharedFontFamily || [_defaults objectForKey:FontFamilyKey]) merged[@"candidate_font_family"] = self.fontFamily;
    if (_sharedCandidateEnglishFont || [_defaults objectForKey:CandidateEnglishFontKey])
        merged[@"candidate_english_font"] = self.candidateEnglishFont ?: (id)NSNull.null;
    if (_sharedTextColor || [_defaults objectForKey:TextColorKey]) merged[@"candidate_text_color"] = self.candidateTextColor ?: (id)NSNull.null;
    if (_sharedFallbackFonts || [_defaults objectForKey:FallbackFontsKey]) merged[@"candidate_fallback_fonts"] = self.fallbackFonts;
    if (_sharedPreeditFontSize || [_defaults objectForKey:PreeditFontKey]) merged[@"candidate_preedit_font_size"] = @(self.preeditFontSize);
    if (_sharedCandidatePreedit || [_defaults objectForKey:CandidatePreeditKey]) merged[@"candidate_preedit_style"] = self.showsCandidatePreedit ? @"pinyin" : @"empty";
    merged[@"chinese_punctuation"] = @(self.chinesePunctuation);
    merged[@"smart_punctuation"] = @(self.smartPunctuation);
    merged[@"smart_punctuation_repeat"] = @(self.smartPunctuationRepeatToChinese);
    merged[@"smart_punctuation_space_convert"] = @(self.smartPunctuationSpaceConvert);
    merged[@"paired_punctuation"] = @(self.pairedPunctuation);
    merged[@"punctuation_lock"] = self.punctuationLock;
    merged[@"mixed_input"] = @{
        @"english": @(self.mixedEnglishInput),
        @"minimum_prefix": @(self.mixedEnglishMinimumPrefix),
        @"emoji": @(self.mixedEmojiInput),
        @"kaomoji": @(self.mixedKaomojiInput)
    };
    merged[@"autocorrect"] = @(self.autocorrect);
    if ([_defaults objectForKey:CandidateLearningKey] != nil || _sharedCandidateLearning != nil)
        merged[@"learning"] = @(self.candidateLearningEnabled);
    if ([_defaults objectForKey:FrequencyModeKey] != nil || [_defaults objectForKey:FrequencyTriggerCountKey] != nil ||
        [_defaults objectForKey:FrequencyLinearStepKey] != nil || _sharedFrequencyMode != nil ||
        _sharedFrequencyTriggerCount != nil || _sharedFrequencyLinearStep != nil) {
        NSMutableDictionary *frequency = [merged[@"frequency"] mutableCopy] ?: [NSMutableDictionary dictionary];
        frequency[@"mode"] = self.frequencyAdjustmentMode;
        frequency[@"trigger_count"] = @(self.frequencyTriggerCount);
        frequency[@"linear_step"] = @(self.frequencyLinearStep);
        merged[@"frequency"] = frequency;
    }
    if ([_defaults objectForKey:FuzzyPinyinKey] != nil || [_defaults objectForKey:FuzzyPinyinRulesKey] != nil ||
        _sharedFuzzyPinyinEnabled != nil || _sharedFuzzyPinyinRules != nil) {
        NSMutableDictionary *fuzzy = [merged[@"fuzzy_pinyin"] mutableCopy] ?: [NSMutableDictionary dictionary];
        fuzzy[@"enabled"] = @(self.fuzzyPinyinEnabled);
        fuzzy[@"rules"] = [self fuzzyPinyinRules];
        merged[@"fuzzy_pinyin"] = fuzzy;
    }
    NSMutableDictionary *quanpin = [merged[@"quanpin"] mutableCopy] ?: [NSMutableDictionary dictionary];
    if (LocalModeBoolean([_defaults objectForKey:TranspositionKey]))
        quanpin[@"autocorrect_transposition"] = _sharedTransposition ?: @(self.autocorrectTransposition);
    if (LocalModeBoolean([_defaults objectForKey:NeighborKey]))
        quanpin[@"autocorrect_neighbor"] = _sharedNeighbor ?: @(self.autocorrectNeighbor);
    if (quanpin.count) merged[@"quanpin"] = quanpin;
    id existingVoice = merged[@"voice_input"];
    NSMutableDictionary *voice = [existingVoice isKindOfClass:NSDictionary.class]
        ? [existingVoice mutableCopy] : [NSMutableDictionary dictionary];
    [voice addEntriesFromDictionary:MSIMEVoicePreferencesFromDefaults(NSUserDefaults.standardUserDefaults)];
    merged[@"voice_input"] = voice;
    NSMutableDictionary *toolbar = [merged[@"floating_toolbar"] mutableCopy];
    if (!toolbar) toolbar = [NSMutableDictionary dictionary];
    id sharedEnglishMode = _sharedToolbarOptions[@"english_mode"];
    toolbar[@"english_mode"] = LocalModeBoolean(sharedEnglishMode) ? sharedEnglishMode : @YES;
    toolbar[@"enabled"] = @(self.floatingToolbarEnabled);
    toolbar[@"punctuation"] = @(self.floatingToolbarPunctuation);
    toolbar[@"fullwidth"] = @(self.floatingToolbarFullWidth);
    toolbar[@"character_set"] = @(self.floatingToolbarCharacterSet);
    toolbar[@"emoji"] = @(self.floatingToolbarEmoji);
    toolbar[@"handwriting"] = @(self.floatingToolbarHandwriting);
    toolbar[@"screen_keyboard"] = @(self.floatingToolbarScreenKeyboard);
    toolbar[@"voice"] = @(self.floatingToolbarVoice);
    toolbar[@"settings"] = @(self.floatingToolbarSettings);
    toolbar[@"scale_percent"] = @(self.floatingToolbarScalePercent);
    toolbar[@"font_size"] = @(self.floatingToolbarFontSize);
    merged[@"floating_toolbar"] = toolbar;
    NSDictionary *stored = [_defaults dictionaryForKey:LocalModesKey];
    NSMutableDictionary *modes = [merged[@"local_modes"] mutableCopy] ?: [NSMutableDictionary dictionary];
    for (NSArray *entry in LocalModeControls()) {
        NSString *mode = entry[0];
        if (LocalModeBoolean(stored[mode])) modes[mode] = @([self localModeEnabled:mode]);
    }
    if (modes.count) merged[@"local_modes"] = modes;
    return merged;
}
- (BOOL)localModeEnabled:(NSString *)mode {
    if (!KnownLocalMode(mode)) return NO;
    NSNumber *value = _sharedLocalModes[mode] ?: [_defaults dictionaryForKey:LocalModesKey][mode];
    return LocalModeBoolean(value) ? value.boolValue : YES;
}
- (void)setLocalMode:(NSString *)mode enabled:(BOOL)enabled {
    if (!KnownLocalMode(mode)) return;
    NSMutableDictionary *stored = [[_defaults dictionaryForKey:LocalModesKey] mutableCopy] ?: [NSMutableDictionary dictionary];
    stored[mode] = @(enabled);
    [_defaults setObject:stored forKey:LocalModesKey];
    if (!_sharedLocalModes) _sharedLocalModes = [NSMutableDictionary dictionary];
    _sharedLocalModes[mode] = @(enabled);
    [self preferencesChanged];
}
- (void)applySharedLocalModes:(NSDictionary *)modes {
    if (![modes isKindOfClass:NSDictionary.class]) return;
    if (!_sharedLocalModes) _sharedLocalModes = [NSMutableDictionary dictionary];
    for (NSArray *entry in LocalModeControls()) {
        id value = modes[entry[0]];
        if (LocalModeBoolean(value))
            _sharedLocalModes[entry[0]] = value;
    }
    for (NSButton *button in _localModeButtons)
        button.state = [self localModeEnabled:button.identifier] ? NSControlStateValueOn : NSControlStateValueOff;
}
- (void)localModeChanged:(NSButton *)sender {
    [self setLocalMode:sender.identifier enabled:sender.state == NSControlStateValueOn];
}
- (NSImage *)decorationImage { return _decorationImage; }
- (msime::mac::ResolvedSkin)resolvedSkinForDark:(BOOL)dark { return dark ? _darkSkin : _lightSkin; }
- (void)reloadSkins {
    const std::filesystem::path root = _skinsRoot.fileSystemRepresentation ?: "";
    _skins = msime::mac::ListSkins(root);
    [self resolveSelectedSkin];
    [self preferencesChanged];
}
- (BOOL)applyCloudSettingsSnapshot:(NSDictionary *)values {
    if (!MSIMEValidateCloudAppearance(values)) return NO;
    const BOOL punctuationBefore = self.chinesePunctuation, widthBefore = self.fullWidthInput;
    NSInteger preset = [values[@"platform.macos.candidate_page_shortcut"] integerValue];
    NSString *pagingKey = preset == 0 ? @"minus_equal" : preset == 1 ? @"brackets" : @"page_up_down";
    if ([[self wordCharacterOptions][@"enabled"] boolValue] && [[self wordCharacterOptions][@"keys"] isEqual:pagingKey]) return NO;
    if (!MSIMEApplyCloudAppearance(values, _defaults)) return NO;
    [self rememberActiveInputMode:[values[@"platform.macos.english_input_mode"] boolValue]];
    [self applyNavigationPreset:preset];
    // Invalidate only fields represented by the legacy platform cloud snapshot.
    // Newer family, color, preedit-size and per-scheme assistance choices survive.
    _sharedFontSize = nil;
    _sharedPageSize = nil;
    _sharedVertical = nil;
    _sharedInputScheme = nil;
    _sharedShuangpinPreeditUsesRaw = nil;
    _sharedChinesePunctuation = nil;
    _sharedSmartPunctuation = nil;
    _sharedSmartPunctuationRepeatToChinese = nil;
    _sharedSmartPunctuationSpaceConvert = nil;
    _sharedTraditionalOutput = nil;
    _sharedFullWidthInput = nil;
    _sharedAutocorrect = nil;
    _sharedToolbarEnabled = nil;
    _sharedCandidateLearning = nil;
    _sharedQuanpinHelpcode = nil;
    _sharedShuangpinHelpcode = nil;
    _sharedHelpcodeOptions = nil;
    _sharedLocalModes = nil;
    [self dropRuntimeOverridesUnlessPunctuation:punctuationBefore width:widthBefore];
    [self reloadSkins]; // Resolve the imported skin and publish one complete update.
    return YES;
}
- (NSDictionary *)cloudSettingsSnapshot {
    // Shared preferences can be effective without being mirrored into defaults.
    // Export the same values the native controls and host currently consume.
    NSMutableDictionary *snapshot = [MSIMECloudAppearanceSnapshot(_defaults) mutableCopy];
    snapshot[@"platform.macos.english_input_mode"] = @(self.englishMode);
    snapshot[@"platform.macos.candidate_font_size"] = @(self.fontSize);
    snapshot[@"platform.macos.candidate_page_size"] = @(self.pageSize);
    snapshot[@"platform.macos.candidate_panel_style"] = @(self.vertical ? 1 : 0);
    NSArray *schemes = @[@"quanpin", @"shuangpin", @"wubi"];
    NSUInteger schemeIndex = [schemes indexOfObject:self.inputScheme];
    // The fixed Apple cloud contract has no Japanese entry. Keep its
    // historical Chinese fallback instead of serializing NSNotFound when a
    // shared Tauri snapshot currently uses the Japanese Engine scheme.
    snapshot[@"platform.macos.input_scheme"] = @(schemeIndex == NSNotFound ? 0 : schemeIndex);
    snapshot[@"platform.macos.quanpin_helpcode_schema"] = @([MSIMECloudHelpcodeSchemas() indexOfObject:[self helpcodeOptionsForScheme:@"quanpin"][@"schema"]]);
    snapshot[@"platform.macos.shuangpin_helpcode_schema"] = @([MSIMECloudHelpcodeSchemas() indexOfObject:[self helpcodeOptionsForScheme:@"shuangpin"][@"schema"]]);
    BOOL allLocalModes = YES;
    for (NSString *mode in MSIMECloudLocalModeKeys()) allLocalModes = allLocalModes && [self localModeEnabled:mode];
    snapshot[@"platform.macos.local_input_modes"] = @(allLocalModes);
    snapshot[@"platform.macos.shuangpin_preedit_uses_raw"] = @(self.shuangpinPreeditUsesRaw);
    snapshot[@"platform.macos.chinese_punctuation"] = @(self.chinesePunctuation);
    snapshot[@"platform.macos.traditional_chinese_output"] = @(self.traditionalOutput);
    snapshot[@"platform.macos.autocorrect"] = @(self.autocorrect);
    snapshot[@"platform.macos.candidate_learning"] = @(self.candidateLearningEnabled);
    snapshot[@"platform.macos.floating_toolbar"] = @(self.floatingToolbarEnabled);
    return [snapshot copy];
}
- (void)resolveSelectedSkin {
    const std::filesystem::path root = _skinsRoot.fileSystemRepresentation ?: "";
    const std::string_view layout = self.vertical ? "vertical" : "horizontal";
    _lightSkin = msime::mac::ResolveSkin(self.skinID.UTF8String, false, root, layout, "light");
    _darkSkin = msime::mac::ResolveSkin(self.skinID.UTF8String, true, root, layout, "dark");
    _decorationImage = nil;
    if (_lightSkin.decorationTopDip > 0 && !_lightSkin.decorationPath.empty()) {
        _decorationImage = [[NSImage alloc] initWithContentsOfFile:@(_lightSkin.decorationPath.c_str())];
    }
    if (!_decorationImage && _darkSkin.decorationTopDip > 0 && !_darkSkin.decorationPath.empty()) {
        _decorationImage = [[NSImage alloc] initWithContentsOfFile:@(_darkSkin.decorationPath.c_str())];
    }
}
- (BOOL)vertical { return _sharedVertical ? _sharedVertical.boolValue : [_defaults integerForKey:LayoutKey] == 1; }
- (BOOL)candidateFollowCursor {
    if (_sharedCandidateFollowCursor) return _sharedCandidateFollowCursor.boolValue;
    return [_defaults objectForKey:CandidateFollowCursorKey] == nil ? YES : [_defaults boolForKey:CandidateFollowCursorKey];
}
- (void)setCandidateFollowCursor:(BOOL)value {
    _sharedCandidateFollowCursor = nil;
    [_defaults setBool:value forKey:CandidateFollowCursorKey];
    [self preferencesChanged];
}
- (BOOL)inputModeHUD {
    if (_sharedInputModeHUD) return _sharedInputModeHUD.boolValue;
    return [_defaults objectForKey:InputModeHUDKey] == nil ? YES : [_defaults boolForKey:InputModeHUDKey];
}
- (void)setInputModeHUD:(BOOL)value {
    _sharedInputModeHUD = nil;
    [_defaults setBool:value forKey:InputModeHUDKey];
    [self preferencesChanged];
}
- (BOOL)autocorrect { if (_sharedAutocorrect) return _sharedAutocorrect.boolValue; return [_defaults objectForKey:AutocorrectKey] == nil ? YES : [_defaults boolForKey:AutocorrectKey]; }
- (BOOL)candidateLearningEnabled {
    if (_sharedCandidateLearning) return _sharedCandidateLearning.boolValue;
    return [_defaults objectForKey:CandidateLearningKey] == nil ? YES : [_defaults boolForKey:CandidateLearningKey];
}
- (void)setCandidateLearningEnabled:(BOOL)value {
    _sharedCandidateLearning = nil;
    [_defaults setBool:value forKey:CandidateLearningKey];
    [self preferencesChanged];
}
- (NSString *)frequencyAdjustmentMode {
    id value = _sharedFrequencyMode ?: [_defaults objectForKey:FrequencyModeKey];
    return ValidFrequencyMode(value) ? value : @"promote";
}
- (void)setFrequencyAdjustmentMode:(NSString *)value {
    if (!ValidFrequencyMode(value)) value = @"promote";
    _sharedFrequencyMode = nil;
    [_defaults setObject:value forKey:FrequencyModeKey];
    [self preferencesChanged];
}
- (NSInteger)frequencyTriggerCount {
    id value = _sharedFrequencyTriggerCount ?: [_defaults objectForKey:FrequencyTriggerCountKey];
    return ValidFrequencyCount(value) ? [value integerValue] : 1;
}
- (void)setFrequencyTriggerCount:(NSInteger)value {
    if (value < 1 || value > 10) value = 1;
    _sharedFrequencyTriggerCount = nil;
    [_defaults setInteger:value forKey:FrequencyTriggerCountKey];
    [self preferencesChanged];
}
- (NSInteger)frequencyLinearStep {
    id value = _sharedFrequencyLinearStep ?: [_defaults objectForKey:FrequencyLinearStepKey];
    return ValidFrequencyCount(value) ? [value integerValue] : 1;
}
- (void)setFrequencyLinearStep:(NSInteger)value {
    if (value < 1 || value > 10) value = 1;
    _sharedFrequencyLinearStep = nil;
    [_defaults setInteger:value forKey:FrequencyLinearStepKey];
    [self preferencesChanged];
}
- (BOOL)fuzzyPinyinEnabled {
    if (_sharedFuzzyPinyinEnabled) return _sharedFuzzyPinyinEnabled.boolValue;
    return [_defaults objectForKey:FuzzyPinyinKey] == nil ? NO : [_defaults boolForKey:FuzzyPinyinKey];
}
- (NSArray<NSString *> *)fuzzyPinyinRules {
    id value = _sharedFuzzyPinyinRules ?: [_defaults objectForKey:FuzzyPinyinRulesKey];
    if (!ValidFuzzyPinyinRules(value)) return @[];
    NSSet *selected = [NSSet setWithArray:value];
    NSMutableArray *ordered = [NSMutableArray array];
    for (NSArray *entry in FuzzyPinyinRuleControls()) if ([selected containsObject:entry[0]]) [ordered addObject:entry[0]];
    return ordered;
}
- (BOOL)fuzzyPinyinRuleEnabled:(NSString *)rule { return [[self fuzzyPinyinRules] containsObject:rule]; }
- (void)setFuzzyPinyinEnabled:(BOOL)value {
    _sharedFuzzyPinyinEnabled = nil;
    [_defaults setBool:value forKey:FuzzyPinyinKey];
    // Match the shared PreferencesStore's first-enable behavior for the native
    // controls while retaining any explicitly pruned rule selection.
    if (value && [_defaults objectForKey:FuzzyPinyinRulesKey] == nil) {
        NSMutableArray *rules = [NSMutableArray array];
        for (NSArray *entry in FuzzyPinyinRuleControls()) [rules addObject:entry[0]];
        [_defaults setObject:rules forKey:FuzzyPinyinRulesKey];
    }
    [self preferencesChanged];
}
- (void)setFuzzyPinyinRule:(NSString *)rule enabled:(BOOL)enabled {
    if (![rule isKindOfClass:NSString.class] || !ValidFuzzyPinyinRules(@[rule])) return;
    NSMutableArray *rules = [[self fuzzyPinyinRules] mutableCopy];
    [rules removeObject:rule];
    if (enabled) [rules addObject:rule];
    _sharedFuzzyPinyinRules = nil;
    [_defaults setObject:rules forKey:FuzzyPinyinRulesKey];
    [self preferencesChanged];
}
- (void)fuzzyPinyinChanged:(NSSwitch *)sender {
    self.fuzzyPinyinEnabled = sender.state == NSControlStateValueOn;
    [self refreshControls];
}
- (void)fuzzyPinyinRuleChanged:(NSButton *)sender {
    [self setFuzzyPinyinRule:sender.identifier enabled:sender.state == NSControlStateValueOn];
}
- (BOOL)cloudCandidates { if (_sharedCloudCandidates) return _sharedCloudCandidates.boolValue; return [_defaults objectForKey:CloudCandidatesKey] == nil ? YES : [_defaults boolForKey:CloudCandidatesKey]; }
- (void)setCloudCandidates:(BOOL)value { _sharedCloudCandidates = nil; [_defaults setBool:value forKey:CloudCandidatesKey]; [self preferencesChanged]; }
- (BOOL)candidateTranslations { if (_sharedCandidateTranslations) return _sharedCandidateTranslations.boolValue; return [_defaults objectForKey:CandidateTranslationsKey] == nil ? YES : [_defaults boolForKey:CandidateTranslationsKey]; }
- (void)setCandidateTranslations:(BOOL)value { _sharedCandidateTranslations = nil; [_defaults setBool:value forKey:CandidateTranslationsKey]; [self preferencesChanged]; }
- (BOOL)candidateEnglishGloss { if (_sharedCandidateEnglishGloss) return _sharedCandidateEnglishGloss.boolValue; return [_defaults boolForKey:CandidateEnglishGlossKey]; }
- (void)setCandidateEnglishGloss:(BOOL)value { _sharedCandidateEnglishGloss = nil; [_defaults setBool:value forKey:CandidateEnglishGlossKey]; [self preferencesChanged]; }
- (void)setAutocorrect:(BOOL)value { _sharedAutocorrect = nil; [_defaults setBool:value forKey:AutocorrectKey]; [self preferencesChanged]; }
- (BOOL)autocorrectTransposition { id value = _sharedTransposition ?: [_defaults objectForKey:TranspositionKey]; return LocalModeBoolean(value) ? [value boolValue] : NO; }
- (BOOL)autocorrectNeighbor { id value = _sharedNeighbor ?: [_defaults objectForKey:NeighborKey]; return LocalModeBoolean(value) ? [value boolValue] : NO; }
- (void)setAutocorrectTransposition:(BOOL)value { _sharedTransposition = nil; [_defaults setBool:value forKey:TranspositionKey]; [self preferencesChanged]; }
- (void)setAutocorrectNeighbor:(BOOL)value { _sharedNeighbor = nil; [_defaults setBool:value forKey:NeighborKey]; [self preferencesChanged]; }
- (BOOL)helpcodeEnabled { return [_defaults objectForKey:HelpcodeKey] == nil ? YES : [_defaults boolForKey:HelpcodeKey]; }
- (void)setHelpcodeEnabled:(BOOL)value {
    _sharedQuanpinHelpcode = nil;
    _sharedShuangpinHelpcode = nil;
    [_defaults setBool:value forKey:HelpcodeKey];
    [_defaults setBool:value forKey:QuanpinHelpcodeKey];
    [_defaults setBool:value forKey:ShuangpinHelpcodeKey];
    [self preferencesChanged];
}
- (BOOL)quanpinHelpcodeEnabled { if (_sharedQuanpinHelpcode) return _sharedQuanpinHelpcode.boolValue; return [_defaults objectForKey:QuanpinHelpcodeKey] ? [_defaults boolForKey:QuanpinHelpcodeKey] : self.helpcodeEnabled; }
- (BOOL)shuangpinHelpcodeEnabled { if (_sharedShuangpinHelpcode) return _sharedShuangpinHelpcode.boolValue; return [_defaults objectForKey:ShuangpinHelpcodeKey] ? [_defaults boolForKey:ShuangpinHelpcodeKey] : self.helpcodeEnabled; }
- (void)setQuanpinHelpcodeEnabled:(BOOL)value { _sharedQuanpinHelpcode = nil; [_defaults setBool:value forKey:QuanpinHelpcodeKey]; [self preferencesChanged]; }
- (void)setShuangpinHelpcodeEnabled:(BOOL)value { _sharedShuangpinHelpcode = nil; [_defaults setBool:value forKey:ShuangpinHelpcodeKey]; [self preferencesChanged]; }
- (void)applySharedAssistancePreferences:(NSDictionary *)preferences {
    if (![preferences isKindOfClass:NSDictionary.class]) return;
    id autocorrect = preferences[@"autocorrect"];
    id learning = preferences[@"learning"];
    NSDictionary *frequency = preferences[@"frequency"];
    NSDictionary *fuzzy = preferences[@"fuzzy_pinyin"];
    id quanpin = preferences[@"quanpin_helpcode"];
    id shuangpin = preferences[@"shuangpin_helpcode"];
    if (LocalModeBoolean(autocorrect)) _sharedAutocorrect = autocorrect;
    if (LocalModeBoolean(learning)) _sharedCandidateLearning = learning;
    if ([frequency isKindOfClass:NSDictionary.class]) {
        if (ValidFrequencyMode(frequency[@"mode"])) _sharedFrequencyMode = [frequency[@"mode"] copy];
        if (ValidFrequencyCount(frequency[@"trigger_count"])) _sharedFrequencyTriggerCount = frequency[@"trigger_count"];
        if (ValidFrequencyCount(frequency[@"linear_step"])) _sharedFrequencyLinearStep = frequency[@"linear_step"];
    }
    if ([fuzzy isKindOfClass:NSDictionary.class]) {
        if (LocalModeBoolean(fuzzy[@"enabled"])) _sharedFuzzyPinyinEnabled = fuzzy[@"enabled"];
        if (ValidFuzzyPinyinRules(fuzzy[@"rules"])) _sharedFuzzyPinyinRules = [fuzzy[@"rules"] copy];
    }
    id correction = preferences[@"quanpin"];
    if (!correction && LocalModeBoolean(autocorrect)) correction = @{};
    if ([correction isKindOfClass:NSDictionary.class]) {
        id transposition = correction[@"autocorrect_transposition"];
        id neighbor = correction[@"autocorrect_neighbor"];
        // Missing optional fields inherit the legacy default, including when
        // a new shared snapshot removes a previously explicit override.
        if (!transposition || transposition == NSNull.null || LocalModeBoolean(transposition)) _sharedTransposition = transposition ?: NSNull.null;
        if (!neighbor || neighbor == NSNull.null || LocalModeBoolean(neighbor)) _sharedNeighbor = neighbor ?: NSNull.null;
    }
    if ([quanpin isKindOfClass:NSDictionary.class] && LocalModeBoolean(quanpin[@"enabled"])) _sharedQuanpinHelpcode = quanpin[@"enabled"];
    if ([shuangpin isKindOfClass:NSDictionary.class] && LocalModeBoolean(shuangpin[@"enabled"])) _sharedShuangpinHelpcode = shuangpin[@"enabled"];
    if (!_sharedHelpcodeOptions) _sharedHelpcodeOptions = [NSMutableDictionary dictionary];
    for (NSString *scheme in @[@"quanpin", @"shuangpin"]) {
        id shared = preferences[[scheme stringByAppendingString:@"_helpcode"]];
        if (![shared isKindOfClass:NSDictionary.class]) continue;
        NSMutableDictionary *values = [_sharedHelpcodeOptions[scheme] mutableCopy] ?: [NSMutableDictionary dictionary];
        for (NSString *key in @[@"schema", @"show_in_candidate_window"])
            if (ValidHelpcodeOption(key, shared[key])) values[key] = shared[key];
        _sharedHelpcodeOptions[scheme] = values;
    }
    [self refreshControls];
}
- (NSDictionary *)helpcodeOptionsForScheme:(NSString *)scheme {
    BOOL shuangpin = [scheme isEqualToString:@"shuangpin"];
    NSMutableDictionary *values = [@{@"schema": shuangpin ? @"lantian" : @"ziranma",
        @"show_in_candidate_window": @(shuangpin)} mutableCopy];
    id stored = [_defaults dictionaryForKey:HelpcodeOptionsKey][scheme];
    if ([stored isKindOfClass:NSDictionary.class])
        for (NSString *key in values.allKeys) if (ValidHelpcodeOption(key, stored[key])) values[key] = stored[key];
    [values addEntriesFromDictionary:_sharedHelpcodeOptions[scheme] ?: @{}];
    return values;
}
- (void)setHelpcodeOption:(NSString *)key value:(id)value scheme:(NSString *)scheme {
    if (![@[@"quanpin", @"shuangpin"] containsObject:scheme] || !ValidHelpcodeOption(key, value)) return;
    NSMutableDictionary *all = [[_defaults dictionaryForKey:HelpcodeOptionsKey] mutableCopy] ?: [NSMutableDictionary dictionary];
    id existing = all[scheme];
    NSMutableDictionary *values = [existing isKindOfClass:NSDictionary.class] ? [existing mutableCopy] : [NSMutableDictionary dictionary];
    values[key] = value;
    all[scheme] = values;
    [_defaults setObject:all forKey:HelpcodeOptionsKey];
    if (!_sharedHelpcodeOptions) _sharedHelpcodeOptions = [NSMutableDictionary dictionary];
    NSMutableDictionary *shared = [_sharedHelpcodeOptions[scheme] mutableCopy] ?: [NSMutableDictionary dictionary];
    shared[key] = value;
    _sharedHelpcodeOptions[scheme] = shared;
    [self preferencesChanged];
}
- (void)helpcodeSchemaChanged:(NSPopUpButton *)sender {
    [self setHelpcodeOption:@"schema" value:sender.selectedItem.representedObject scheme:sender.identifier];
}
- (void)helpcodeDisplayChanged:(NSSwitch *)sender {
    [self setHelpcodeOption:@"show_in_candidate_window" value:@(sender.state == NSControlStateValueOn) scheme:sender.identifier];
}
- (NSString *)inputScheme { NSString *value = _sharedInputScheme ?: [_defaults stringForKey:SchemeKey]; return [@[@"quanpin", @"shuangpin", @"wubi", @"japanese"] containsObject:value] ? value : @"quanpin"; }
- (void)setInputScheme:(NSString *)value { if (![@[@"quanpin", @"shuangpin", @"wubi", @"japanese"] containsObject:value]) value = @"quanpin"; _sharedInputScheme = nil; [_defaults setObject:value forKey:SchemeKey]; [self preferencesChanged]; }
- (NSString *)shuangpinProfile { NSString *value = _sharedShuangpinProfile ?: [_defaults stringForKey:ShuangpinProfileKey]; return [@[@"xiaohe", @"ziranma", @"shoudao", @"microsoft"] containsObject:value] ? value : @"xiaohe"; }
- (void)setShuangpinProfile:(NSString *)value { if (![@[@"xiaohe", @"ziranma", @"shoudao", @"microsoft"] containsObject:value]) value = @"xiaohe"; _sharedShuangpinProfile = nil; [_defaults setObject:value forKey:ShuangpinProfileKey]; [self preferencesChanged]; }
- (BOOL)shuangpinPreeditUsesRaw { if (_sharedShuangpinPreeditUsesRaw) return _sharedShuangpinPreeditUsesRaw.boolValue; return [_defaults objectForKey:ShuangpinPreeditKey] == nil ? YES : [_defaults boolForKey:ShuangpinPreeditKey]; }
- (void)setShuangpinPreeditUsesRaw:(BOOL)value { _sharedShuangpinPreeditUsesRaw = nil; [_defaults setBool:value forKey:ShuangpinPreeditKey]; [self preferencesChanged]; }
- (BOOL)wubiMixedPinyinEnabled {
    return _sharedWubiMixedPinyin ? _sharedWubiMixedPinyin.boolValue : [_defaults boolForKey:WubiMixedPinyinKey];
}
- (void)setWubiMixedPinyinEnabled:(BOOL)value {
    _sharedWubiMixedPinyin = nil;
    [_defaults setBool:value forKey:WubiMixedPinyinKey];
    [self preferencesChanged];
}
- (MSIMEInlinePreeditStyle)inlinePreeditStyle {
    NSString *value = _sharedInlinePreeditStyle ?: @"raw";
    if ([value isEqual:@"raw"]) return MSIMEInlinePreeditStyleRaw;
    if ([value isEqual:@"empty"]) return MSIMEInlinePreeditStyleEmpty;
    return MSIMEInlinePreeditStylePinyin;
}
- (void)applySharedInputPreferences:(NSDictionary *)preferences {
    if (![preferences isKindOfClass:NSDictionary.class]) return;
    const BOOL punctuationBefore = self.chinesePunctuation, widthBefore = self.fullWidthInput;
    id defaultMode = preferences[@"default_ime_mode"], scope = preferences[@"ime_mode_scope"];
    if ([@[@"chinese", @"english"] containsObject:defaultMode]) _sharedDefaultImeMode = defaultMode;
    if ([@[@"app", @"global"] containsObject:scope]) _sharedImeModeScope = scope;
    id keys = preferences[@"keybindings"];
    if ([keys isKindOfClass:NSDictionary.class]) {
        id shift = keys[@"switch_language_shift"];
        if (LocalModeBoolean(shift)) {
            // The shared Tauri setting reaches both native Shift routes.
            _sharedInputModeShortcut = shift;
            _sharedShiftTapShortcut = shift;
        }
        if (LocalModeBoolean(keys[@"switch_language_ctrl"])) _sharedControlTapShortcut = keys[@"switch_language_ctrl"];
        id inputMode = keys[@"switch_language_ctrl_alt_space"];
        if (LocalModeBoolean(inputMode)) _sharedControlOptionSpaceShortcut = inputMode;
        id enabled = keys[@"toggle_character_set_ctrl_shift_f"];
        if (LocalModeBoolean(enabled)) _sharedCharacterSetShortcut = enabled;
        id fullWidth = keys[@"toggle_fullwidth_option_shift_h"];
        if (LocalModeBoolean(fullWidth)) _sharedFullWidthShortcut = fullWidth;
    }
    id punctuation = preferences[@"chinese_punctuation"];
    if (LocalModeBoolean(punctuation)) _sharedChinesePunctuation = punctuation;
    id smart = preferences[@"smart_punctuation"];
    if (LocalModeBoolean(smart)) _sharedSmartPunctuation = smart;
    id smartRepeat = preferences[@"smart_punctuation_repeat"];
    if (LocalModeBoolean(smartRepeat)) _sharedSmartPunctuationRepeatToChinese = smartRepeat;
    id smartSpace = preferences[@"smart_punctuation_space_convert"];
    if (LocalModeBoolean(smartSpace)) _sharedSmartPunctuationSpaceConvert = smartSpace;
    id paired = preferences[@"paired_punctuation"];
    if (LocalModeBoolean(paired)) _sharedPairedPunctuation = paired;
    id punctuationLock = preferences[@"punctuation_lock"];
    if ([@[@"follow", @"chinese", @"english"] containsObject:punctuationLock]) _sharedPunctuationLock = [punctuationLock copy];
    id mixedInput = preferences[@"mixed_input"];
    if ([mixedInput isKindOfClass:NSDictionary.class]) {
        NSMutableDictionary *values = [_sharedMixedInput mutableCopy] ?: [NSMutableDictionary dictionary];
        if (LocalModeBoolean(mixedInput[@"english"])) values[@"english"] = mixedInput[@"english"];
        if (ValidMixedPrefix(mixedInput[@"minimum_prefix"])) values[@"minimum_prefix"] = mixedInput[@"minimum_prefix"];
        if (LocalModeBoolean(mixedInput[@"emoji"])) values[@"emoji"] = mixedInput[@"emoji"];
        if (LocalModeBoolean(mixedInput[@"kaomoji"])) values[@"kaomoji"] = mixedInput[@"kaomoji"];
        _sharedMixedInput = values;
    }
    id traditional = preferences[@"traditional_chinese_output"];
    if (LocalModeBoolean(traditional)) _sharedTraditionalOutput = traditional;
    id characterWidth = preferences[@"character_width"];
    if ([characterWidth isEqual:@"fullwidth"] || [characterWidth isEqual:@"halfwidth"])
        _sharedFullWidthInput = @([characterWidth isEqual:@"fullwidth"]);
    [self dropRuntimeOverridesUnlessPunctuation:punctuationBefore width:widthBefore];
    id cloud = preferences[@"cloud_candidates"];
    if (LocalModeBoolean(cloud)) _sharedCloudCandidates = cloud;
    id translations = preferences[@"candidate_translations"];
    if (LocalModeBoolean(translations)) _sharedCandidateTranslations = translations;
    id englishGloss = preferences[@"candidate_english_gloss"];
    if (LocalModeBoolean(englishGloss)) _sharedCandidateEnglishGloss = englishGloss;
    id scheme = preferences[@"scheme"];
    id profile = preferences[@"shuangpin_profile"];
    id raw = preferences[@"shuangpin_preedit_uses_raw"];
    id wubiMixedPinyin = preferences[@"wubi_mixed_pinyin"];
    if ([@[@"quanpin", @"shuangpin", @"wubi", @"japanese"] containsObject:scheme]) _sharedInputScheme = [scheme copy];
    if ([@[@"xiaohe", @"ziranma", @"shoudao", @"microsoft"] containsObject:profile]) _sharedShuangpinProfile = [profile copy];
    if (LocalModeBoolean(raw)) _sharedShuangpinPreeditUsesRaw = raw;
    if (LocalModeBoolean(wubiMixedPinyin)) _sharedWubiMixedPinyin = wubiMixedPinyin;
    id inlinePreedit = preferences[@"tsf_preedit_style"];
    if ([@[@"raw", @"pinyin", @"empty"] containsObject:inlinePreedit]) _sharedInlinePreeditStyle = [inlinePreedit copy];
    [self refreshControls];
}
- (NSString *)defaultImeMode {
    NSString *value = _sharedDefaultImeMode ?: [_defaults stringForKey:DefaultImeModeKey];
    return [value isEqual:@"english"] ? @"english" : @"chinese";
}
- (void)setDefaultImeMode:(NSString *)value {
    if (![@[@"chinese", @"english"] containsObject:value]) return;
    _sharedDefaultImeMode = nil;
    [_defaults setObject:value forKey:DefaultImeModeKey];
    [self preferencesChanged];
}
- (NSString *)imeModeScope {
    NSString *value = _sharedImeModeScope ?: [_defaults stringForKey:ImeModeScopeKey];
    return [value isEqual:@"global"] ? @"global" : @"app";
}
- (void)setImeModeScope:(NSString *)value {
    if (![@[@"app", @"global"] containsObject:value]) return;
    _sharedImeModeScope = nil;
    [_defaults setObject:value forKey:ImeModeScopeKey];
    [self preferencesChanged];
}
- (void)activateInputModeForApplication:(NSString *)identifier {
    _activeModeApplication = [identifier isKindOfClass:NSString.class] && identifier.length ? [identifier copy] : nil;
    // Scope changes take effect on activation, never in the middle of typing.
    _activeModeGlobal = [self.imeModeScope isEqual:@"global"];
}
- (BOOL)englishMode {
    if (!_activeModeApplication) return [_defaults boolForKey:EnglishKey];
    NSNumber *mode = _activeModeGlobal ? _globalInputMode : _applicationInputModes[_activeModeApplication];
    return mode ? mode.boolValue : [self.defaultImeMode isEqual:@"english"];
}
- (void)rememberActiveInputMode:(BOOL)english {
    if (!_activeModeApplication) return;
    if (_activeModeGlobal) _globalInputMode = @(english);
    else {
        if (!_applicationInputModes) _applicationInputModes = [NSMutableDictionary dictionary];
        _applicationInputModes[_activeModeApplication] = @(english);
    }
}
- (void)lockActiveInputMode { [self rememberActiveInputMode:self.englishMode]; }
// Punctuation and width toggles are always per app, whatever ime_mode_scope says: the reference keeps them in compartments of each UI thread. Without an active application they share one unnamed slot.
- (NSString *)runtimeInputStateKey { return _activeModeApplication ?: @""; }
- (BOOL)runtimeChinesePunctuation {
    NSNumber *value = _runtimeChinesePunctuation[[self runtimeInputStateKey]];
    return value ? value.boolValue : self.chinesePunctuation;
}
- (void)setRuntimeChinesePunctuation:(BOOL)value {
    if (!_runtimeChinesePunctuation) _runtimeChinesePunctuation = [NSMutableDictionary dictionary];
    _runtimeChinesePunctuation[[self runtimeInputStateKey]] = @(value);
}
- (BOOL)runtimeFullWidthInput {
    NSNumber *value = _runtimeFullWidthInput[[self runtimeInputStateKey]];
    return value ? value.boolValue : self.fullWidthInput;
}
- (void)setRuntimeFullWidthInput:(BOOL)value {
    if (!_runtimeFullWidthInput) _runtimeFullWidthInput = [NSMutableDictionary dictionary];
    _runtimeFullWidthInput[[self runtimeInputStateKey]] = @(value);
}
- (void)resetRuntimePunctuationForActiveApplication { [_runtimeChinesePunctuation removeObjectForKey:[self runtimeInputStateKey]]; }
- (void)resetRuntimeInputStateForActiveApplication {
    [self resetRuntimePunctuationForActiveApplication];
    [_runtimeFullWidthInput removeObjectForKey:[self runtimeInputStateKey]];
}
- (void)resetAllRuntimeInputState { _runtimeChinesePunctuation = nil; _runtimeFullWidthInput = nil; }
// A new saved starting value applies to every app at once, as re-activation does in the reference. An unchanged value keeps the toggles: the shared document is re-applied on every reload.
- (void)dropRuntimeOverridesUnlessPunctuation:(BOOL)punctuation width:(BOOL)width {
    if (self.chinesePunctuation != punctuation) _runtimeChinesePunctuation = nil;
    if (self.fullWidthInput != width) _runtimeFullWidthInput = nil;
}
// Switching to another input source ends the mode session in both scopes, as the source's TIP re-activation re-seeds default_ime_mode. The active application and scope stay, so the current activation keeps its scope.
- (void)resetRememberedInputModes {
    _globalInputMode = nil;
    [_applicationInputModes removeAllObjects];
}
- (BOOL)traditionalOutput { return _sharedTraditionalOutput ? _sharedTraditionalOutput.boolValue : [_defaults boolForKey:TraditionalKey]; }
- (BOOL)fullWidthInput { return _sharedFullWidthInput ? _sharedFullWidthInput.boolValue : [_defaults boolForKey:FullWidthKey]; }
- (BOOL)chinesePunctuation { if (_sharedChinesePunctuation) return _sharedChinesePunctuation.boolValue; return [_defaults objectForKey:ChinesePunctuationKey] == nil ? YES : [_defaults boolForKey:ChinesePunctuationKey]; }
- (BOOL)smartPunctuation { return _sharedSmartPunctuation ? _sharedSmartPunctuation.boolValue : ([_defaults objectForKey:SmartPunctuationKey] == nil ? NO : [_defaults boolForKey:SmartPunctuationKey]); }
- (void)setSmartPunctuation:(BOOL)value { _sharedSmartPunctuation = nil; [_defaults setBool:value forKey:SmartPunctuationKey]; [self preferencesChanged]; }
- (BOOL)smartPunctuationRepeatToChinese { return _sharedSmartPunctuationRepeatToChinese ? _sharedSmartPunctuationRepeatToChinese.boolValue : ([_defaults objectForKey:SmartPunctuationRepeatToChineseKey] == nil ? NO : [_defaults boolForKey:SmartPunctuationRepeatToChineseKey]); }
- (void)setSmartPunctuationRepeatToChinese:(BOOL)value { _sharedSmartPunctuationRepeatToChinese = nil; [_defaults setBool:value forKey:SmartPunctuationRepeatToChineseKey]; [self preferencesChanged]; }
// Off unless asked for, matching the Windows baseline and the shared default.
- (BOOL)smartPunctuationSpaceConvert { return _sharedSmartPunctuationSpaceConvert ? _sharedSmartPunctuationSpaceConvert.boolValue : [_defaults boolForKey:SmartPunctuationSpaceConvertKey]; }
- (void)setSmartPunctuationSpaceConvert:(BOOL)value { _sharedSmartPunctuationSpaceConvert = nil; [_defaults setBool:value forKey:SmartPunctuationSpaceConvertKey]; [self preferencesChanged]; }
- (BOOL)shuangpinKeymap { return [_defaults boolForKey:KeymapKey]; }
- (BOOL)wubiAutoCommitUnique { return [_defaults boolForKey:WubiKey]; }
- (BOOL)floatingToolbarEnabled { return _sharedToolbarEnabled ? _sharedToolbarEnabled.boolValue : ([_defaults objectForKey:FloatingToolbarKey] == nil ? YES : [_defaults boolForKey:FloatingToolbarKey]); }
- (void)setFloatingToolbarEnabled:(BOOL)value { _sharedToolbarEnabled = nil; [_defaults setBool:value forKey:FloatingToolbarKey]; [self preferencesChanged]; }
- (void)applySharedToolbarVisibility:(BOOL)enabled { _sharedToolbarEnabled = @(enabled); [self refreshControls]; }
- (NSDictionary *)floatingToolbarValues {
    NSDictionary *values = _sharedToolbarOptions ?: [_defaults dictionaryForKey:FloatingToolbarOptionsKey];
    return [values isKindOfClass:NSDictionary.class] ? values : @{};
}
- (BOOL)floatingToolbarBoolean:(NSString *)key defaultValue:(BOOL)defaultValue {
    id value = [self floatingToolbarValues][key];
    return LocalModeBoolean(value) ? [value boolValue] : defaultValue;
}
- (void)setFloatingToolbarBoolean:(NSString *)key value:(BOOL)value {
    NSMutableDictionary *values = [[_defaults dictionaryForKey:FloatingToolbarOptionsKey] mutableCopy] ?: [NSMutableDictionary dictionary];
    values[key] = @(value);
    _sharedToolbarOptions = nil;
    [_defaults setObject:values forKey:FloatingToolbarOptionsKey];
    [self preferencesChanged];
}
- (BOOL)floatingToolbarPunctuation { return [self floatingToolbarBoolean:@"punctuation" defaultValue:YES]; }
- (void)setFloatingToolbarPunctuation:(BOOL)value { [self setFloatingToolbarBoolean:@"punctuation" value:value]; }
- (BOOL)floatingToolbarFullWidth { return [self floatingToolbarBoolean:@"fullwidth" defaultValue:YES]; }
- (void)setFloatingToolbarFullWidth:(BOOL)value { [self setFloatingToolbarBoolean:@"fullwidth" value:value]; }
- (BOOL)floatingToolbarCharacterSet { return [self floatingToolbarBoolean:@"character_set" defaultValue:YES]; }
- (void)setFloatingToolbarCharacterSet:(BOOL)value { [self setFloatingToolbarBoolean:@"character_set" value:value]; }
- (BOOL)floatingToolbarEmoji { return [self floatingToolbarBoolean:@"emoji" defaultValue:YES]; }
- (void)setFloatingToolbarEmoji:(BOOL)value { [self setFloatingToolbarBoolean:@"emoji" value:value]; }
// The handwriting panel and voice buttons, which the reference's toolbar does not have. Both default
// on: they have been on the toolbar since it shipped, and a switch appearing must not remove them.
- (BOOL)floatingToolbarHandwriting { return [self floatingToolbarBoolean:@"handwriting" defaultValue:YES]; }
- (void)setFloatingToolbarHandwriting:(BOOL)value { [self setFloatingToolbarBoolean:@"handwriting" value:value]; }
- (BOOL)floatingToolbarVoice { return [self floatingToolbarBoolean:@"voice" defaultValue:YES]; }
- (void)setFloatingToolbarVoice:(BOOL)value { [self setFloatingToolbarBoolean:@"voice" value:value]; }
- (BOOL)floatingToolbarScreenKeyboard { return [self floatingToolbarBoolean:@"screen_keyboard" defaultValue:NO]; }
- (void)setFloatingToolbarScreenKeyboard:(BOOL)value { [self setFloatingToolbarBoolean:@"screen_keyboard" value:value]; }
- (BOOL)floatingToolbarSettings { return [self floatingToolbarBoolean:@"settings" defaultValue:YES]; }
- (void)setFloatingToolbarSettings:(BOOL)value { [self setFloatingToolbarBoolean:@"settings" value:value]; }
- (NSInteger)floatingToolbarScalePercent {
    id value = [self floatingToolbarValues][@"scale_percent"];
    return ValidToolbarScale(value) ? [value integerValue] : 100;
}
- (void)setFloatingToolbarScalePercent:(NSInteger)value {
    if (!ValidToolbarScale(@(value))) value = 100;
    NSMutableDictionary *values = [[_defaults dictionaryForKey:FloatingToolbarOptionsKey] mutableCopy] ?: [NSMutableDictionary dictionary];
    values[@"scale_percent"] = @(value); _sharedToolbarOptions = nil;
    [_defaults setObject:values forKey:FloatingToolbarOptionsKey]; [self preferencesChanged];
}
- (NSInteger)floatingToolbarFontSize {
    id value = [self floatingToolbarValues][@"font_size"];
    return ValidToolbarFontSize(value) ? [value integerValue] : 24;
}
- (void)setFloatingToolbarFontSize:(NSInteger)value {
    if (!ValidToolbarFontSize(@(value))) value = 24;
    NSMutableDictionary *values = [[_defaults dictionaryForKey:FloatingToolbarOptionsKey] mutableCopy] ?: [NSMutableDictionary dictionary];
    values[@"font_size"] = @(value); _sharedToolbarOptions = nil;
    [_defaults setObject:values forKey:FloatingToolbarOptionsKey]; [self preferencesChanged];
}
- (void)applySharedToolbarPreferences:(NSDictionary *)preferences {
    if (![preferences isKindOfClass:NSDictionary.class]) return;
    NSDictionary *toolbar = preferences[@"floating_toolbar"];
    if (![toolbar isKindOfClass:NSDictionary.class]) return;
    if (!_sharedToolbarOptions) _sharedToolbarOptions = [NSMutableDictionary dictionary];
    for (NSString *key in FloatingToolbarComponentKeys()) {
        id value = toolbar[key];
        if (LocalModeBoolean(value)) _sharedToolbarOptions[key] = value;
    }
    id scale = toolbar[@"scale_percent"];
    if (ValidToolbarScale(scale)) _sharedToolbarOptions[@"scale_percent"] = scale;
    id font = toolbar[@"font_size"];
    if (ValidToolbarFontSize(font)) _sharedToolbarOptions[@"font_size"] = font;
    [self refreshControls];
}
- (void)setWubiAutoCommitUnique:(BOOL)value { [_defaults setBool:value forKey:WubiKey]; [self preferencesChanged]; }
- (void)setShuangpinKeymap:(BOOL)value {
    [_defaults setBool:value forKey:KeymapKey];
    [self preferencesChanged];
}
- (void)setFullWidthInput:(BOOL)value {
    _sharedFullWidthInput = nil;
    _runtimeFullWidthInput = nil;
    [_defaults setBool:value forKey:FullWidthKey];
    [self preferencesChanged];
}
- (void)setChinesePunctuation:(BOOL)value {
    _sharedChinesePunctuation = nil;
    _runtimeChinesePunctuation = nil;
    [_defaults setBool:value forKey:ChinesePunctuationKey];
    [self preferencesChanged];
}
- (BOOL)pairedPunctuation {
    if (_sharedPairedPunctuation) return _sharedPairedPunctuation.boolValue;
    return [_defaults objectForKey:PairedPunctuationKey] == nil ? YES : [_defaults boolForKey:PairedPunctuationKey];
}
- (void)setPairedPunctuation:(BOOL)value {
    _sharedPairedPunctuation = nil;
    [_defaults setBool:value forKey:PairedPunctuationKey];
    [self preferencesChanged];
}
- (NSString *)punctuationLock {
    NSString *value = _sharedPunctuationLock ?: [_defaults stringForKey:PunctuationLockKey];
    return [@[@"follow", @"chinese", @"english"] containsObject:value] ? value : @"follow";
}
- (void)setPunctuationLock:(NSString *)value {
    if (![@[@"follow", @"chinese", @"english"] containsObject:value]) value = @"follow";
    _sharedPunctuationLock = nil;
    [_defaults setObject:value forKey:PunctuationLockKey];
    [self preferencesChanged];
}
- (NSDictionary *)mixedInputValues {
    NSDictionary *values = _sharedMixedInput ?: [_defaults dictionaryForKey:MixedInputKey];
    return [values isKindOfClass:NSDictionary.class] ? values : @{};
}
- (BOOL)mixedEnglishInput { id value = [self mixedInputValues][@"english"]; return LocalModeBoolean(value) ? [value boolValue] : YES; }
- (void)setMixedEnglishInput:(BOOL)value {
    NSMutableDictionary *values = [[_defaults dictionaryForKey:MixedInputKey] mutableCopy] ?: [NSMutableDictionary dictionary];
    values[@"english"] = @(value); _sharedMixedInput = nil; [_defaults setObject:values forKey:MixedInputKey]; [self preferencesChanged];
}
- (NSInteger)mixedEnglishMinimumPrefix { id value = [self mixedInputValues][@"minimum_prefix"]; return ValidMixedPrefix(value) ? [value integerValue] : 5; }
- (void)setMixedEnglishMinimumPrefix:(NSInteger)value {
    if (value < 1 || value > 8) value = 5;
    NSMutableDictionary *values = [[_defaults dictionaryForKey:MixedInputKey] mutableCopy] ?: [NSMutableDictionary dictionary];
    values[@"minimum_prefix"] = @(value); _sharedMixedInput = nil; [_defaults setObject:values forKey:MixedInputKey]; [self preferencesChanged];
}
// Falls back to on, matching `source_mixed_emoji_default` in client-core and the source's `emoji_mixed_input = true`.
- (BOOL)mixedEmojiInput { id value = [self mixedInputValues][@"emoji"]; return LocalModeBoolean(value) ? [value boolValue] : YES; }
- (void)setMixedEmojiInput:(BOOL)value {
    NSMutableDictionary *values = [[_defaults dictionaryForKey:MixedInputKey] mutableCopy] ?: [NSMutableDictionary dictionary];
    values[@"emoji"] = @(value); _sharedMixedInput = nil; [_defaults setObject:values forKey:MixedInputKey]; [self preferencesChanged];
}
- (BOOL)mixedKaomojiInput { id value = [self mixedInputValues][@"kaomoji"]; return LocalModeBoolean(value) ? [value boolValue] : NO; }
- (void)setMixedKaomojiInput:(BOOL)value {
    NSMutableDictionary *values = [[_defaults dictionaryForKey:MixedInputKey] mutableCopy] ?: [NSMutableDictionary dictionary];
    values[@"kaomoji"] = @(value); _sharedMixedInput = nil; [_defaults setObject:values forKey:MixedInputKey]; [self preferencesChanged];
}
- (void)setTraditionalOutput:(BOOL)value {
    _sharedTraditionalOutput = nil;
    [_defaults setBool:value forKey:TraditionalKey];
    [self preferencesChanged];
}
- (void)setEnglishMode:(BOOL)value {
    [self rememberActiveInputMode:value];
    [_defaults setBool:value forKey:EnglishKey];
    [self preferencesChanged];
}
- (BOOL)inputModeShortcut {
    if (_sharedInputModeShortcut) return _sharedInputModeShortcut.boolValue;
    return [_defaults objectForKey:InputModeShortcutKey] == nil || [_defaults boolForKey:InputModeShortcutKey];
}
- (BOOL)shiftTapShortcut {
    if (_sharedShiftTapShortcut) return _sharedShiftTapShortcut.boolValue;
    return [_defaults objectForKey:ShiftTapShortcutKey] == nil || [_defaults boolForKey:ShiftTapShortcutKey];
}
- (void)setShiftTapShortcut:(BOOL)value {
    _sharedInputModeShortcut = nil;
    _sharedShiftTapShortcut = nil;
    [_defaults setBool:value forKey:ShiftTapShortcutKey];
    [self preferencesChanged];
}
- (BOOL)controlTapShortcut {
    return _sharedControlTapShortcut ? _sharedControlTapShortcut.boolValue : [_defaults boolForKey:ControlTapShortcutKey];
}
- (void)setControlTapShortcut:(BOOL)value {
    _sharedControlTapShortcut = nil;
    [_defaults setBool:value forKey:ControlTapShortcutKey];
    [self preferencesChanged];
}
- (BOOL)controlOptionSpaceShortcut {
    if (_sharedControlOptionSpaceShortcut) return _sharedControlOptionSpaceShortcut.boolValue;
    return [_defaults objectForKey:ControlOptionSpaceShortcutKey] == nil || [_defaults boolForKey:ControlOptionSpaceShortcutKey];
}
- (void)setControlOptionSpaceShortcut:(BOOL)value {
    _sharedControlOptionSpaceShortcut = nil;
    [_defaults setBool:value forKey:ControlOptionSpaceShortcutKey];
    [self preferencesChanged];
}
- (BOOL)characterSetShortcut {
    if (_sharedCharacterSetShortcut) return _sharedCharacterSetShortcut.boolValue;
    return [_defaults objectForKey:CharacterSetShortcutKey] == nil || [_defaults boolForKey:CharacterSetShortcutKey];
}
- (void)setCharacterSetShortcut:(BOOL)value {
    _sharedCharacterSetShortcut = nil;
    [_defaults setBool:value forKey:CharacterSetShortcutKey];
    [self preferencesChanged];
}
- (BOOL)fullWidthShortcut {
    if (_sharedFullWidthShortcut) return _sharedFullWidthShortcut.boolValue;
    return [_defaults objectForKey:FullWidthShortcutKey] == nil || [_defaults boolForKey:FullWidthShortcutKey];
}
- (void)setFullWidthShortcut:(BOOL)value {
    _sharedFullWidthShortcut = nil;
    [_defaults setBool:value forKey:FullWidthShortcutKey];
    [self preferencesChanged];
}
- (void)setInputModeShortcut:(BOOL)value {
    _sharedInputModeShortcut = nil;
    _sharedShiftTapShortcut = nil;
    [_defaults setBool:value forKey:InputModeShortcutKey];
    [self preferencesChanged];
}
- (void)setVertical:(BOOL)value {
    _sharedVertical = nil;
    [_defaults setInteger:value ? 1 : 0 forKey:LayoutKey];
    [self preferencesChanged];
}
- (NSUInteger)fontSize {
    NSInteger size = _sharedFontSize ? _sharedFontSize.integerValue : [_defaults integerForKey:FontKey];
    return size >= 12 && size <= 32 ? size : 18;
}
- (NSString *)fontFamily {
    id value = _sharedFontFamily ?: [_defaults objectForKey:FontFamilyKey];
    return ValidFontFamily(value) ? value : @"Segoe UI";
}
- (NSString *)candidateEnglishFont {
    id value = _sharedCandidateEnglishFont ?: [_defaults objectForKey:CandidateEnglishFontKey];
    return ValidFontFamily(value) ? value : nil;
}
- (NSString *)candidateTextColor {
    id value = _sharedTextColor ?: [_defaults objectForKey:TextColorKey];
    return ValidTextColor(value) ? value : nil;
}
- (void)setCandidateTextColor:(NSString *)value {
    if (value && !ValidTextColor(value)) { NSBeep(); [self refreshControls]; return; }
    _sharedTextColor = nil;
    [_defaults setObject:value ?: @"" forKey:TextColorKey];
    [self preferencesChanged];
}
- (NSColor *)candidateTextColorWithDefault:(NSColor *)color {
    return CandidateColor(self.candidateTextColor, color);
}
- (NSColor *)candidateNumberColorWithDefault:(NSColor *)color {
    NSColor *text = CandidateColor(self.candidateTextColor, nil);
    return CandidateColor(_sharedNumberColor, text ? [text colorWithAlphaComponent:0x9d / 255.0] : color);
}
- (NSColor *)candidateAccentColorWithDefault:(NSColor *)color { return CandidateColor(_sharedAccentColor, color); }
- (NSColor *)candidateSelectedColorWithDefault:(NSColor *)color { return CandidateColor(_sharedSelectedColor, color); }
- (NSColor *)candidateHoverColorWithDefault:(NSColor *)color { return CandidateColor(_sharedHoverColor, color); }
- (NSColor *)candidateSurfaceColorWithDefault:(NSColor *)color { return CandidateColor(_sharedSurfaceColor, color); }
- (NSColor *)candidateBorderColorWithDefault:(NSColor *)color { return CandidateColor(_sharedBorderColor, color); }
- (void)setFontFamily:(NSString *)value {
    if (!ValidFontFamily(value)) { [self refreshControls]; return; }
    _sharedFontFamily = nil;
    [_defaults setObject:[value copy] forKey:FontFamilyKey];
    [self preferencesChanged];
}
- (void)setCandidateEnglishFont:(NSString *)value {
    if (value && !ValidFontFamily(value)) { [self refreshControls]; return; }
    _sharedCandidateEnglishFont = nil;
    // An empty marker lets the native fallback explicitly clear a previously
    // shared value without putting NSNull into NSUserDefaults.
    [_defaults setObject:value.length ? [value copy] : @"" forKey:CandidateEnglishFontKey];
    [self preferencesChanged];
}
- (NSFont *)candidateFontOfSize:(CGFloat)size {
    return [self candidateFontOfSize:size englishFirst:NO];
}
- (NSFont *)candidateFontOfSize:(CGFloat)size englishFirst:(BOOL)englishFirst {
    // Resolve a family without silently substituting a different installed family.
    // Preserve unavailable cross-platform names in preferences. Resolve installed
    // supplementary families in order, retaining system fallback at the end.
    NSMutableArray<NSFontDescriptor *> *resolved = [NSMutableArray array];
    NSMutableArray<NSString *> *families = [NSMutableArray array];
    if (englishFirst && self.candidateEnglishFont.length) [families addObject:self.candidateEnglishFont];
    [families addObject:self.fontFamily];
    [families addObjectsFromArray:self.fallbackFonts];
    for (NSString *family in families) {
        NSFontDescriptor *requested = [NSFontDescriptor fontDescriptorWithFontAttributes:@{NSFontFamilyAttribute:family}];
        NSFontDescriptor *matched = [requested matchingFontDescriptorWithMandatoryKeys:[NSSet setWithObject:NSFontFamilyAttribute]];
        if (matched) [resolved addObject:matched];
    }
    NSFont *system = [NSFont systemFontOfSize:size];
    if (!resolved.count) return system;
    NSFontDescriptor *primary = resolved.firstObject;
    [resolved removeObjectAtIndex:0];
    if (families.count > 1 || resolved.count) {
        [resolved addObject:system.fontDescriptor];
        primary = [primary fontDescriptorByAddingAttributes:@{NSFontCascadeListAttribute:resolved}];
    }
    return [NSFont fontWithDescriptor:primary size:size] ?: system;
}
- (NSArray<NSString *> *)fallbackFonts {
    id value = _sharedFallbackFonts ?: [_defaults objectForKey:FallbackFontsKey];
    return ValidFallbackFonts(value) ? value : @[];
}
- (void)setFallbackFonts:(NSArray<NSString *> *)value {
    if (!ValidFallbackFonts(value)) return;
    _sharedFallbackFonts = nil;
    [_defaults setObject:[[NSArray alloc] initWithArray:value copyItems:YES] forKey:FallbackFontsKey];
    [self preferencesChanged];
}
- (void)setFontSize:(NSUInteger)value {
    _sharedFontSize = nil;
    [_defaults setInteger:value >= 12 && value <= 32 ? value : 18 forKey:FontKey];
    [self preferencesChanged];
}
- (void)preferencesChanged {
    [self refreshControls];
    [[NSNotificationCenter defaultCenter] postNotificationName:MSIMEAppearanceDidChangeNotification object:self];
}
- (NSUInteger)preeditFontSize {
    NSInteger size = _sharedPreeditFontSize ? _sharedPreeditFontSize.integerValue : [_defaults integerForKey:PreeditFontKey];
    return size >= 12 && size <= 32 ? size : 16;
}
- (void)setPreeditFontSize:(NSUInteger)value {
    _sharedPreeditFontSize = nil;
    [_defaults setInteger:value >= 12 && value <= 32 ? value : 16 forKey:PreeditFontKey];
    [self preferencesChanged];
}
- (BOOL)showsCandidatePreedit {
    return ![(_sharedCandidatePreedit ?: [_defaults stringForKey:CandidatePreeditKey]) isEqual:@"empty"];
}
- (void)setShowsCandidatePreedit:(BOOL)value {
    _sharedCandidatePreedit = nil;
    [_defaults setObject:value ? @"pinyin" : @"empty" forKey:CandidatePreeditKey];
    [self preferencesChanged];
}
- (NSInteger)pageShortcut {
    NSInteger value = [_defaults integerForKey:PageShortcutKey];
    return value == 1 || value == 2 ? value : 0;
}
- (BOOL)navigationEnabled:(NSString *)key {
    id value = _sharedNavigation[key] ?: [_defaults dictionaryForKey:NavigationKey][key];
    if (LocalModeBoolean(value)) return [value boolValue];
    if ([key isEqual:@"minus_equal"]) return self.pageShortcut == 0;
    if ([key isEqual:@"brackets"]) return self.pageShortcut == 1;
    return [@[@"comma_period", @"tab", @"page_up_down", @"arrows"] containsObject:key];
}
- (NSDictionary *)wordCharacterOptions {
    NSDictionary *value = _sharedWordCharacter ?: [_defaults dictionaryForKey:WordCharacterKey];
    return LocalModeBoolean(value[@"enabled"]) && [@[@"brackets", @"minus_equal"] containsObject:value[@"keys"]] ? value : @{@"enabled": @YES, @"keys": @"brackets"};
}
- (void)setWordCharacterEnabled:(BOOL)enabled keys:(NSString *)keys {
    if (![@[@"brackets", @"minus_equal"] containsObject:keys]) return;
    if (enabled && [self navigationEnabled:keys]) { NSBeep(); [self refreshControls]; return; }
    _sharedWordCharacter = @{@"enabled": @(enabled), @"keys": keys};
    [_defaults setObject:_sharedWordCharacter forKey:WordCharacterKey];
    [self preferencesChanged];
}
- (void)setNavigation:(NSString *)key enabled:(BOOL)enabled {
    BOOL known = NO;
    for (NSArray *entry in NavigationControls()) if ([entry[0] isEqual:key]) known = YES;
    if (!known) return;
    if (enabled && [[self wordCharacterOptions][@"enabled"] boolValue] && [[self wordCharacterOptions][@"keys"] isEqual:key]) {
        NSBeep(); [self refreshControls]; return;
    }
    NSMutableDictionary *values = [[_defaults dictionaryForKey:NavigationKey] mutableCopy] ?: [NSMutableDictionary dictionary];
    values[key] = @(enabled);
    [_defaults setObject:values forKey:NavigationKey];
    if (!_sharedNavigation) _sharedNavigation = [NSMutableDictionary dictionary];
    _sharedNavigation[key] = @(enabled);
    [self preferencesChanged];
}
- (NSString *)skinID {
    NSString *value = [_defaults stringForKey:SkinKey];
    return @(msime::mac::NormalizeSkinId(value.UTF8String ?: "").c_str());
}
- (void)setSkinID:(NSString *)value {
    [_defaults setObject:@(msime::mac::NormalizeSkinId(value.UTF8String ?: "").c_str()) forKey:SkinKey];
    [self resolveSelectedSkin];
    [self preferencesChanged];
}
- (NSUInteger)pageSize {
    NSInteger value = _sharedPageSize ? _sharedPageSize.integerValue : [_defaults integerForKey:PageSizeKey];
    // Absent reads as zero, which is not a page size. That is the unset case, and it means the shared
    // default rather than the nearest legal number.
    if (value <= 0) return msime::mac::kDefaultCandidatePageSize;
    return msime::mac::NormalizeCandidatePageSize(static_cast<NSUInteger>(value));
}
- (void)setPageSize:(NSUInteger)value {
    _sharedPageSize = nil;
    [_defaults setInteger:msime::mac::NormalizeCandidatePageSize(value) forKey:PageSizeKey];
    [self preferencesChanged];
}
- (void)applySharedCandidatePreferences:(NSDictionary *)preferences {
    if (![preferences isKindOfClass:NSDictionary.class]) return;
    NSDictionary *navigation = preferences[@"navigation"];
    NSDictionary *wordCharacter = preferences[@"word_character"];
    if ([wordCharacter isKindOfClass:NSDictionary.class] && LocalModeBoolean(wordCharacter[@"enabled"]) &&
        [@[@"brackets", @"minus_equal"] containsObject:wordCharacter[@"keys"]]) _sharedWordCharacter = [wordCharacter copy];
    if ([navigation isKindOfClass:NSDictionary.class]) {
        if (!_sharedNavigation) _sharedNavigation = [NSMutableDictionary dictionary];
        for (NSArray *entry in NavigationControls())
            if (LocalModeBoolean(navigation[entry[0]])) _sharedNavigation[entry[0]] = navigation[entry[0]];
        // Windows names this shared switch candidate_arrow_navigation; accept
        // it at the Apple boundary while retaining navigation.arrows locally.
        if (navigation[@"candidate_arrow_navigation"] != nil)
            _sharedNavigation[@"arrows"] = @([navigation[@"candidate_arrow_navigation"] boolValue]);
    }
    id layout = preferences[@"candidate_layout"];
    if ([@[@"horizontal", @"vertical"] containsObject:layout]) _sharedVertical = @([layout isEqual:@"vertical"]);
    id followCursor = preferences[@"candidate_follow_cursor"];
    if (LocalModeBoolean(followCursor)) _sharedCandidateFollowCursor = followCursor;
    id inputModeHUD = preferences[@"input_mode_hud"];
    if (LocalModeBoolean(inputModeHUD)) _sharedInputModeHUD = inputModeHUD;
    id font = preferences[@"candidate_font_size"];
    id textColor = preferences[@"candidate_text_color"];
    // This optional shared field is omitted when None; omission also clears a
    // previously loaded explicit color, without persisting a local override.
    if (!textColor || textColor == NSNull.null) _sharedTextColor = NSNull.null;
    else if (ValidTextColor(textColor)) _sharedTextColor = [textColor copy];
    _sharedNumberColor = SharedCandidateColor(preferences, @"candidate_number_color", _sharedNumberColor);
    _sharedAccentColor = SharedCandidateColor(preferences, @"candidate_accent_color", _sharedAccentColor);
    _sharedSelectedColor = SharedCandidateColor(preferences, @"candidate_selected_color", _sharedSelectedColor);
    _sharedHoverColor = SharedCandidateColor(preferences, @"candidate_hover_color", _sharedHoverColor);
    _sharedSurfaceColor = SharedCandidateColor(preferences, @"candidate_surface_color", _sharedSurfaceColor);
    _sharedBorderColor = SharedCandidateColor(preferences, @"candidate_border_color", _sharedBorderColor);
    id family = preferences[@"candidate_font_family"];
    if (ValidFontFamily(family)) _sharedFontFamily = [family copy];
    id englishFamily = preferences[@"candidate_english_font"];
    if (!englishFamily) {
        // An omitted optional field clears a previously loaded shared value,
        // while leaving a legacy native-only value usable on first load.
        if (_sharedCandidateEnglishFont) _sharedCandidateEnglishFont = NSNull.null;
    } else if (englishFamily == NSNull.null) _sharedCandidateEnglishFont = NSNull.null;
    else if (ValidFontFamily(englishFamily)) _sharedCandidateEnglishFont = [englishFamily copy];
    id fallbacks = preferences[@"candidate_fallback_fonts"];
    if (ValidFallbackFonts(fallbacks)) _sharedFallbackFonts = [[NSArray alloc] initWithArray:fallbacks copyItems:YES];
    id preeditFont = preferences[@"candidate_preedit_font_size"];
    id preeditStyle = preferences[@"candidate_preedit_style"];
    if ([preeditFont isKindOfClass:NSNumber.class] && !LocalModeBoolean(preeditFont) && [preeditFont doubleValue] == [preeditFont integerValue] && [preeditFont integerValue] >= 12 && [preeditFont integerValue] <= 32) _sharedPreeditFontSize = preeditFont;
    if ([@[@"pinyin", @"empty"] containsObject:preeditStyle]) _sharedCandidatePreedit = preeditStyle;
    id page = preferences[@"candidate_page_size"];
    // Match the shared integer ranges; booleans and fractions are not sizes.
    if ([font isKindOfClass:NSNumber.class] && !LocalModeBoolean(font) && [font doubleValue] == [font integerValue] && [font integerValue] >= 12 && [font integerValue] <= 32) _sharedFontSize = font;
    if ([page isKindOfClass:NSNumber.class] && !LocalModeBoolean(page) && [page doubleValue] == [page integerValue] && [page integerValue] >= 1 && [page integerValue] <= 9)
        _sharedPageSize = @(msime::mac::NormalizeCandidatePageSize([page unsignedIntegerValue]));
    id theme = preferences[@"theme"];
    if ([@[@"dark", @"light", @"system"] containsObject:theme]) _sharedTheme = [theme copy];
    id candidateTheme = preferences[@"candidate_theme"];
    if ([@[@"follow", @"dark", @"light"] containsObject:candidateTheme]) _sharedCandidateTheme = [candidateTheme copy];
    [self refreshControls];
}

- (NSAppearance *)candidateAppearanceOverride {
    NSString *surface = _sharedCandidateTheme ?: @"follow";
    NSString *global = _sharedTheme ?: @"system";
    NSString *resolved = [surface isEqual:@"dark"] || [surface isEqual:@"light"] ? surface : global;
    if ([resolved isEqual:@"dark"]) return [NSAppearance appearanceNamed:NSAppearanceNameDarkAqua];
    if ([resolved isEqual:@"light"]) return [NSAppearance appearanceNamed:NSAppearanceNameAqua];
    return nil;
}
- (BOOL)candidateAppearanceOverrideConfigured {
    return _sharedTheme != nil || _sharedCandidateTheme != nil;
}
- (void)setPageShortcut:(NSInteger)value {
    value = value == 1 || value == 2 ? value : 0;
    NSString *enabledKey = value == 0 ? @"minus_equal" : value == 1 ? @"brackets" : @"page_up_down";
    if ([[self wordCharacterOptions][@"enabled"] boolValue] && [[self wordCharacterOptions][@"keys"] isEqual:enabledKey]) { NSBeep(); [self refreshControls]; return; }
    [self applyNavigationPreset:value];
    [_defaults setInteger:value forKey:PageShortcutKey];
    [self preferencesChanged];
}
- (void)applyNavigationPreset:(NSInteger)value {
    NSMutableDictionary *navigation = [[_defaults dictionaryForKey:NavigationKey] mutableCopy] ?: [NSMutableDictionary dictionary];
    navigation[@"minus_equal"] = @(value == 0);
    navigation[@"brackets"] = @(value == 1);
    navigation[@"page_up_down"] = @YES;
    [_defaults setObject:navigation forKey:NavigationKey];
    if (!_sharedNavigation) _sharedNavigation = [NSMutableDictionary dictionary];
    for (NSString *key in @[@"minus_equal", @"brackets", @"page_up_down"]) _sharedNavigation[key] = navigation[key];
}
- (void)refreshControls {
    [_defaultImeModeButton selectItemAtIndex:[self.defaultImeMode isEqual:@"english"] ? 1 : 0];
    [_imeModeScopeButton selectItemAtIndex:[self.imeModeScope isEqual:@"global"] ? 1 : 0];
    NSDictionary *wordCharacter = [self wordCharacterOptions];
    _wordCharacterToggle.state = [wordCharacter[@"enabled"] boolValue] ? NSControlStateValueOn : NSControlStateValueOff;
    [_wordCharacterKeys selectItemAtIndex:[wordCharacter[@"keys"] isEqual:@"minus_equal"] ? 1 : 0];
    for (NSButton *button in _navigationButtons)
        button.state = [self navigationEnabled:button.identifier] ? NSControlStateValueOn : NSControlStateValueOff;
    for (NSString *scheme in _helpcodeSchemaButtons) {
        NSDictionary *values = [self helpcodeOptionsForScheme:scheme];
        [_helpcodeSchemaButtons[scheme] selectItemAtIndex:[HelpcodeSchemas() indexOfObject:values[@"schema"]]];
        _helpcodeDisplayToggles[scheme].state = [values[@"show_in_candidate_window"] boolValue] ? NSControlStateValueOn : NSControlStateValueOff;
    }
    _fullWidthToggle.state = self.fullWidthInput ? NSControlStateValueOn : NSControlStateValueOff;
    _keymapToggle.state = self.shuangpinKeymap ? NSControlStateValueOn : NSControlStateValueOff;
    _wubiToggle.state = self.wubiAutoCommitUnique ? NSControlStateValueOn : NSControlStateValueOff;
    _punctuationToggle.state = self.chinesePunctuation ? NSControlStateValueOn : NSControlStateValueOff;
    _smartPunctuationToggle.state = self.smartPunctuation ? NSControlStateValueOn : NSControlStateValueOff;
    _smartPunctuationRepeatToggle.state = self.smartPunctuationRepeatToChinese ? NSControlStateValueOn : NSControlStateValueOff;
    _pairedPunctuationToggle.state = self.pairedPunctuation ? NSControlStateValueOn : NSControlStateValueOff;
    NSDictionary *punctuationLockIndexes = @{@"follow": @0, @"chinese": @1, @"english": @2};
    [_punctuationLockButton selectItemAtIndex:[punctuationLockIndexes[self.punctuationLock] integerValue]];
    _mixedEnglishToggle.state = self.mixedEnglishInput ? NSControlStateValueOn : NSControlStateValueOff;
    _mixedEnglishPrefixButton.enabled = self.mixedEnglishInput;
    [_mixedEnglishPrefixButton selectItemAtIndex:self.mixedEnglishMinimumPrefix - 1];
    _mixedEmojiToggle.state = self.mixedEmojiInput ? NSControlStateValueOn : NSControlStateValueOff;
    _mixedKaomojiToggle.state = self.mixedKaomojiInput ? NSControlStateValueOn : NSControlStateValueOff;
    _toolbarToggle.state = self.floatingToolbarEnabled ? NSControlStateValueOn : NSControlStateValueOff;
    _toolbarPunctuationButton.state = self.floatingToolbarPunctuation ? NSControlStateValueOn : NSControlStateValueOff;
    _toolbarFullWidthButton.state = self.floatingToolbarFullWidth ? NSControlStateValueOn : NSControlStateValueOff;
    _toolbarCharacterSetButton.state = self.floatingToolbarCharacterSet ? NSControlStateValueOn : NSControlStateValueOff;
    _toolbarEmojiButton.state = self.floatingToolbarEmoji ? NSControlStateValueOn : NSControlStateValueOff;
    _toolbarScreenKeyboardButton.state = self.floatingToolbarScreenKeyboard ? NSControlStateValueOn : NSControlStateValueOff;
    _toolbarSettingsButton.state = self.floatingToolbarSettings ? NSControlStateValueOn : NSControlStateValueOff;
    [_toolbarScaleButton selectItemAtIndex:[@[@75, @100, @125, @150] indexOfObject:@(self.floatingToolbarScalePercent)]];
    [_toolbarFontSizeButton selectItemAtIndex:self.floatingToolbarFontSize - 16];
    _transpositionToggle.state = self.autocorrectTransposition ? NSControlStateValueOn : NSControlStateValueOff;
    _neighborToggle.state = self.autocorrectNeighbor ? NSControlStateValueOn : NSControlStateValueOff;
    _candidateFollowCursorToggle.state = self.candidateFollowCursor ? NSControlStateValueOn : NSControlStateValueOff;
    _candidateLearningToggle.state = self.candidateLearningEnabled ? NSControlStateValueOn : NSControlStateValueOff;
    [_frequencyModeButton selectItemAtIndex:[FrequencyModes() indexOfObject:self.frequencyAdjustmentMode]];
    [_frequencyTriggerButton selectItemAtIndex:self.frequencyTriggerCount - 1];
    [_frequencyStepButton selectItemAtIndex:self.frequencyLinearStep - 1];
    _fuzzyPinyinToggle.state = self.fuzzyPinyinEnabled ? NSControlStateValueOn : NSControlStateValueOff;
    for (NSString *rule in _fuzzyPinyinRuleButtons) {
        NSButton *button = _fuzzyPinyinRuleButtons[rule];
        button.state = [self fuzzyPinyinRuleEnabled:rule] ? NSControlStateValueOn : NSControlStateValueOff;
        button.enabled = self.fuzzyPinyinEnabled;
    }
    _cloudCandidatesToggle.state = self.cloudCandidates ? NSControlStateValueOn : NSControlStateValueOff;
    _candidateTranslationsToggle.state = self.candidateTranslations ? NSControlStateValueOn : NSControlStateValueOff;
    _candidateEnglishGlossToggle.state = self.candidateEnglishGloss ? NSControlStateValueOn : NSControlStateValueOff;
    _quanpinHelpcodeToggle.state = self.quanpinHelpcodeEnabled ? NSControlStateValueOn : NSControlStateValueOff;
    _shuangpinHelpcodeToggle.state = self.shuangpinHelpcodeEnabled ? NSControlStateValueOn : NSControlStateValueOff;
    for (NSButton *button in _localModeButtons)
        button.state = [self localModeEnabled:button.identifier] ? NSControlStateValueOn : NSControlStateValueOff;
    _inputModeShortcutToggle.state = self.inputModeShortcut ? NSControlStateValueOn : NSControlStateValueOff;
    _shiftTapShortcutToggle.state = self.shiftTapShortcut ? NSControlStateValueOn : NSControlStateValueOff;
    _controlTapShortcutToggle.state = self.controlTapShortcut ? NSControlStateValueOn : NSControlStateValueOff;
    _controlOptionSpaceShortcutToggle.state = self.controlOptionSpaceShortcut ? NSControlStateValueOn : NSControlStateValueOff;
    _characterSetShortcutToggle.state = self.characterSetShortcut ? NSControlStateValueOn : NSControlStateValueOff;
    [_layoutButton selectItemAtIndex:self.vertical ? 1 : 0];
    NSDictionary *schemeIndexes = @{@"quanpin": @0, @"shuangpin": @1, @"wubi": @2, @"japanese": @3};
    const NSInteger storedScheme = [schemeIndexes[self.inputScheme] integerValue];
    // The radios and the scheme popups mirror the same stored value: only the selected scheme's
    // popup is usable, so a disabled row cannot look like it is configuring the active scheme.
    for (NSInteger index = 0; index < (NSInteger)_schemeButtons.count; ++index)
        _schemeButtons[index].state = index == storedScheme ? NSControlStateValueOn : NSControlStateValueOff;
    _shuangpinSchemeButton.enabled = storedScheme == 1;
    _wubiSchemeButton.enabled = storedScheme == 2;
    // Options that only apply to one scheme are shown only while it is selected. Leaving them
    // editable under another scheme means the change saves, the page says nothing, and the setting
    // does nothing until the user happens to switch back.
    _shuangpinCard.hidden = storedScheme != 1;
    _wubiCard.hidden = storedScheme != 2;
    NSDictionary *profileIndexes = @{@"xiaohe": @0, @"ziranma": @1, @"shoudao": @2, @"microsoft": @3};
    [_profileButton selectItemAtIndex:[profileIndexes[self.shuangpinProfile] integerValue]];
    [_preeditButton selectItemAtIndex:self.shuangpinPreeditUsesRaw ? 1 : 0];
    [_fontButton selectItemAtIndex:self.fontSize - 12];
    _englishFontFamilyControl.stringValue = self.candidateEnglishFont ?: @"";
    _fontFamilyControl.stringValue = self.fontFamily;
    _textColorField.stringValue = self.candidateTextColor ?: @"";
    _textColorWell.color = [self candidateTextColorWithDefault:NSColor.labelColor];
    NSInteger fallbackIndex = MAX(0, _fallbackList.indexOfSelectedItem);
    [_fallbackList removeAllItems];
    for (NSString *family in self.fallbackFonts)
        [_fallbackList.menu addItem:[[NSMenuItem alloc] initWithTitle:family action:nil keyEquivalent:@""]];
    if (_fallbackList.numberOfItems) [_fallbackList selectItemAtIndex:MIN(fallbackIndex, _fallbackList.numberOfItems - 1)];
    [_preeditFontButton selectItemAtIndex:self.preeditFontSize - 12];
    [_candidatePreeditButton selectItemAtIndex:self.showsCandidatePreedit ? 0 : 1];
    [_pageShortcutButton selectItemAtIndex:self.pageShortcut];
    [_pageSizeButton selectItemAtIndex:msime::mac::CandidatePageSizeOptionIndex(self.pageSize)];
    [_preview updatePanelStyle:self.vertical ? 1 : 0 pageSize:self.pageSize fontSize:self.fontSize];
}
- (NSWindow *)window {
    NSWindow *window = [super window];
    if (!window) {
        [self loadWindow];
        window = [super window];
    }
    return window;
}
- (void)loadWindow {
    NSWindow *window = [[NSWindow alloc] initWithContentRect:NSMakeRect(0, 0, 840, 620)
                                                   styleMask:NSWindowStyleMaskTitled | NSWindowStyleMaskClosable |
                                                             NSWindowStyleMaskMiniaturizable | NSWindowStyleMaskResizable |
                                                             NSWindowStyleMaskFullSizeContentView
                                                     backing:NSBackingStoreBuffered
                                                       defer:NO];
    window.title = @"水杉输入法设置";
    // A window the user is expected to come back to, at the size and place they left it. The
    // identifier is what makes restorable more than a flag: AppKit keys a window's saved state by
    // it, and a window without one is encoded into the saved-state bundle and then cannot be found
    // again.
    window.restorable = YES;
    window.identifier = MSIMESettingsWindowFrameAutosaveName();
    // The unified toolbar is where the title goes now, and it says which page is in front of the
    // user — the first thing in this window's chrome that ever did. A transparent titlebar was what
    // the hand-pinned sidebar needed to run full height behind it; the split view's sidebar item
    // does that itself, and asking for both leaves the toolbar drawing on nothing.
    window.titleVisibility = NSWindowTitleVisible;
    // 800 rather than 760: the sidebar can be dragged to kSidebarMaxWidth, and what is left after
    // it and the two page margins has to stay above kContentColumnMin.
    window.contentMinSize = NSMakeSize(800, 520);
    window.releasedWhenClosed = NO;
    _layoutButton = [[NSPopUpButton alloc] initWithFrame:NSZeroRect pullsDown:NO];
    [_layoutButton addItemsWithTitles:@[@"横向排列", @"纵向列表"]];
    _layoutButton.accessibilityLabel = @"候选排列";
    _layoutButton.target = self;
    _layoutButton.action = @selector(layoutChanged:);
    _candidateFollowCursorToggle = MSIMESettingSwitch(self, @selector(candidateFollowCursorChanged:), @"候选窗口跟随光标");
    _profileButton = [[NSPopUpButton alloc] initWithFrame:NSZeroRect pullsDown:NO];
    for (const char *identifier : msime::mac::kShuangpinSchemaIdentifiers)
        [_profileButton addItemWithTitle:[NSString stringWithUTF8String:msime::mac::ShuangpinSchemaTitle(identifier)]];
    _profileButton.target = self;
    _profileButton.action = @selector(profileChanged:);
    _preeditButton = [[NSPopUpButton alloc] initWithFrame:NSZeroRect pullsDown:NO];
    [_preeditButton addItemsWithTitles:@[@"全拼显示", @"原始双拼显示"]];
    _preeditButton.target = self;
    _preeditButton.action = @selector(preeditChanged:);
    _fontButton = [[NSPopUpButton alloc] initWithFrame:NSZeroRect pullsDown:NO];
    for (NSUInteger size = 12; size <= 32; ++size)
        [_fontButton addItemWithTitle:[NSString stringWithFormat:@"%lu pt", (unsigned long)size]];
    _fontButton.accessibilityLabel = @"候选字号";
    _fontButton.target = self;
    _fontButton.action = @selector(fontChanged:);
    _englishFontFamilyControl = [[NSComboBox alloc] initWithFrame:NSZeroRect];
    [_englishFontFamilyControl addItemsWithObjectValues:[NSFontManager.sharedFontManager.availableFontFamilies sortedArrayUsingSelector:@selector(localizedCaseInsensitiveCompare:)]];
    _englishFontFamilyControl.completes = YES;
    _englishFontFamilyControl.accessibilityLabel = @"候选窗英文字体";
    _englishFontFamilyControl.toolTip = @"优先用于拉丁字符；未安装时回退到候选主字体和补充字体；留空表示不设置独立英文字体";
    _englishFontFamilyControl.target = self;
    _englishFontFamilyControl.action = @selector(englishFontFamilyChanged:);
    _fontFamilyControl = [[NSComboBox alloc] initWithFrame:NSZeroRect];
    [_fontFamilyControl addItemsWithObjectValues:[NSFontManager.sharedFontManager.availableFontFamilies sortedArrayUsingSelector:@selector(localizedCaseInsensitiveCompare:)]];
    _fontFamilyControl.completes = YES;
    _fontFamilyControl.accessibilityLabel = @"候选字体";
    _fontFamilyControl.toolTip = @"可选择本机字体或输入字体家族名称；未安装时按补充字体顺序回退，最后使用系统字体，并保留原设置";
    _fontFamilyControl.target = self;
    _fontFamilyControl.action = @selector(fontFamilyChanged:);
    _textColorField = [[NSTextField alloc] initWithFrame:NSZeroRect];
    _textColorField.placeholderString = @"跟随皮肤（留空）";
    _textColorField.accessibilityLabel = @"候选文字颜色";
    _textColorField.target = self;
    _textColorField.action = @selector(textColorChanged:);
    [_textColorField.widthAnchor constraintEqualToConstant:110].active = YES;
    _textColorWell = [[NSColorWell alloc] initWithFrame:NSMakeRect(0, 0, 40, 24)];
    _textColorWell.accessibilityLabel = @"选择候选文字颜色";
    _textColorWell.target = self;
    _textColorWell.action = @selector(textColorWellChanged:);
    NSStackView *textColorControls = [NSStackView stackViewWithViews:@[_textColorField, _textColorWell,
        [NSButton buttonWithTitle:@"跟随皮肤" target:self action:@selector(resetTextColor:)]]];
    textColorControls.orientation = NSUserInterfaceLayoutOrientationHorizontal;
    _fallbackList = [[NSPopUpButton alloc] initWithFrame:NSZeroRect pullsDown:NO];
    _fallbackList.accessibilityLabel = @"补充字体顺序";
    [_fallbackList.widthAnchor constraintEqualToConstant:104].active = YES;
    _fallbackFamilyControl = [[NSComboBox alloc] initWithFrame:NSZeroRect];
    [_fallbackFamilyControl addItemsWithObjectValues:_fontFamilyControl.objectValues];
    _fallbackFamilyControl.completes = YES;
    _fallbackFamilyControl.accessibilityLabel = @"添加补充字体";
    _fallbackFamilyControl.placeholderString = @"字体家族名称";
    [_fallbackFamilyControl.widthAnchor constraintEqualToConstant:176].active = YES;
    NSButton *addFallback = [NSButton buttonWithTitle:@"添加" target:self action:@selector(addFallbackFont:)];
    NSStackView *fallbackAdd = [NSStackView stackViewWithViews:@[_fallbackFamilyControl, addFallback]];
    fallbackAdd.orientation = NSUserInterfaceLayoutOrientationHorizontal;
    NSStackView *fallbackOrder = [NSStackView stackViewWithViews:@[
        _fallbackList,
        [NSButton buttonWithTitle:@"上移" target:self action:@selector(moveFallbackFontUp:)],
        [NSButton buttonWithTitle:@"下移" target:self action:@selector(moveFallbackFontDown:)],
        [NSButton buttonWithTitle:@"移除" target:self action:@selector(removeFallbackFont:)]]];
    fallbackOrder.orientation = NSUserInterfaceLayoutOrientationHorizontal;
    _preeditFontButton = [[NSPopUpButton alloc] initWithFrame:NSZeroRect pullsDown:NO];
    for (NSUInteger size = 12; size <= 32; ++size)
        [_preeditFontButton addItemWithTitle:[NSString stringWithFormat:@"%lu pt", (unsigned long)size]];
    _preeditFontButton.accessibilityLabel = @"候选窗拼音字号";
    _preeditFontButton.target = self;
    _preeditFontButton.action = @selector(preeditFontChanged:);
    _candidatePreeditButton = [[NSPopUpButton alloc] initWithFrame:NSZeroRect pullsDown:NO];
    [_candidatePreeditButton addItemsWithTitles:@[@"显示拼音", @"隐藏"]];
    _candidatePreeditButton.accessibilityLabel = @"候选窗预编辑";
    _candidatePreeditButton.target = self;
    _candidatePreeditButton.action = @selector(candidatePreeditChanged:);
    _pageShortcutButton = [[NSPopUpButton alloc] initWithFrame:NSZeroRect pullsDown:NO];
    [_pageShortcutButton addItemsWithTitles:@[@"- / =", @"[ / ]", @"Page Up / Page Down"]];
    _pageShortcutButton.accessibilityLabel = @"候选翻页快捷键";
    _pageShortcutButton.target = self;
    _pageShortcutButton.action = @selector(pageShortcutChanged:);
    _wordCharacterToggle = MSIMESettingSwitch(self, @selector(wordCharacterChanged:), @"以词定字");
    _wordCharacterKeys = [[NSPopUpButton alloc] initWithFrame:NSZeroRect pullsDown:NO];
    [_wordCharacterKeys addItemsWithTitles:@[@"[ / ]", @"- / ="]];
    _wordCharacterKeys.accessibilityLabel = @"以词定字键组";
    _wordCharacterKeys.target = self;
    _wordCharacterKeys.action = @selector(wordCharacterChanged:);
    _navigationButtons = [NSMutableArray array];
    for (NSArray *entry in NavigationControls()) {
        NSButton *button = [NSButton checkboxWithTitle:entry[1] target:self action:@selector(navigationChanged:)];
        button.identifier = entry[0];
        button.accessibilityLabel = entry[1];
        if ([entry[0] isEqual:@"minus_equal"] || [entry[0] isEqual:@"brackets"])
            button.toolTip = @"此键组用于以词定字时，不能同时启用翻页";
        [_navigationButtons addObject:button];
    }
    _pageSizeButton = [[NSPopUpButton alloc] initWithFrame:NSZeroRect pullsDown:NO];
    for (NSUInteger index = 0; index < msime::mac::kOfferedCandidatePageSizes; ++index)
        [_pageSizeButton addItemWithTitle:[NSString stringWithFormat:@"%lu 个",
            (unsigned long)msime::mac::CandidatePageSizeForOptionIndex(index)]];
    _pageSizeButton.accessibilityLabel = @"每页候选";
    _pageSizeButton.target = self;
    _pageSizeButton.action = @selector(pageSizeChanged:);
    _inputModeShortcutToggle = MSIMESettingSwitch(self, @selector(inputModeShortcutChanged:), @"Shift + 空格切换中英文");
    _defaultImeModeButton = [[NSPopUpButton alloc] initWithFrame:NSZeroRect pullsDown:NO];
    [_defaultImeModeButton addItemsWithTitles:@[@"中文", @"英文"]];
    _defaultImeModeButton.target = self; _defaultImeModeButton.action = @selector(defaultImeModeChanged:);
    _imeModeScopeButton = [[NSPopUpButton alloc] initWithFrame:NSZeroRect pullsDown:NO];
    [_imeModeScopeButton addItemsWithTitles:@[@"按应用", @"全局"]];
    _imeModeScopeButton.target = self; _imeModeScopeButton.action = @selector(imeModeScopeChanged:);
    _imeModeScopeButton.toolTip = @"下一次激活时生效；中英文状态仅在当前输入法进程内记忆";
    _shiftTapShortcutToggle = MSIMESettingSwitch(self, @selector(shiftTapShortcutChanged:), @"单按 Shift 切换中英文");
    _controlTapShortcutToggle = MSIMESettingSwitch(self, @selector(controlTapShortcutChanged:), @"单按 Control 切换中英文");
    _controlOptionSpaceShortcutToggle = MSIMESettingSwitch(self, @selector(controlOptionSpaceShortcutChanged:), @"Control + Option + 空格切换中英文");
    _characterSetShortcutToggle = MSIMESettingSwitch(self, @selector(characterSetShortcutChanged:), @"Control + Shift + F 切换简繁");
    _fullWidthToggle = MSIMESettingSwitch(self, @selector(fullWidthChanged:), @"全角输入（Option + Shift + H）");
    _keymapToggle = MSIMESettingSwitch(self, @selector(keymapChanged:), @"输入时显示双拼键位提示");
    _wubiToggle = MSIMESettingSwitch(self, @selector(wubiChanged:), @"五笔四码唯一候选自动上屏");
    _punctuationToggle = MSIMESettingSwitch(self, @selector(punctuationChanged:), @"中文标点");
    _smartPunctuationToggle = MSIMESettingSwitch(self, @selector(smartPunctuationChanged:), @"智能标点");
    _smartPunctuationRepeatToggle = MSIMESettingSwitch(self, @selector(smartPunctuationRepeatChanged:), @"重复标点转中文");
    _pairedPunctuationToggle = MSIMESettingSwitch(self, @selector(pairedPunctuationChanged:), @"成对标点");
    _punctuationLockButton = [[NSPopUpButton alloc] initWithFrame:NSZeroRect pullsDown:NO];
    [_punctuationLockButton
        addItemsWithTitles:@[ @"跟随中英文状态", @"始终使用中文标点", @"始终使用英文标点" ]];
    _punctuationLockButton.accessibilityLabel = @"固定标点";
    _punctuationLockButton.target = self;
    _punctuationLockButton.action = @selector(punctuationLockChanged:);
    _mixedEnglishToggle = MSIMESettingSwitch(self, @selector(mixedEnglishChanged:), @"中英混输");
    _mixedEnglishPrefixButton = [[NSPopUpButton alloc] initWithFrame:NSZeroRect pullsDown:NO];
    NSMutableArray<NSString *> *mixedPrefixes = [NSMutableArray array];
    for (NSInteger prefix = 1; prefix <= 8; ++prefix)
        [mixedPrefixes addObject:[NSString stringWithFormat:@"%ld 个字符", (long)prefix]];
    [_mixedEnglishPrefixButton addItemsWithTitles:mixedPrefixes];
    _mixedEnglishPrefixButton.accessibilityLabel = @"中英混输触发字符数";
    _mixedEnglishPrefixButton.target = self;
    _mixedEnglishPrefixButton.action = @selector(mixedEnglishPrefixChanged:);
    _mixedEmojiToggle = MSIMESettingSwitch(self, @selector(mixedEmojiChanged:), @"Emoji 混输");
    _mixedKaomojiToggle = MSIMESettingSwitch(self, @selector(mixedKaomojiChanged:), @"颜文字混输");
    _toolbarToggle = MSIMESettingSwitch(self, @selector(toolbarChanged:), @"显示浮动工具栏");
    _toolbarPunctuationButton = [NSButton checkboxWithTitle:@"标点按钮" target:self action:@selector(toolbarPunctuationChanged:)];
    _toolbarFullWidthButton = [NSButton checkboxWithTitle:@"全半角按钮" target:self action:@selector(toolbarFullWidthChanged:)];
    _toolbarCharacterSetButton = [NSButton checkboxWithTitle:@"简繁按钮" target:self action:@selector(toolbarCharacterSetChanged:)];
    _toolbarEmojiButton = [NSButton checkboxWithTitle:@"Emoji 按钮" target:self action:@selector(toolbarEmojiChanged:)];
    _toolbarScreenKeyboardButton = [NSButton checkboxWithTitle:@"屏幕键盘按钮" target:self action:@selector(toolbarScreenKeyboardChanged:)];
    _toolbarSettingsButton = [NSButton checkboxWithTitle:@"设置按钮" target:self action:@selector(toolbarSettingsChanged:)];
    _toolbarScaleButton = [[NSPopUpButton alloc] initWithFrame:NSZeroRect pullsDown:NO];
    [_toolbarScaleButton addItemsWithTitles:@[@"75%", @"100%", @"125%", @"150%"]];
    _toolbarScaleButton.accessibilityLabel = @"工具栏缩放";
    _toolbarScaleButton.target = self; _toolbarScaleButton.action = @selector(toolbarScaleChanged:);
    _toolbarFontSizeButton = [[NSPopUpButton alloc] initWithFrame:NSZeroRect pullsDown:NO];
    for (NSInteger size = 16; size <= 28; size += 2)
        [_toolbarFontSizeButton addItemWithTitle:[NSString stringWithFormat:@"%ld pt", (long)size]];
    _toolbarFontSizeButton.accessibilityLabel = @"工具栏字号";
    _toolbarFontSizeButton.target = self; _toolbarFontSizeButton.action = @selector(toolbarFontSizeChanged:);
    _transpositionToggle = MSIMESettingSwitch(self, @selector(transpositionChanged:), @"全拼乱序纠错（sahng → shang）");
    _neighborToggle = MSIMESettingSwitch(self, @selector(neighborChanged:), @"全拼邻键纠错（shabg → shang）");
    _candidateLearningToggle = MSIMESettingSwitch(self, @selector(candidateLearningChanged:), @"学习候选词频");
    _frequencyModeButton = [[NSPopUpButton alloc] initWithFrame:NSZeroRect pullsDown:NO];
    [_frequencyModeButton addItemsWithTitles:@[@"关闭", @"置顶", @"折半", @"线性", @"置前"]];
    _frequencyModeButton.target = self;
    _frequencyModeButton.action = @selector(frequencyModeChanged:);
    _frequencyTriggerButton = [[NSPopUpButton alloc] initWithFrame:NSZeroRect pullsDown:NO];
    _frequencyStepButton = [[NSPopUpButton alloc] initWithFrame:NSZeroRect pullsDown:NO];
    NSMutableArray<NSString *> *frequencyCounts = [NSMutableArray array];
    for (NSInteger count = 1; count <= 10; ++count)
        [frequencyCounts addObject:[NSString stringWithFormat:@"%ld 次", (long)count]];
    [_frequencyTriggerButton addItemsWithTitles:frequencyCounts];
    [_frequencyStepButton addItemsWithTitles:frequencyCounts];
    _frequencyTriggerButton.target = self;
    _frequencyTriggerButton.action = @selector(frequencyTriggerChanged:);
    _frequencyStepButton.target = self;
    _frequencyStepButton.action = @selector(frequencyStepChanged:);
    _fuzzyPinyinToggle = MSIMESettingSwitch(self, @selector(fuzzyPinyinChanged:), @"启用模糊音");
    _cloudCandidatesToggle = MSIMESettingSwitch(self, @selector(cloudCandidatesChanged:), @"启用云候选（将查询发送至 Google 输入工具）");
    _candidateTranslationsToggle = MSIMESettingSwitch(self, @selector(candidateTranslationsChanged:), @"显示候选释义");
    _candidateEnglishGlossToggle = MSIMESettingSwitch(self, @selector(candidateEnglishGlossChanged:), @"显示离线英文释义");
    _quanpinHelpcodeToggle = MSIMESettingSwitch(self, @selector(quanpinHelpcodeChanged:), @"启用全拼辅助码");
    _shuangpinHelpcodeToggle = MSIMESettingSwitch(self, @selector(shuangpinHelpcodeChanged:), @"启用双拼辅助码");
    _helpcodeSchemaButtons = [NSMutableDictionary dictionary];
    _helpcodeDisplayToggles = [NSMutableDictionary dictionary];
    _fuzzyPinyinRuleButtons = [NSMutableDictionary dictionary];
    _localModeButtons = [NSMutableArray array];

    // ---- 输入 -------------------------------------------------------------------------------
    NSBox *inputModeCard = MSIMECardWithViews(@[
        MSIMEPreferenceRow(@"输入模式", _defaultImeModeButton),
        MSIMEPreferenceRow(@"模式作用范围", _imeModeScopeButton),
    ], 0.0);
    inputModeCard.accessibilityLabel = @"输入模式卡片";

    // The scheme is one choice, so it reads as radios with each scheme's own popup trailing it,
    // disabled until that scheme is selected. The stored value stays the same scheme string.
    NSArray<NSString *> *schemeTitles = @[@"全拼输入", @"双拼输入", @"五笔输入", @"日语输入"];
    NSMutableArray<NSButton *> *schemeButtons = [NSMutableArray array];
    NSMutableArray<NSView *> *schemeRows = [NSMutableArray arrayWithObjects:MSIMECardHeader(@"输入方式"), MSIMECardSeparator(), nil];
    _shuangpinSchemeButton = _profileButton;
    _wubiSchemeButton = [[NSPopUpButton alloc] initWithFrame:NSZeroRect pullsDown:NO];
    [_wubiSchemeButton addItemWithTitle:@"86 五笔"];
    _wubiSchemeButton.accessibilityLabel = @"五笔方案";
    for (NSInteger index = 0; index < (NSInteger)schemeTitles.count; ++index) {
        NSButton *button = [NSButton radioButtonWithTitle:schemeTitles[index] target:self action:@selector(schemeRadioChanged:)];
        button.tag = index;
        button.font = [NSFont systemFontOfSize:13.0 weight:NSFontWeightMedium];
        button.accessibilityLabel = schemeTitles[index];
        [schemeButtons addObject:button];
        NSView *accessory = index == 1 ? _shuangpinSchemeButton : (index == 2 ? _wubiSchemeButton : nil);
        [schemeRows addObject:SchemeChoiceRow(button, accessory)];
        if (index < (NSInteger)schemeTitles.count - 1) [schemeRows addObject:MSIMECardSeparator()];
    }
    _schemeButtons = schemeButtons;
    NSBox *schemeCard = MSIMECardWithViews(schemeRows, 0.0);
    schemeCard.accessibilityLabel = @"输入方式卡片";

    // The options belonging to one scheme follow the scheme card and appear only while that scheme
    // is the selected one. Upstream shows the 双拼 options whatever is selected — editable, saved,
    // and with no effect until you come back and pick 双拼 — and puts the 五笔 options on a page of
    // their own reached by a link, with a 返回键盘输入 button to get out. That is a web flow inside
    // a sidebar window: the sidebar stays on 输入 while the content is somewhere else.
    _shuangpinCard = MSIMECardWithViews(@[
        MSIMEPreferenceRow(@"双拼预编辑", _preeditButton),
        // Upstream labels this row 双拼初学者 and puts the wording on the checkbox beside it, so the
        // row says the same thing twice. The switch carries no text, so the label carries it.
        MSIMESwitchRow(@"输入时显示双拼键位提示", _keymapToggle, nil),
    ], 0.0);
    _shuangpinCard.accessibilityLabel = @"双拼选项卡片";
    NSTextField *wubiSchemeLabel = [NSTextField labelWithString:@"86 五笔"];
    wubiSchemeLabel.textColor = [NSColor secondaryLabelColor];
    _wubiCard = MSIMECardWithViews(@[
        MSIMEPreferenceRow(@"编码方案", wubiSchemeLabel),
        MSIMESwitchRow(@"四码唯一候选自动上屏", _wubiToggle, nil),
    ], 0.0);
    _wubiCard.accessibilityLabel = @"五笔选项卡片";

    NSBox *punctuationCard = MSIMECardWithViews(@[
        MSIMESwitchRow(@"中文标点", _punctuationToggle, @"Control+. 切换中英文标点"),
        MSIMESwitchRow(@"智能标点", _smartPunctuationToggle, @"前一个字符为字母或数字时保留逗号、句号和冒号为 ASCII 形式"),
        MSIMESwitchRow(@"重复标点转中文", _smartPunctuationRepeatToggle, @"短时间重复输入 ASCII 标点时替换为中文标点"),
        MSIMESwitchRow(@"成对标点", _pairedPunctuationToggle, @"自动插入并配对引号、括号等标点"),
        MSIMEPreferenceRow(@"固定标点", _punctuationLockButton),
    ], 0.0);
    punctuationCard.accessibilityLabel = @"标点输入卡片";
    NSBox *mixedCard = MSIMECardWithViews(@[
        MSIMESwitchRow(@"中英混输", _mixedEnglishToggle, @"在中文组词中允许英文候选"),
        MSIMEPreferenceRow(@"中英混输触发长度", _mixedEnglishPrefixButton),
        MSIMESwitchRow(@"Emoji 混输", _mixedEmojiToggle, @"在中文组词中提供 Emoji 候选"),
        MSIMESwitchRow(@"颜文字混输", _mixedKaomojiToggle, @"在中文组词中提供颜文字候选"),
    ], 0.0);
    mixedCard.accessibilityLabel = @"中英混输卡片";
    NSBox *correctionCard = MSIMECardWithViews(@[
        MSIMESwitchRow(@"全拼乱序纠错（sahng → shang）", _transpositionToggle, nil),
        MSIMESwitchRow(@"全拼邻键纠错（shabg → shang）", _neighborToggle, nil),
    ], 0.0);
    correctionCard.accessibilityLabel = @"拼音纠错卡片";
    NSMutableArray<NSButton *> *fuzzyRuleBoxes = [NSMutableArray array];
    for (NSArray *entry in FuzzyPinyinRuleControls()) {
        NSButton *button = [NSButton checkboxWithTitle:entry[1] target:self action:@selector(fuzzyPinyinRuleChanged:)];
        button.identifier = entry[0];
        _fuzzyPinyinRuleButtons[entry[0]] = button;
        [fuzzyRuleBoxes addObject:button];
    }
    NSBox *fuzzyCard = MSIMECardWithViews(@[
        MSIMESwitchRow(@"启用模糊音", _fuzzyPinyinToggle, nil),
        MSIMECardSeparator(),
        MSIMECheckboxGrid(fuzzyRuleBoxes, 3),
    ], 8.0);
    fuzzyCard.accessibilityLabel = @"模糊音卡片";

    NSScrollView *generalPage = PreferencesPage(@"键盘输入", @"选择中文或日语输入模式，并调整日常输入行为。", @[
        inputModeCard, MSIMESectionLabel(@"中文输入方案"), schemeCard, _shuangpinCard, _wubiCard,
        MSIMESectionLabel(@"标点输入"), punctuationCard, MSIMESectionLabel(@"中英混输"), mixedCard,
        MSIMESectionLabel(@"拼音纠错"), correctionCard, MSIMESectionLabel(@"模糊音"), fuzzyCard,
    ]);

    // ---- 外观 -------------------------------------------------------------------------------
    _preview = [[MSIMECandidatePreviewView alloc] initWithFrame:NSMakeRect(0, 0, 580, 190)];
    _preview.preferences = self;
    _preview.translatesAutoresizingMaskIntoConstraints = NO;
    _themeButton = [NSButton buttonWithTitle:[_preview forcedThemeButtonTitle] target:self action:@selector(togglePreviewTheme:)];
    _preview.themeButton = _themeButton;
    NSButton *showcase = [NSButton checkboxWithTitle:@"同时预览横排、竖排与状态栏" target:self action:@selector(togglePreviewShowcase:)];
    NSStackView *previewControls = [NSStackView stackViewWithViews:@[showcase, _themeButton]];
    previewControls.orientation = NSUserInterfaceLayoutOrientationHorizontal;
    previewControls.spacing = 12.0;
    NSBox *candidateWindowCard = MSIMECardWithViews(@[
        MSIMEPreferenceRow(@"候选排列", _layoutButton),
        MSIMEPreferenceRow(@"每页候选", _pageSizeButton),
        MSIMEPreferenceRow(@"候选字号", _fontButton),
        MSIMEPreferenceRow(@"候选窗拼音字号", _preeditFontButton),
        MSIMEPreferenceRow(@"候选窗预编辑", _candidatePreeditButton),
        MSIMESwitchRow(@"候选窗口跟随光标", _candidateFollowCursorToggle, nil),
    ], 0.0);
    candidateWindowCard.accessibilityLabel = @"候选窗口卡片";
    // The three clusters — a field beside a colour well, a field beside a button, a popup beside
    // three buttons — are wider than one popup, and the row now lets them be: the control column is
    // placed against the trailing edge rather than pinned to a width, so the card keeps one control
    // edge without the second fixed width these rows used to ask for.
    NSBox *fontCard = MSIMECardWithViews(@[
        MSIMEPreferenceRow(@"候选字体", _fontFamilyControl),
        MSIMEPreferenceRow(@"候选窗英文字体", _englishFontFamilyControl),
        MSIMEPreferenceRow(@"候选文字颜色", textColorControls),
        MSIMEPreferenceRow(@"补充字体（最多 32 项）", fallbackAdd),
        MSIMEPreferenceRow(@"补充字体优先顺序", fallbackOrder),
    ], 0.0);
    fontCard.accessibilityLabel = @"候选字体卡片";
    NSScrollView *appearancePage = PreferencesPage(@"外观", @"调整候选窗口与输入状态栏的显示方式。", @[
        MSIMESectionLabel(@"效果预览"), _preview, previewControls,
        MSIMESectionLabel(@"候选窗口"), candidateWindowCard,
        MSIMESectionLabel(@"候选字体"), fontCard,
    ]);

    // ---- 皮肤 -------------------------------------------------------------------------------
    // The page is the skin browser itself. It already existed — cards with a live candidate preview
    // of each skin, in both appearances — but it lived in a window of its own behind a
    // 浏览所有皮肤… button, and the page you actually landed on offered a popup of skin names.
    // Picking a skin by reading its name out of a menu is choosing a look you cannot see.
    // The shared settings application has a skin page too. It stays reachable, but as a named trip
    // to another application rather than as the button you press to pick a skin.
    NSButton *sharedSkinPage = [NSButton buttonWithTitle:@"在设置应用中打开…" target:self action:@selector(showSkinCatalog:)];
    MSIMELinkifyButton(sharedSkinPage, @"在设置应用中打开皮肤页");
    sharedSkinPage.translatesAutoresizingMaskIntoConstraints = NO;
    // The cards are filled in the first time the page is shown. Building them renders a live
    // candidate preview per skin and rescans the skin directory, and rescanning announces an
    // appearance change — doing that while merely opening the window rebuilds the candidate panel
    // for a page the user has not asked for.
    _skinPageContainer = [[NSView alloc] initWithFrame:NSZeroRect];
    _skinPageContainer.translatesAutoresizingMaskIntoConstraints = NO;
    _skinPageContainer.accessibilityLabel = @"皮肤";
    [_skinPageContainer addSubview:sharedSkinPage];
    [NSLayoutConstraint activateConstraints:@[
        [sharedSkinPage.trailingAnchor constraintEqualToAnchor:_skinPageContainer.trailingAnchor constant:-kPageMargin],
        [sharedSkinPage.bottomAnchor constraintEqualToAnchor:_skinPageContainer.bottomAnchor constant:-6.0],
    ]];
    _skinPageSharedEntry = sharedSkinPage;
    NSView *skinPage = _skinPageContainer;

    // ---- 词库与数据 --------------------------------------------------------------------------
    NSBox *learningCard = MSIMECardWithViews(@[
        MSIMESwitchRow(@"学习候选词频", _candidateLearningToggle, nil),
        MSIMEPreferenceRow(@"词频调整方式", _frequencyModeButton),
        MSIMEPreferenceRow(@"词频触发次数", _frequencyTriggerButton),
        MSIMEPreferenceRow(@"线性调整步长", _frequencyStepButton),
    ], 0.0);
    learningCard.accessibilityLabel = @"候选与学习卡片";
    NSButton *aiButton = [NSButton buttonWithTitle:@"配置 AI 联想…" target:self action:@selector(showAISettings:)];
    NSButton *translationButton = [NSButton buttonWithTitle:@"配置候选翻译…" target:self action:@selector(showTranslationSettings:)];
    NSButton *dictionaryButton = [NSButton buttonWithTitle:@"打开词库管理…" target:self action:@selector(showDictionary:)];
    dictionaryButton.accessibilityLabel = @"打开本机词库管理";
    NSBox *cloudCard = MSIMECardWithViews(@[
        // Where the query goes stays on the label rather than moving into a tooltip: it is the one
        // switch here that sends what is being typed off the machine.
        MSIMESwitchRow(@"启用云候选（将查询发送至 Google 输入工具）", _cloudCandidatesToggle, nil),
        MSIMESwitchRow(@"显示候选释义", _candidateTranslationsToggle, nil),
        MSIMESwitchRow(@"显示离线英文释义", _candidateEnglishGlossToggle, nil),
        MSIMEPreferenceRow(@"AI 联想", aiButton),
        MSIMEPreferenceRow(@"翻译服务与目标语言", translationButton),
    ], 0.0);
    cloudCard.accessibilityLabel = @"云端与智能候选卡片";
    NSBox *dictionaryCard = MSIMECardWithViews(@[
        MSIMEPreferenceRow(@"本机用户词库", dictionaryButton),
    ], 0.0);
    dictionaryCard.accessibilityLabel = @"本机用户词库卡片";
    NSScrollView *dataPage = PreferencesPage(@"词库与数据", @"管理本机词库、用户词条与学习数据。", @[
        MSIMESectionLabel(@"候选与学习"), learningCard, MSIMESectionLabel(@"本机词库"), dictionaryCard,
        MSIMESectionLabel(@"云端与智能候选"), cloudCard,
    ]);

    // ---- 关于 -------------------------------------------------------------------------------
    Class updateControllerClass = NSClassFromString(@"MetasequoiaUpdateController");
    if ([updateControllerClass respondsToSelector:@selector(sharedController)])
        _updateController = [updateControllerClass sharedController];
    _versionLabel = [NSTextField labelWithString:@"开发构建"];
    _versionLabel.textColor = [NSColor secondaryLabelColor];
    _versionLabel.alignment = NSTextAlignmentRight;
    _versionLabel.accessibilityLabel = @"当前版本";
    _automaticUpdateLabel = [NSTextField labelWithString:@"检查自动更新状态…"];
    _automaticUpdateLabel.textColor = [NSColor secondaryLabelColor];
    _automaticUpdateLabel.alignment = NSTextAlignmentRight;
    _automaticUpdateLabel.accessibilityLabel = @"自动更新状态";
    _updatePageButton = [NSButton buttonWithTitle:@"检查更新…" target:self action:@selector(checkForUpdates:)];
    _updatePageButton.accessibilityLabel = @"立即检查更新";
    NSBox *updateCard = MSIMECardWithViews(@[
        MSIMEPreferenceRow(@"当前版本", _versionLabel),
        MSIMEPreferenceRow(@"自动更新", _automaticUpdateLabel),
        MSIMEPreferenceRow(@"立即检查", _updatePageButton),
    ], 0.0);
    updateCard.accessibilityLabel = @"软件更新卡片";
    NSButton *websiteButton = [NSButton buttonWithTitle:@"访问 msime.app" target:self action:@selector(openProductWebsite:)];
    MSIMELinkifyButton(websiteButton, @"访问水杉官网");
    _removeUserDataButton = [NSButton checkboxWithTitle:@"同时删除词库、学习记录、偏好与语音密钥"
                                                   target:nil
                                                   action:nil];
    _removeUserDataButton.accessibilityLabel = @"卸载时删除本机数据";
    _uninstallButton = [NSButton buttonWithTitle:@"卸载…" target:self action:@selector(uninstallInputSource:)];
    _uninstallButton.bezelStyle = NSBezelStyleRounded;
    _uninstallButton.contentTintColor = NSColor.systemRedColor;
    _uninstallButton.accessibilityLabel = @"卸载水杉输入法";
    _uninstallButton.enabled = msime_macos_uninstall_input_source != nullptr;
    NSBox *uninstallCard = MSIMECardWithViews(@[
        MSIMEPreferenceRow(@"输入源", _uninstallButton), _removeUserDataButton,
    ], 6.0);
    uninstallCard.accessibilityLabel = @"卸载输入源卡片";
    NSBox *aboutCard = MSIMECardWithViews(@[MSIMEPreferenceRow(@"产品主页", websiteButton)], 0.0);
    aboutCard.accessibilityLabel = @"关于卡片";
    // The sidebar used to open with the icon and the product name above the navigation. Under a
    // transparent titlebar that space belongs to the traffic lights and the search field, so the
    // mark moves here, where a Mac application states what it is.
    NSImageView *logo = [[NSImageView alloc] initWithFrame:NSZeroRect];
    // The bundle's own icon, not a redrawn approximation of it: this mark and the Dock tile are
    // then the same artwork by construction and cannot drift apart in shape or colour.
    logo.image = [NSImage imageNamed:NSImageNameApplicationIcon];
    logo.imageScaling = NSImageScaleProportionallyUpOrDown;
    logo.accessibilityLabel = @"水杉 IME";
    logo.translatesAutoresizingMaskIntoConstraints = NO;
    [logo.widthAnchor constraintEqualToConstant:52.0].active = YES;
    [logo.heightAnchor constraintEqualToConstant:52.0].active = YES;
    NSTextField *brand = [NSTextField labelWithString:@"水杉输入法"];
    brand.font = [NSFont systemFontOfSize:17.0 weight:NSFontWeightSemibold];
    NSTextField *tagline = [NSTextField labelWithString:@"Metasequoia IME"];
    tagline.font = [NSFont systemFontOfSize:kBodyFontSize];
    tagline.textColor = NSColor.secondaryLabelColor;
    NSStackView *brandText = [NSStackView stackViewWithViews:@[brand, tagline]];
    brandText.orientation = NSUserInterfaceLayoutOrientationVertical;
    brandText.alignment = NSLayoutAttributeLeading;
    brandText.spacing = 2.0;
    NSStackView *brandRow = [NSStackView stackViewWithViews:@[logo, brandText]];
    brandRow.orientation = NSUserInterfaceLayoutOrientationHorizontal;
    brandRow.alignment = NSLayoutAttributeCenterY;
    brandRow.spacing = 14.0;
    brandRow.translatesAutoresizingMaskIntoConstraints = NO;
    NSScrollView *aboutPage = PreferencesPage(@"关于", @"版本与更新，以及水杉输入法的产品主页。", @[
        brandRow, MSIMESectionLabel(@"软件更新"), updateCard, MSIMESectionLabel(@"产品信息"), aboutCard,
        MSIMESectionLabel(@"卸载"), uninstallCard,
    ]);

    // ---- 辅助码 -----------------------------------------------------------------------------
    NSMutableArray<NSView *> *helpcodeRows = [NSMutableArray arrayWithObjects:
        MSIMESwitchRow(@"启用全拼辅助码", _quanpinHelpcodeToggle, nil),
        MSIMESwitchRow(@"启用双拼辅助码", _shuangpinHelpcodeToggle, nil), nil];
    for (NSString *scheme in @[@"quanpin", @"shuangpin"]) {
        NSString *name = [scheme isEqual:@"quanpin"] ? @"全拼" : @"双拼";
        NSPopUpButton *schemas = [[NSPopUpButton alloc] initWithFrame:NSZeroRect pullsDown:NO];
        [schemas addItemsWithTitles:@[@"蓝天小雨点", @"自然码", @"首右2.0", @"首右plus", @"小鹤", @"加加"]];
        for (NSUInteger index = 0; index < HelpcodeSchemas().count; ++index)
            [schemas itemAtIndex:index].representedObject = HelpcodeSchemas()[index];
        schemas.identifier = scheme;
        schemas.target = self;
        schemas.action = @selector(helpcodeSchemaChanged:);
        schemas.accessibilityLabel = [name stringByAppendingString:@"辅助码方案"];
        NSString *displayTitle = [NSString stringWithFormat:@"在候选窗口中显示%@辅助码", name];
        NSSwitch *display = MSIMESettingSwitch(self, @selector(helpcodeDisplayChanged:), displayTitle);
        display.identifier = scheme;
        _helpcodeSchemaButtons[scheme] = schemas;
        _helpcodeDisplayToggles[scheme] = display;
        [helpcodeRows addObject:MSIMEPreferenceRow(schemas.accessibilityLabel, schemas)];
        [helpcodeRows addObject:MSIMESwitchRow(displayTitle, display, nil)];
    }
    NSBox *helpcodeCard = MSIMECardWithViews(helpcodeRows, 0.0);
    helpcodeCard.accessibilityLabel = @"辅助码卡片";
    NSScrollView *helpcodePage = PreferencesPage(@"辅助码", @"为全拼与双拼分别选择辅助码方案。", @[
        MSIMESectionLabel(@"辅助码方案"), helpcodeCard,
    ]);

    // ---- 快捷键 -----------------------------------------------------------------------------
    NSBox *pagingCard = MSIMECardWithViews(@[
        MSIMEPreferenceRow(@"上翻 / 下翻", _pageShortcutButton),
        MSIMECardSeparator(),
        MSIMECardHeader(@"独立候选导航"),
        // Six peer key-pairs in the control column of one row is a tall stack pushed against the
        // right edge. They are a group, so they get the card's width and a heading of their own.
        MSIMECheckboxGrid(_navigationButtons, 2),
        MSIMECardSeparator(),
        MSIMESwitchRow(@"以词定字（首字／尾字）", _wordCharacterToggle, @"须先关闭所选键组的翻页功能"),
        MSIMEPreferenceRow(@"首字／尾字键组", _wordCharacterKeys),
    ], 6.0);
    pagingCard.accessibilityLabel = @"候选翻页卡片";
    NSBox *switchingCard = MSIMECardWithViews(@[
        MSIMESwitchRow(@"Shift + 空格切换中英文", _inputModeShortcutToggle, nil),
        MSIMESwitchRow(@"单按 Shift 切换中英文", _shiftTapShortcutToggle, nil),
        MSIMESwitchRow(@"单按 Control 切换中英文", _controlTapShortcutToggle, nil),
        MSIMESwitchRow(@"Control + Option + 空格切换中英文", _controlOptionSpaceShortcutToggle, nil),
        MSIMESwitchRow(@"Control + Shift + F 切换简繁", _characterSetShortcutToggle, nil),
        MSIMESwitchRow(@"全角输入（Option + Shift + H）", _fullWidthToggle,
                  @"Control+Shift+Space 或 Option+Shift+H 切换全半角"),
    ], 0.0);
    switchingCard.accessibilityLabel = @"输入状态切换卡片";
    NSScrollView *shortcutsPage = PreferencesPage(@"快捷键", @"设置候选翻页与输入状态切换快捷键。", @[
        MSIMESectionLabel(@"候选翻页与选字"), pagingCard, MSIMESectionLabel(@"输入状态切换"), switchingCard,
    ]);

    // ---- 悬浮工具栏 --------------------------------------------------------------------------
    NSBox *toolbarCard = MSIMECardWithViews(@[
        MSIMESwitchRow(@"显示浮动工具栏", _toolbarToggle, nil),
        MSIMECardSeparator(),
        MSIMECardHeader(@"工具栏按钮"),
        MSIMECheckboxGrid(@[
            _toolbarPunctuationButton, _toolbarFullWidthButton, _toolbarCharacterSetButton,
            _toolbarEmojiButton, _toolbarScreenKeyboardButton, _toolbarSettingsButton,
        ], 2),
    ], 6.0);
    toolbarCard.accessibilityLabel = @"悬浮工具栏卡片";
    NSBox *toolbarSizeCard = MSIMECardWithViews(@[
        MSIMEPreferenceRow(@"工具栏缩放", _toolbarScaleButton),
        MSIMEPreferenceRow(@"工具栏字号", _toolbarFontSizeButton),
    ], 0.0);
    toolbarSizeCard.accessibilityLabel = @"悬浮工具栏尺寸卡片";
    NSScrollView *floatingPage = PreferencesPage(@"悬浮工具栏", @"随时查看输入状态，通过工具栏切换常用输入选项。", @[
        MSIMESectionLabel(@"显示与组件"), toolbarCard, MSIMESectionLabel(@"尺寸"), toolbarSizeCard,
    ]);

    // ---- 账号 -------------------------------------------------------------------------------
    NSView *accountPaneView = nil;
    if (MSIMEAccountPaneView != nullptr) {
        accountPaneView = MSIMEAccountPaneView();
        [accountPaneView.heightAnchor constraintGreaterThanOrEqualToConstant:520.0].active = YES;
    } else {
        NSButton *accountButton = [NSButton buttonWithTitle:@"管理水杉账号…" target:self action:@selector(showBackendAccount:)];
        accountButton.accessibilityIdentifier = @"MSIMEClientBackendAccount";
        NSBox *accountCard = MSIMECardWithViews(@[MSIMEPreferenceRow(@"登录与账号管理", accountButton)], 0.0);
        accountCard.accessibilityLabel = @"水杉账号卡片";
        accountPaneView = MSIMECardWithViews(@[MSIMESectionLabel(@"水杉账号"), accountCard], 0.0);
    }
    NSScrollView *accountPage = PreferencesPage(@"账号", @"登录水杉账号后，候选词翻译、云同步等需要账号的功能才会生效。", @[
        accountPaneView,
    ]);

    // ---- 帮助 / 反馈 -------------------------------------------------------------------------
    // Upstream builds both pages out of its own help copy and a local issue form. This host has
    // neither; it routes to the existing support window instead of inventing the content here.
    NSButton *helpButton = [NSButton buttonWithTitle:@"打开使用帮助…" target:self action:@selector(showSupport:)];
    NSBox *helpCard = MSIMECardWithViews(@[MSIMEPreferenceRow(@"常用按键与常见问题", helpButton)], 0.0);
    helpCard.accessibilityLabel = @"帮助卡片";
    NSScrollView *helpPage = PreferencesPage(@"帮助", @"常用按键、候选词释义的工作方式，以及常见问题。", @[
        MSIMESectionLabel(@"使用帮助"), helpCard,
    ]);
    NSButton *feedbackButton = [NSButton buttonWithTitle:@"提交反馈…" target:self action:@selector(showSupport:)];
    NSBox *feedbackCard = MSIMECardWithViews(@[MSIMEPreferenceRow(@"问题反馈与功能建议", feedbackButton)], 0.0);
    feedbackCard.accessibilityLabel = @"反馈卡片";
    NSScrollView *feedbackPage = PreferencesPage(@"反馈", @"在这里写清问题，提交时会带上版本与系统信息。", @[
        MSIMESectionLabel(@"问题反馈"), feedbackCard,
    ]);

    // ---- 语音输入 ---------------------------------------------------------------------------
    // The form itself, not a 配置语音输入… button opening a second window with its own 保存 button.
    Class voiceFormClass = NSClassFromString(@"MetasequoiaVoiceProviderSettingsView");
    _voiceSettingsView = [[voiceFormClass alloc] initWithFrame:NSZeroRect];
    NSView *voiceContent = _voiceSettingsView
        ?: (NSView *)MSIMECardWithViews(@[MSIMEPreferenceRow(@"语音输入",
               [NSTextField labelWithString:@"此构建不包含语音模块。"])], 0.0);
    NSScrollView *voicePage = PreferencesPage(@"语音输入", @"配置听写使用的识别服务，以及识别后的文本整理。", @[
        voiceContent,
    ]);

    // ---- 实用功能 ---------------------------------------------------------------------------
    for (NSArray<NSString *> *entry in LocalModeControls()) {
        NSButton *button = [NSButton checkboxWithTitle:entry[1] target:self action:@selector(localModeChanged:)];
        button.identifier = entry[0];
        [_localModeButtons addObject:button];
    }
    NSBox *localModesCard = MSIMECardWithViews(@[MSIMECheckboxGrid(_localModeButtons, 2)], 0.0);
    localModesCard.accessibilityLabel = @"扩展输入卡片";
    NSScrollView *utilitiesPage = PreferencesPage(@"实用功能", @"未组词时用 Shift 加一个字母，临时切到另一种输入方式。", @[
        MSIMESectionLabel(@"扩展输入模式"), localModesCard,
    ]);

    // The index is both the page index and the sidebar item's page index. Every page has a sidebar
    // item now that 五笔 folds into 输入, so the two lists line up one to one.
    _preferencePages = @[
        generalPage, appearancePage, skinPage, dataPage, aboutPage, helpcodePage, shortcutsPage,
        floatingPage, accountPage, helpPage, feedbackPage, voicePage, utilitiesPage,
    ];

    NSArray<NSString *> *navigationLabels = @[
        @"输入", @"外观", @"皮肤", @"词库", @"关于", @"辅助码", @"快捷键", @"悬浮工具栏", @"账号", @"帮助",
        @"反馈", @"语音输入", @"实用功能",
    ];
    NSArray<NSString *> *navigationSymbols = @[
        @"keyboard", @"paintpalette", @"photo.on.rectangle", @"book", @"info.circle", @"a.circle",
        @"command", @"ellipsis.rectangle", @"person.crop.circle", @"questionmark.square", @"ladybug", @"mic",
        @"wand.and.stars",
    ];
    _pageTitles = navigationLabels;
    // The stable name of each page, parallel to _preferencePages. Both things that have to point at
    // a page from outside this method — the remembered page and -showSettingsPageWithIdentifier: —
    // name it instead of numbering it, because the numbering is the one part of this list that is
    // expected to change. The names are the tails of the shared settings: routes
    // (src/core/DesktopSettingsLauncher.h), so a deep link reads the same whichever settings
    // surface answers it.
    _pageIdentifiers = @[
        @"input", @"appearance", @"skin", @"dictionary", @"about", @"helpcode", @"shortcuts",
        @"floating", @"account", @"help", @"feedback", @"voice", @"utilities",
    ];
    // Four runs with nothing but a gap between them announce a grouping without saying what it
    // groups by, so each run gets the heading AppKit puts above a source-list section.
    NSArray<NSString *> *groupTitles = @[@"输入", @"外观", @"数据", @"支持"];
    NSArray<NSArray<NSNumber *> *> *navigationGroups = @[
        @[@0, @5, @6, @12, @11],  // 输入 · 辅助码 · 快捷键 · 实用功能 · 语音输入
        @[@1, @2, @7],            // 外观 · 皮肤 · 悬浮工具栏
        @[@3, @8],                // 词库 · 账号
        @[@9, @10, @4],           // 帮助 · 反馈 · 关于
    ];
    NSMutableArray<MSIMESettingsSidebarItem *> *sidebarGroups = [NSMutableArray array];
    for (NSUInteger groupIndex = 0; groupIndex < navigationGroups.count; ++groupIndex) {
        NSMutableArray<MSIMESettingsSidebarItem *> *members = [NSMutableArray array];
        for (NSNumber *pageIndex in navigationGroups[groupIndex]) {
            const NSInteger index = pageIndex.integerValue;
            MSIMESettingsSidebarItem *member = [MSIMESettingsSidebarItem new];
            member.title = navigationLabels[index];
            member.symbolName = navigationSymbols[index];
            member.pageIndex = index;
            [members addObject:member];
        }
        MSIMESettingsSidebarItem *group = [MSIMESettingsSidebarItem new];
        group.title = groupTitles[groupIndex];
        group.pageIndex = -1;
        group.children = members;
        [sidebarGroups addObject:group];
    }
    _sidebarGroups = sidebarGroups;

    // The sidebar is a source list, not thirteen push-on buttons in a stack view. What the system
    // brings with it is everything the drawn version had to imitate and mostly did not: desaturating
    // when the window loses focus, hover, the vibrant selection, truncation with an ellipsis, the
    // focus ring, arrow keys that hand the selection back at either end, and type-select. It is in a
    // scroll view because a stack view with no bottom anchor drew its last rows past the bottom of
    // the sidebar at the minimum window height, where they could not be clicked.
    _sidebarOutline = [[NSOutlineView alloc] initWithFrame:NSZeroRect];
    _sidebarOutline.style = NSTableViewStyleSourceList;
    _sidebarOutline.headerView = nil;
    _sidebarOutline.floatsGroupRows = NO;
    _sidebarOutline.allowsEmptySelection = NO;
    _sidebarOutline.rowSizeStyle = NSTableViewRowSizeStyleCustom;
    _sidebarOutline.accessibilityLabel = @"水杉输入法导航";
    NSTableColumn *sidebarColumn = [[NSTableColumn alloc] initWithIdentifier:@"MSIMESettingsSidebarColumn"];
    sidebarColumn.resizingMask = NSTableColumnAutoresizingMask;
    [_sidebarOutline addTableColumn:sidebarColumn];
    _sidebarOutline.outlineTableColumn = sidebarColumn;
    _sidebarOutline.dataSource = self;
    _sidebarOutline.delegate = self;
    [_sidebarOutline reloadData];
    // The groups are headings, not folders: every row is on screen from the start and stays there.
    [_sidebarOutline expandItem:nil expandChildren:YES];
    _sidebarScroll = [[NSScrollView alloc] initWithFrame:NSZeroRect];
    _sidebarScroll.documentView = _sidebarOutline;
    _sidebarScroll.hasVerticalScroller = YES;
    _sidebarScroll.autohidesScrollers = YES;
    _sidebarScroll.drawsBackground = NO;
    _sidebarScroll.translatesAutoresizingMaskIntoConstraints = NO;

    _searchResultsStack = [NSStackView stackViewWithViews:@[]];
    _searchResultsStack.orientation = NSUserInterfaceLayoutOrientationVertical;
    _searchResultsStack.alignment = NSLayoutAttributeLeading;
    _searchResultsStack.spacing = 1.0;
    _searchResultsStack.translatesAutoresizingMaskIntoConstraints = NO;
    // Fourteen results at 36pt do not fit a 520pt-tall sidebar, and pinned to its bottom edge they
    // broke a required constraint instead of scrolling.
    NSView *searchResultsDocument = [[MSIMEPreferencesDocumentView alloc] initWithFrame:NSZeroRect];
    searchResultsDocument.translatesAutoresizingMaskIntoConstraints = NO;
    [searchResultsDocument addSubview:_searchResultsStack];
    _searchResultsScroll = [[NSScrollView alloc] initWithFrame:NSZeroRect];
    _searchResultsScroll.documentView = searchResultsDocument;
    _searchResultsScroll.hasVerticalScroller = YES;
    _searchResultsScroll.autohidesScrollers = YES;
    _searchResultsScroll.drawsBackground = NO;
    _searchResultsScroll.translatesAutoresizingMaskIntoConstraints = NO;
    _searchResultsScroll.hidden = YES;
    [NSLayoutConstraint activateConstraints:@[
        [searchResultsDocument.widthAnchor constraintEqualToAnchor:_searchResultsScroll.contentView.widthAnchor],
        [searchResultsDocument.leadingAnchor constraintEqualToAnchor:_searchResultsScroll.contentView.leadingAnchor],
        [searchResultsDocument.topAnchor constraintEqualToAnchor:_searchResultsScroll.contentView.topAnchor],
        [_searchResultsStack.leadingAnchor constraintEqualToAnchor:searchResultsDocument.leadingAnchor constant:10.0],
        [_searchResultsStack.trailingAnchor constraintEqualToAnchor:searchResultsDocument.trailingAnchor constant:-10.0],
        [_searchResultsStack.topAnchor constraintEqualToAnchor:searchResultsDocument.topAnchor constant:6.0],
        [_searchResultsStack.bottomAnchor constraintEqualToAnchor:searchResultsDocument.bottomAnchor constant:-6.0],
    ]];

    NSViewController *sidebarController = [[NSViewController alloc] init];
    sidebarController.view = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, kSidebarWidth, 520)];
    [sidebarController.view addSubview:_sidebarScroll];
    [sidebarController.view addSubview:_searchResultsScroll];
    for (NSScrollView *list in @[_sidebarScroll, _searchResultsScroll])
        [NSLayoutConstraint activateConstraints:@[
            [list.leadingAnchor constraintEqualToAnchor:sidebarController.view.leadingAnchor],
            [list.trailingAnchor constraintEqualToAnchor:sidebarController.view.trailingAnchor],
            [list.topAnchor constraintEqualToAnchor:sidebarController.view.topAnchor],
            [list.bottomAnchor constraintEqualToAnchor:sidebarController.view.bottomAnchor],
        ]];

    // The detail side stays what it was: every page pinned edge to edge in one container, shown and
    // hidden rather than added and removed. An NSTabViewController would take the unselected pages
    // out of the view hierarchy, and the tests walk hidden pages to find the control they are about
    // (platforms/macos/tests/settings/PreferenceViewLookup.h).
    NSViewController *detailController = [[NSViewController alloc] init];
    NSView *pageContainer = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 600, 520)];
    detailController.view = pageContainer;
    for (NSView *page in _preferencePages) {
        [pageContainer addSubview:page];
        [NSLayoutConstraint activateConstraints:@[
            [page.leadingAnchor constraintEqualToAnchor:pageContainer.leadingAnchor],
            [page.trailingAnchor constraintEqualToAnchor:pageContainer.trailingAnchor],
            // The safe area is where the toolbar ends. Pinning to the container's own top instead is
            // what put the 20pt page title at y = -59, behind the titlebar and clipped.
            [page.topAnchor constraintEqualToAnchor:pageContainer.safeAreaLayoutGuide.topAnchor],
            [page.bottomAnchor constraintEqualToAnchor:pageContainer.bottomAnchor],
        ]];
    }

    _splitViewController = [[NSSplitViewController alloc] init];
    NSSplitViewItem *sidebarItem = [NSSplitViewItem sidebarWithViewController:sidebarController];
    sidebarItem.allowsFullHeightLayout = YES;
    sidebarItem.canCollapse = YES;
    sidebarItem.minimumThickness = kSidebarWidth;
    sidebarItem.maximumThickness = kSidebarMaxWidth;
    NSSplitViewItem *detailItem = [NSSplitViewItem splitViewItemWithViewController:detailController];
    // The page scrolls under the toolbar, so the line under the titlebar is the system's to draw
    // and to take away again — the cards used to run off the top of the window with nothing there.
    detailItem.titlebarSeparatorStyle = NSTitlebarSeparatorStyleAutomatic;
    [_splitViewController addSplitViewItem:sidebarItem];
    [_splitViewController addSplitViewItem:detailItem];
    _splitViewController.splitView.autosaveName = @"MSIMESettingsSplit";
    window.contentViewController = _splitViewController;
    // Handing a window a content view controller sizes it to that controller's fitting size, which
    // for a split view is its two minimum thicknesses — the window came up at its own minimum, one
    // card narrower and two cards shorter than it used to. The size the window opens at is a
    // decision of this window's, so it is restated after the assignment rather than left to the
    // solver.
    [window setContentSize:NSMakeSize(860, 640)];

    _searchField = [[NSSearchField alloc] initWithFrame:NSZeroRect];
    _searchField.placeholderString = @"搜索设置";
    _searchField.accessibilityLabel = @"搜索设置";
    _searchField.font = [NSFont systemFontOfSize:kBodyFontSize];
    _searchField.sendsWholeSearchString = NO;
    _searchField.sendsSearchStringImmediately = YES;
    _searchField.target = self;
    _searchField.action = @selector(searchChanged:);
    NSToolbar *toolbar = [[NSToolbar alloc] initWithIdentifier:@"MSIMESettingsToolbar"];
    toolbar.delegate = self;
    toolbar.allowsUserCustomization = NO;
    toolbar.displayMode = NSToolbarDisplayModeIconOnly;
    window.toolbar = toolbar;
    window.toolbarStyle = NSWindowToolbarStyleUnified;
    MSIMEInstallFindSettingsMenuItem(self, @selector(beginSettingsSearch:));
    self.window = window;
    // The account pane is a foreign view attached to this window; closing the window from its own
    // close button has to detach it the way the removed Close button used to.
    [NSNotificationCenter.defaultCenter addObserver:self
                                           selector:@selector(preferencesWindowWillClose:)
                                               name:NSWindowWillCloseNotification
                                             object:window];
    [self buildSearchIndex];
    // 设置窗口不是每次都从头看一遍的向导，上次停在哪一页，下次就该从哪一页接着看。
    const NSInteger rememberedPage = [self pageIndexForIdentifier:[_defaults stringForKey:LastSettingsPageKey]];
    const NSInteger initialPage = rememberedPage < 0 ? 0 : rememberedPage;
    [self showPreferencesPageAtIndex:initialPage navigationIndex:initialPage];
    [self refreshUpdateControls];
    [self refreshControls];
    // Restore first, centre only as the fallback: the two have to be asked in this order, because
    // attaching the autosave name saves the frame the window currently has, after which every
    // launch would "restore" whatever centring had just produced.
    if (![window setFrameUsingName:MSIMESettingsWindowFrameAutosaveName()]) [window center];
    [window setFrameAutosaveName:MSIMESettingsWindowFrameAutosaveName()];
}
- (void)preferencesWindowWillClose:(NSNotification *)notification {
    (void)notification;
    if (MSIMEAccountPaneClose != nullptr) MSIMEAccountPaneClose();
}

/// Walks the built pages once and records every label and checkbox title as something the search
/// field can find. Labels name a setting and sit beside its control, so the row they are in is
/// what the result scrolls to; a checkbox carries its own wording, so it is its own target.
- (void)buildSearchIndex {
    NSMutableArray<MSIMESettingsSearchEntry *> *entries = [NSMutableArray array];
    NSMutableSet<NSString *> *seen = [NSMutableSet set];
    for (NSInteger pageIndex = 0; pageIndex < (NSInteger)_preferencePages.count; ++pageIndex)
        [self collectSearchEntriesFrom:_preferencePages[pageIndex] page:pageIndex into:entries seen:seen];
    _searchIndex = entries;
}
- (void)collectSearchEntriesFrom:(NSView *)view
                            page:(NSInteger)pageIndex
                            into:(NSMutableArray<MSIMESettingsSearchEntry *> *)entries
                            seen:(NSMutableSet<NSString *> *)seen {
    for (NSView *child in view.subviews) {
        NSString *title = nil;
        NSView *target = nil;
        if ([child isKindOfClass:NSTextField.class]) {
            NSTextField *label = (NSTextField *)child;
            // An editable field holds a value rather than the name of one, and the page title just
            // repeats the sidebar item that is already one click away.
            if (!label.editable && !label.selectable && label.font.pointSize < 20.0) {
                title = label.stringValue;
                target = label.superview ?: label;
            }
        } else if ([child isKindOfClass:NSButton.class] && ((NSButton *)child).title.length > 0) {
            title = ((NSButton *)child).title;
            target = child;
        }
        if (title.length > 0) {
            NSString *key = [NSString stringWithFormat:@"%ld\n%@", (long)pageIndex, title];
            if (![seen containsObject:key]) {
                [seen addObject:key];
                MSIMESettingsSearchEntry *entry = [MSIMESettingsSearchEntry new];
                entry.title = title;
                entry.pageIndex = pageIndex;
                entry.row = target;
                [entries addObject:entry];
            }
        }
        [self collectSearchEntriesFrom:child page:pageIndex into:entries seen:seen];
    }
}
/// A query replaces the navigation with its matches rather than dropping a menu over the sidebar:
/// a menu takes key focus, so the next keystroke would go to the menu instead of the field.
- (void)searchChanged:(NSSearchField *)sender {
    for (NSView *result in [_searchResultsStack.arrangedSubviews copy]) [result removeFromSuperview];
    NSString *query = [sender.stringValue
        stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    if (query.length == 0) {
        _searchResultsScroll.hidden = YES;
        _sidebarScroll.hidden = NO;
        return;
    }
    _sidebarScroll.hidden = YES;
    _searchResultsScroll.hidden = NO;
    const NSUInteger limit = 14;
    for (NSUInteger index = 0; index < _searchIndex.count && _searchResultsStack.arrangedSubviews.count < limit; ++index) {
        MSIMESettingsSearchEntry *entry = _searchIndex[index];
        if ([entry.title rangeOfString:query options:NSCaseInsensitiveSearch].location == NSNotFound) continue;
        NSButton *result = [NSButton buttonWithTitle:entry.title target:self action:@selector(openSearchResult:)];
        result.bordered = NO;
        result.alignment = NSTextAlignmentLeft;
        result.tag = (NSInteger)index;
        NSMutableAttributedString *label = [[NSMutableAttributedString alloc]
            initWithString:entry.title
                attributes:@{
                    NSFontAttributeName : [NSFont systemFontOfSize:kBodyFontSize],
                    NSForegroundColorAttributeName : NSColor.labelColor,
                }];
        [label appendAttributedString:[[NSAttributedString alloc]
            initWithString:[@"\n" stringByAppendingString:_pageTitles[entry.pageIndex]]
                attributes:@{
                    NSFontAttributeName : [NSFont systemFontOfSize:11.0],
                    NSForegroundColorAttributeName : NSColor.secondaryLabelColor,
                }]];
        result.attributedTitle = label;
        result.cell.usesSingleLineMode = NO;
        result.cell.lineBreakMode = NSLineBreakByTruncatingTail;
        result.accessibilityLabel = [NSString stringWithFormat:@"%@，在%@页", entry.title, _pageTitles[entry.pageIndex]];
        [_searchResultsStack addArrangedSubview:result];
        [result.widthAnchor constraintEqualToAnchor:_searchResultsStack.widthAnchor].active = YES;
        [result.heightAnchor constraintEqualToConstant:36.0].active = YES;
    }
    if (_searchResultsStack.arrangedSubviews.count == 0) {
        NSTextField *empty = [NSTextField labelWithString:@"没有匹配的设置"];
        empty.font = [NSFont systemFontOfSize:kBodyFontSize];
        empty.textColor = NSColor.secondaryLabelColor;
        [_searchResultsStack addArrangedSubview:empty];
    }
}
- (void)openSearchResult:(NSButton *)sender {
    if (sender.tag < 0 || (NSUInteger)sender.tag >= _searchIndex.count) return;
    MSIMESettingsSearchEntry *entry = _searchIndex[sender.tag];
    [self showPreferencesPageAtIndex:entry.pageIndex navigationIndex:entry.pageIndex];
    NSView *row = entry.row;
    if (row == nil) return;
    // The page was hidden until a moment ago, so its frames mean nothing until layout settles.
    dispatch_async(dispatch_get_main_queue(), ^{
        NSScrollView *scrollView = row.enclosingScrollView;
        if (scrollView == nil) return;
        NSRect visible = [row convertRect:row.bounds toView:scrollView.documentView];
        [scrollView.documentView scrollRectToVisible:NSInsetRect(visible, 0.0, -60.0)];
        // A tinted box fading out behind the row, rather than animating the row's own layer: the
        // test binaries link AppKit but not QuartzCore, and `animator.alphaValue` needs neither.
        NSBox *flash = [[NSBox alloc] initWithFrame:row.bounds];
        flash.boxType = NSBoxCustom;
        flash.borderWidth = 0.0;
        flash.cornerRadius = 5.0;
        flash.fillColor = [[NSColor controlAccentColor] colorWithAlphaComponent:0.28];
        flash.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
        [row addSubview:flash positioned:NSWindowBelow relativeTo:nil];
        [NSAnimationContext runAnimationGroup:^(NSAnimationContext *context) {
            context.duration = 1.1;
            flash.animator.alphaValue = 0.0;
        } completionHandler:^{
            [flash removeFromSuperview];
        }];
    });
}
- (void)layoutChanged:(NSPopUpButton *)sender { self.vertical = sender.indexOfSelectedItem == 1; }
- (void)candidateFollowCursorChanged:(NSSwitch *)sender { self.candidateFollowCursor = sender.state == NSControlStateValueOn; }
- (void)transpositionChanged:(NSSwitch *)sender { self.autocorrectTransposition = sender.state == NSControlStateValueOn; }
- (void)neighborChanged:(NSSwitch *)sender { self.autocorrectNeighbor = sender.state == NSControlStateValueOn; }
- (void)candidateLearningChanged:(NSSwitch *)sender { self.candidateLearningEnabled = sender.state == NSControlStateValueOn; }
- (void)frequencyModeChanged:(NSPopUpButton *)sender { self.frequencyAdjustmentMode = FrequencyModes()[sender.indexOfSelectedItem]; }
- (void)frequencyTriggerChanged:(NSPopUpButton *)sender { self.frequencyTriggerCount = sender.indexOfSelectedItem + 1; }
- (void)frequencyStepChanged:(NSPopUpButton *)sender { self.frequencyLinearStep = sender.indexOfSelectedItem + 1; }
- (void)cloudCandidatesChanged:(NSSwitch *)sender { self.cloudCandidates = sender.state == NSControlStateValueOn; }
- (void)candidateTranslationsChanged:(NSSwitch *)sender { self.candidateTranslations = sender.state == NSControlStateValueOn; }
- (void)candidateEnglishGlossChanged:(NSSwitch *)sender { self.candidateEnglishGloss = sender.state == NSControlStateValueOn; }
- (void)quanpinHelpcodeChanged:(NSSwitch *)sender { self.quanpinHelpcodeEnabled = sender.state == NSControlStateValueOn; }
- (void)shuangpinHelpcodeChanged:(NSSwitch *)sender { self.shuangpinHelpcodeEnabled = sender.state == NSControlStateValueOn; }
- (void)profileChanged:(NSPopUpButton *)sender { self.shuangpinProfile = @[@"xiaohe", @"ziranma", @"shoudao", @"microsoft"][sender.indexOfSelectedItem]; }
- (void)preeditChanged:(NSPopUpButton *)sender { self.shuangpinPreeditUsesRaw = sender.indexOfSelectedItem == 1; }
- (void)inputModeShortcutChanged:(NSSwitch *)sender { self.inputModeShortcut = sender.state == NSControlStateValueOn; }
- (void)defaultImeModeChanged:(NSPopUpButton *)sender { self.defaultImeMode = sender.indexOfSelectedItem == 1 ? @"english" : @"chinese"; }
- (void)imeModeScopeChanged:(NSPopUpButton *)sender { self.imeModeScope = sender.indexOfSelectedItem == 1 ? @"global" : @"app"; }
- (void)shiftTapShortcutChanged:(NSSwitch *)sender { self.shiftTapShortcut = sender.state == NSControlStateValueOn; }
- (void)controlTapShortcutChanged:(NSSwitch *)sender { self.controlTapShortcut = sender.state == NSControlStateValueOn; }
- (void)controlOptionSpaceShortcutChanged:(NSSwitch *)sender { self.controlOptionSpaceShortcut = sender.state == NSControlStateValueOn; }
- (void)characterSetShortcutChanged:(NSSwitch *)sender { self.characterSetShortcut = sender.state == NSControlStateValueOn; }
- (void)fullWidthChanged:(NSSwitch *)sender { self.fullWidthInput = sender.state == NSControlStateValueOn; }
- (void)keymapChanged:(NSSwitch *)sender { self.shuangpinKeymap = sender.state == NSControlStateValueOn; }
- (void)wubiChanged:(NSSwitch *)sender { self.wubiAutoCommitUnique = sender.state == NSControlStateValueOn; }
- (void)punctuationChanged:(NSSwitch *)sender { self.chinesePunctuation = sender.state == NSControlStateValueOn; }
- (void)smartPunctuationChanged:(NSSwitch *)sender { self.smartPunctuation = sender.state == NSControlStateValueOn; }
- (void)smartPunctuationRepeatChanged:(NSSwitch *)sender { self.smartPunctuationRepeatToChinese = sender.state == NSControlStateValueOn; }
- (void)pairedPunctuationChanged:(NSSwitch *)sender { self.pairedPunctuation = sender.state == NSControlStateValueOn; }
- (void)punctuationLockChanged:(NSPopUpButton *)sender { self.punctuationLock = @[@"follow", @"chinese", @"english"][sender.indexOfSelectedItem]; }
- (void)mixedEnglishChanged:(NSSwitch *)sender { self.mixedEnglishInput = sender.state == NSControlStateValueOn; }
- (void)mixedEnglishPrefixChanged:(NSPopUpButton *)sender { self.mixedEnglishMinimumPrefix = sender.indexOfSelectedItem + 1; }
- (void)mixedEmojiChanged:(NSSwitch *)sender { self.mixedEmojiInput = sender.state == NSControlStateValueOn; }
- (void)mixedKaomojiChanged:(NSSwitch *)sender { self.mixedKaomojiInput = sender.state == NSControlStateValueOn; }
- (void)toolbarChanged:(NSSwitch *)sender { self.floatingToolbarEnabled = sender.state == NSControlStateValueOn; }
- (void)toolbarPunctuationChanged:(NSButton *)sender { self.floatingToolbarPunctuation = sender.state == NSControlStateValueOn; }
- (void)toolbarFullWidthChanged:(NSButton *)sender { self.floatingToolbarFullWidth = sender.state == NSControlStateValueOn; }
- (void)toolbarCharacterSetChanged:(NSButton *)sender { self.floatingToolbarCharacterSet = sender.state == NSControlStateValueOn; }
- (void)toolbarEmojiChanged:(NSButton *)sender { self.floatingToolbarEmoji = sender.state == NSControlStateValueOn; }
- (void)toolbarScreenKeyboardChanged:(NSButton *)sender { self.floatingToolbarScreenKeyboard = sender.state == NSControlStateValueOn; }
- (void)toolbarSettingsChanged:(NSButton *)sender { self.floatingToolbarSettings = sender.state == NSControlStateValueOn; }
- (void)toolbarScaleChanged:(NSPopUpButton *)sender { self.floatingToolbarScalePercent = [@[@75, @100, @125, @150][sender.indexOfSelectedItem] integerValue]; }
- (void)toolbarFontSizeChanged:(NSPopUpButton *)sender { self.floatingToolbarFontSize = 16 + sender.indexOfSelectedItem * 2; }
- (MetasequoiaSkinSettingsView *)ensureSkinSettingsView {
    (void)self.window;  // The page container is built with the rest of the pages.
    if (_skinSettingsView != nil) return _skinSettingsView;
    _skinSettingsView = [[MetasequoiaSkinSettingsView alloc] initWithFrame:NSZeroRect preferences:self];
    [_skinPageContainer addSubview:_skinSettingsView];
    [NSLayoutConstraint activateConstraints:@[
        [_skinSettingsView.leadingAnchor constraintEqualToAnchor:_skinPageContainer.leadingAnchor],
        [_skinSettingsView.trailingAnchor constraintEqualToAnchor:_skinPageContainer.trailingAnchor],
        [_skinSettingsView.topAnchor constraintEqualToAnchor:_skinPageContainer.topAnchor],
        [_skinSettingsView.bottomAnchor constraintEqualToAnchor:_skinPageSharedEntry.topAnchor constant:-6.0],
    ]];
    return _skinSettingsView;
}
- (NSView *)skinSettingsView {
    MetasequoiaSkinSettingsView *view = [self ensureSkinSettingsView];
    [view reload];
    return view;
}
- (void)showSkinCatalog:(id)sender {
    (void)sender;
    __weak MSIMEAppearancePreferences *weakSelf = self;
    // The native fallback used to open a second window holding the same browser the 皮肤 page now
    // is, so falling back means showing that page rather than a duplicate of it.
    MSIMEOpenDesktopSettings(MSIMEDesktopSettingsPage::Skin, [self desktopSettingsWorkspace], ^{
        MSIMEAppearancePreferences *strongSelf = weakSelf;
        if (strongSelf == nil) return;
        [[strongSelf ensureSkinSettingsView] reload];
        [strongSelf showPreferencesPageAtIndex:kSkinPageIndex navigationIndex:kSkinPageIndex];
        [strongSelf showWindow:nil];
    });
}
- (void)showDictionary:(id)sender {
    (void)sender;
    __weak MSIMEAppearancePreferences *weakSelf = self;
    MSIMEOpenDesktopRoute(@"settings:dictionary", NSWorkspace.sharedWorkspace, ^{
        MSIMEAppearancePreferences *strongSelf = weakSelf;
        if (!strongSelf) return;
        NSDictionary *options = MSIMELoadRuntimeOptions();
        if (![options isKindOfClass:NSDictionary.class]) {
            NSAlert *alert = [NSAlert new];
            alert.messageText = @"词库管理暂不可用";
            alert.informativeText = @"请先激活输入法，再从输入法菜单打开词库管理。";
            [alert addButtonWithTitle:@"好"];
            [alert runModal];
            return;
        }
        strongSelf->_dictionaryWindow = [[MSIMEDictionaryWindowController alloc] initWithOptions:options];
        [strongSelf->_dictionaryWindow showWindow:nil];
        [NSApp activateIgnoringOtherApps:YES];
    });
}
- (void)togglePreviewTheme:(id)sender { (void)sender; [_preview toggleForcedTheme]; }
- (void)togglePreviewShowcase:(NSButton *)sender { [_preview setShowsLayoutShowcase:sender.state == NSControlStateValueOn]; }
- (void)selectPreferencesPage:(id)sender {
    NSButton *button = [sender isKindOfClass:NSButton.class] ? (NSButton *)sender : nil;
    const NSInteger index = button == nil ? 0 : button.tag;
    [self showPreferencesPageAtIndex:index navigationIndex:index];
}
/// The page a stable identifier names, or -1 when nothing is named — an identifier written by a
/// version that had a page this one does not is not an error, it is a page that went away.
- (NSInteger)pageIndexForIdentifier:(NSString *)identifier {
    if (identifier.length == 0) return -1;
    const NSUInteger index = [_pageIdentifiers indexOfObject:identifier];
    return index == NSNotFound ? -1 : (NSInteger)index;
}
- (BOOL)showSettingsPageWithIdentifier:(NSString *)identifier {
    (void)self.window;  // The page list is built with the window; a deep link can arrive before it.
    const NSInteger pageIndex = [self pageIndexForIdentifier:identifier];
    if (pageIndex < 0) return NO;
    [self showPreferencesPageAtIndex:pageIndex navigationIndex:pageIndex];
    return YES;
}
- (void)showPreferencesPageAtIndex:(NSInteger)pageIndex navigationIndex:(NSInteger)navigationIndex {
    _selectedPageIndex = pageIndex;
    if (pageIndex >= 0 && pageIndex < (NSInteger)_pageIdentifiers.count)
        [_defaults setObject:_pageIdentifiers[pageIndex] forKey:LastSettingsPageKey];
    if (pageIndex == kSkinPageIndex) [self ensureSkinSettingsView];
    if (pageIndex == kVoicePageIndex) [_voiceSettingsView reloadSettings];
    for (NSInteger index = 0; index < (NSInteger)_preferencePages.count; ++index)
        _preferencePages[index].hidden = index != pageIndex;
    [self selectSidebarRowForPageAtIndex:navigationIndex];
    // The window's chrome says which page you are on, which is what the title bar is for and what
    // this window has never used it for.
    if (navigationIndex >= 0 && navigationIndex < (NSInteger)_pageTitles.count)
        [super window].title = _pageTitles[navigationIndex];
    if (pageIndex == kAccountPageIndex && MSIMEAccountPaneAttach != nullptr)
        MSIMEAccountPaneAttach(self.window);
    else if (MSIMEAccountPaneClose != nullptr)
        MSIMEAccountPaneClose();
}
- (void)selectSidebarRowForPageAtIndex:(NSInteger)navigationIndex {
    if (_sidebarOutline == nil) return;
    for (MSIMESettingsSidebarItem *group in _sidebarGroups)
        for (MSIMESettingsSidebarItem *member in group.children) {
            if (member.pageIndex != navigationIndex) continue;
            const NSInteger row = [_sidebarOutline rowForItem:member];
            if (row < 0 || row == _sidebarOutline.selectedRow) return;
            _updatingSidebarSelection = YES;
            [_sidebarOutline selectRowIndexes:[NSIndexSet indexSetWithIndex:(NSUInteger)row]
                         byExtendingSelection:NO];
            [_sidebarOutline scrollRowToVisible:row];
            _updatingSidebarSelection = NO;
            return;
        }
}

#pragma mark - 侧栏源列表

- (NSInteger)outlineView:(NSOutlineView *)outlineView numberOfChildrenOfItem:(id)item {
    (void)outlineView;
    if (item == nil) return (NSInteger)_sidebarGroups.count;
    return (NSInteger)[(MSIMESettingsSidebarItem *)item children].count;
}
- (id)outlineView:(NSOutlineView *)outlineView child:(NSInteger)index ofItem:(id)item {
    (void)outlineView;
    if (item == nil) return _sidebarGroups[(NSUInteger)index];
    return [(MSIMESettingsSidebarItem *)item children][(NSUInteger)index];
}
- (BOOL)outlineView:(NSOutlineView *)outlineView isItemExpandable:(id)item {
    (void)outlineView;
    return [(MSIMESettingsSidebarItem *)item children].count > 0;
}
- (BOOL)outlineView:(NSOutlineView *)outlineView isGroupItem:(id)item {
    (void)outlineView;
    return [(MSIMESettingsSidebarItem *)item children].count > 0;
}
- (BOOL)outlineView:(NSOutlineView *)outlineView shouldSelectItem:(id)item {
    (void)outlineView;
    return [(MSIMESettingsSidebarItem *)item children].count == 0;
}
/// The four groups are the window's structure, not something to fold away: collapsing 显示 would
/// hide three of the eleven pages behind a triangle nothing else in the window mentions.
- (BOOL)outlineView:(NSOutlineView *)outlineView shouldCollapseItem:(id)item {
    (void)outlineView;
    (void)item;
    return NO;
}
- (BOOL)outlineView:(NSOutlineView *)outlineView shouldShowOutlineCellForItem:(id)item {
    (void)outlineView;
    (void)item;
    return NO;
}
- (CGFloat)outlineView:(NSOutlineView *)outlineView heightOfRowByItem:(id)item {
    (void)outlineView;
    (void)item;
    return kSidebarRowHeight;
}
- (NSView *)outlineView:(NSOutlineView *)outlineView
     viewForTableColumn:(NSTableColumn *)tableColumn
                   item:(id)item {
    (void)tableColumn;
    MSIMESettingsSidebarItem *entry = item;
    const BOOL group = entry.children.count > 0;
    NSUserInterfaceItemIdentifier identifier = group ? @"MSIMESettingsSidebarGroupCell" : @"MSIMESettingsSidebarCell";
    NSTableCellView *cell = [outlineView makeViewWithIdentifier:identifier owner:self];
    if (cell == nil) {
        cell = [[NSTableCellView alloc] initWithFrame:NSZeroRect];
        cell.identifier = identifier;
        NSTextField *label = [NSTextField labelWithString:@""];
        label.font = [NSFont systemFontOfSize:kBodyFontSize];
        // A sidebar narrow enough to be dragged to 204pt truncates 悬浮工具栏 rather than drawing it
        // past its own edge.
        label.lineBreakMode = NSLineBreakByTruncatingTail;
        label.translatesAutoresizingMaskIntoConstraints = NO;
        [cell addSubview:label];
        cell.textField = label;
        [label.centerYAnchor constraintEqualToAnchor:cell.centerYAnchor].active = YES;
        [label.trailingAnchor constraintLessThanOrEqualToAnchor:cell.trailingAnchor].active = YES;
        if (group) {
            [label.leadingAnchor constraintEqualToAnchor:cell.leadingAnchor].active = YES;
        } else {
            NSImageView *icon = [[NSImageView alloc] initWithFrame:NSZeroRect];
            icon.imageScaling = NSImageScaleProportionallyDown;
            icon.translatesAutoresizingMaskIntoConstraints = NO;
            [cell addSubview:icon];
            cell.imageView = icon;
            [NSLayoutConstraint activateConstraints:@[
                [icon.leadingAnchor constraintEqualToAnchor:cell.leadingAnchor],
                [icon.centerYAnchor constraintEqualToAnchor:cell.centerYAnchor],
                [icon.widthAnchor constraintEqualToConstant:18.0],
                [label.leadingAnchor constraintEqualToAnchor:icon.trailingAnchor constant:6.0],
            ]];
        }
    }
    cell.textField.stringValue = entry.title;
    cell.imageView.image = entry.symbolName.length > 0
        ? [NSImage imageWithSystemSymbolName:entry.symbolName accessibilityDescription:nil]
        : nil;
    return cell;
}
- (void)outlineViewSelectionDidChange:(NSNotification *)notification {
    (void)notification;
    if (_updatingSidebarSelection) return;
    MSIMESettingsSidebarItem *item = [_sidebarOutline itemAtRow:_sidebarOutline.selectedRow];
    if (item == nil || item.children.count > 0) return;
    [self showPreferencesPageAtIndex:item.pageIndex navigationIndex:item.pageIndex];
}

#pragma mark - 工具栏

- (NSArray<NSToolbarItemIdentifier> *)toolbarDefaultItemIdentifiers:(NSToolbar *)toolbar {
    (void)toolbar;
    return @[
        NSToolbarToggleSidebarItemIdentifier, MSIMESettingsSearchItemIdentifier,
        MSIMESettingsSeparatorItemIdentifier, NSToolbarFlexibleSpaceItemIdentifier,
        MSIMESettingsMoreItemIdentifier,
    ];
}
- (NSArray<NSToolbarItemIdentifier> *)toolbarAllowedItemIdentifiers:(NSToolbar *)toolbar {
    return [self toolbarDefaultItemIdentifiers:toolbar];
}
- (NSToolbarItem *)toolbar:(NSToolbar *)toolbar
        itemForItemIdentifier:(NSToolbarItemIdentifier)identifier
    willBeInsertedIntoToolbar:(BOOL)inserted {
    (void)toolbar;
    (void)inserted;
    if ([identifier isEqualToString:MSIMESettingsSearchItemIdentifier]) {
        _searchToolbarItem = [[NSSearchToolbarItem alloc] initWithItemIdentifier:identifier];
        _searchToolbarItem.searchField = _searchField;
        _searchToolbarItem.resignsFirstResponderWithCancel = YES;
        // Wide enough that the sidebar's own width is what the field spans, which is where a Mac
        // settings window puts its search field.
        _searchToolbarItem.preferredWidthForSearchField = kSidebarWidth - 24.0;
        return _searchToolbarItem;
    }
    if ([identifier isEqualToString:MSIMESettingsSeparatorItemIdentifier])
        return [NSTrackingSeparatorToolbarItem trackingSeparatorToolbarItemWithIdentifier:identifier
                                                                                splitView:_splitViewController.splitView
                                                                             dividerIndex:0];
    if ([identifier isEqualToString:MSIMESettingsMoreItemIdentifier]) {
        NSMenuToolbarItem *more = [[NSMenuToolbarItem alloc] initWithItemIdentifier:identifier];
        more.image = [NSImage imageWithSystemSymbolName:@"ellipsis.circle" accessibilityDescription:@"更多设置操作"];
        more.label = @"更多";
        more.toolTip = @"更多设置操作";
        NSMenu *menu = [[NSMenu alloc] initWithTitle:@"更多"];
        // The global reset used to sit in a footer strip that cost all thirteen pages 42pt, one row
        // above the red 卸载… button on 关于. It is an action taken once, so it belongs in a menu.
        NSMenuItem *restore = [[NSMenuItem alloc] initWithTitle:@"恢复全部设置…"
                                                         action:@selector(restoreAllDefaults:)
                                                  keyEquivalent:@""];
        restore.target = self;
        [menu addItem:restore];
        more.menu = menu;
        return more;
    }
    return nil;
}
/// ⌘F and the toolbar's own field are the same interaction, so the menu item asks the item to begin
/// it rather than reaching for the field and making it first responder behind the item's back.
- (void)beginSettingsSearch:(id)sender {
    (void)sender;
    [_searchToolbarItem beginSearchInteraction];
}
- (void)schemeRadioChanged:(NSButton *)sender {
    self.inputScheme = @[@"quanpin", @"shuangpin", @"wubi", @"japanese"][sender.tag];
}
- (void)showBackendAccount:(id)sender {
    (void)sender;
    if (MSIMEAccountPaneAttach != nullptr) {
        [self showPreferencesPageAtIndex:kAccountPageIndex navigationIndex:kAccountPageIndex];
        MSIMEAccountPaneAttach(self.window);
    } else {
        MSIMEOpenBackendAccount(NSClassFromString(@"MSIMEBackendAccountWindow"));
    }
}
- (void)showSupport:(id)sender {
    (void)sender;
    Class supportClass = NSClassFromString(@"MSIMESupportWindowController");
    if (![supportClass respondsToSelector:@selector(sharedController)]) return;
    [[supportClass sharedController] showWindow:self];
    [NSApp activateIgnoringOtherApps:YES];
}
- (void)openProductWebsite:(id)sender {
    (void)sender;
    [NSWorkspace.sharedWorkspace openURL:[NSURL URLWithString:@"https://msime.app"]];
}
- (void)uninstallInputSource:(id)sender {
    (void)sender;
    if (msime_macos_uninstall_input_source == nullptr) return;
    NSAlert *confirmation = [NSAlert new];
    confirmation.alertStyle = NSAlertStyleWarning;
    confirmation.messageText = @"确认卸载水杉输入法？";
    confirmation.informativeText = _removeUserDataButton.state == NSControlStateValueOn
        ? @"输入法会移到废纸篓，并删除本机词库、学习记录、偏好与语音密钥。"
        : @"输入法会移到废纸篓；本机词库、学习记录和偏好会保留。";
    [confirmation addButtonWithTitle:@"确认卸载"];
    [confirmation addButtonWithTitle:@"取消"];
    if ([confirmation runModal] != NSAlertFirstButtonReturn) return;

    NSFileManager *fileManager = NSFileManager.defaultManager;
    NSURL *library = [fileManager URLForDirectory:NSLibraryDirectory
                                          inDomain:NSUserDomainMask
                                 appropriateForURL:nil
                                            create:NO
                                             error:nil];
    NSURL *inputMethods = [library URLByAppendingPathComponent:@"Input Methods" isDirectory:YES];
    NSURL *bundle = [inputMethods URLByAppendingPathComponent:@"水杉输入法.app" isDirectory:YES];
    // A copy installed by the previous preview build may be the one that is there.
    // Uninstalling has to remove what exists rather than a path that was never written; both carry
    // the same bundle identifier, so only one of them can be installed.
    if (![NSFileManager.defaultManager fileExistsAtPath:bundle.path]) {
        NSURL *other = [inputMethods URLByAppendingPathComponent:@"水杉输入法（预览）.app" isDirectory:YES];
        if ([NSFileManager.defaultManager fileExistsAtPath:other.path]) bundle = other;
    }
    NSDictionary *runtime = MSIMELoadRuntimeOptions();
    NSString *configuredState = [runtime[ @"preferences_directory"] isKindOfClass:NSString.class]
        && [runtime[@"preferences_directory"] isAbsolutePath] ? runtime[@"preferences_directory"] : nil;
    NSURL *support = [fileManager URLForDirectory:NSApplicationSupportDirectory
                                           inDomain:NSUserDomainMask
                                  appropriateForURL:nil
                                             create:NO
                                              error:nil];
    NSURL *defaultState = [support URLByAppendingPathComponent:@"app.msime.client" isDirectory:YES];
    NSString *userData = configuredState ?: defaultState.path;
    BOOL ok = msime_macos_uninstall_input_source(bundle.path.fileSystemRepresentation,
                                                  userData.fileSystemRepresentation,
                                                  "app.msime.inputmethod.MetasequoiaIME",
                                                  _removeUserDataButton.state == NSControlStateValueOn);
    if (!ok) {
        NSAlert *failure = [NSAlert new];
        failure.alertStyle = NSAlertStyleCritical;
        failure.messageText = @"卸载未能完成";
        failure.informativeText = @"输入法没有移到废纸篓；本机数据未被删除。";
        [failure runModal];
        return;
    }
    [NSApp terminate:nil];
}
- (void)checkForUpdates:(id)sender { [_updateController checkForUpdates:sender]; }
- (void)refreshUpdateControls {
    NSString *version = [NSBundle.mainBundle objectForInfoDictionaryKey:@"CFBundleShortVersionString"];
    _versionLabel.stringValue = version.length == 0 ? @"开发构建" : [NSString stringWithFormat:@"v%@", version];
    // Without the update controller linked in, the page still renders and simply reports that
    // this build cannot check; it must not claim automatic checks are on.
    const BOOL automatic = [_updateController automaticallyChecksForUpdates];
    _automaticUpdateLabel.stringValue = automatic ? @"已开启自动检查" : @"自动检查已关闭";
    _updatePageButton.enabled = [_updateController canCheckForUpdates];
}
// Clears only this host's own preference domain, by an explicit key list, the way the upstream
// window does. It never touches the Apple product's domain or the user dictionary.
- (NSArray<NSString *> *)restorableKeys {
    return @[
        LayoutKey, CandidateFollowCursorKey, InputModeHUDKey, SchemeKey, ShuangpinProfileKey,
        ShuangpinPreeditKey, LocalModesKey, HelpcodeKey, HelpcodeOptionsKey, QuanpinHelpcodeKey,
        ShuangpinHelpcodeKey, KeymapKey, WubiKey, InputModeShortcutKey, ShiftTapShortcutKey,
        ControlTapShortcutKey, ControlOptionSpaceShortcutKey, CharacterSetShortcutKey,
        FullWidthShortcutKey, FloatingToolbarKey, FloatingToolbarOptionsKey,
    ];
}
/// Which of those keys the page in front of the user owns. Upstream offers one button that clears
/// every one of them at once and asks nothing first, so tidying up one page costs the other twelve.
- (NSArray<NSString *> *)restorableKeysForPageAtIndex:(NSInteger)pageIndex {
    switch (pageIndex) {
        case 0: return @[SchemeKey, ShuangpinProfileKey, ShuangpinPreeditKey, KeymapKey, WubiKey];
        case 1: return @[LayoutKey, CandidateFollowCursorKey, InputModeHUDKey];
        case 5: return @[HelpcodeKey, HelpcodeOptionsKey, QuanpinHelpcodeKey, ShuangpinHelpcodeKey];
        case 6: return @[
            InputModeShortcutKey, ShiftTapShortcutKey, ControlTapShortcutKey,
            ControlOptionSpaceShortcutKey, CharacterSetShortcutKey, FullWidthShortcutKey,
        ];
        case 7: return @[FloatingToolbarKey, FloatingToolbarOptionsKey];
        case 12: return @[LocalModesKey];
        default: return @[];
    }
}
- (void)removeStoredKeys:(NSArray<NSString *> *)keys {
    for (NSString *key in keys) [_defaults removeObjectForKey:key];
    [self refreshControls];
    [NSNotificationCenter.defaultCenter postNotificationName:MSIMEAppearanceDidChangeNotification object:self];
}
/// The whole window at once, from the toolbar's ⋯ menu. Per-section restore — the one a user
/// actually reaches for — is the section label's own affair and is not built yet, so this is
/// deliberately the blunt instrument and says so.
- (void)restoreAllDefaults:(id)sender {
    (void)sender;
    NSAlert *alert = [NSAlert new];
    alert.alertStyle = NSAlertStyleWarning;
    alert.messageText = @"恢复全部设置？";
    alert.informativeText = @"所有页的设置都会恢复为默认值。词库、学习记录、账号与语音密钥不受影响。";
    // Cancel is added first so it is the default button: the other one throws settings away, and a
    // destructive action should not be what Return picks.
    [alert addButtonWithTitle:@"取消"];
    [alert addButtonWithTitle:@"恢复全部设置"];
    if ([alert runModal] == NSAlertFirstButtonReturn) return;
    [self removeStoredKeys:[self restorableKeys]];
}
- (void)restoreDefaults:(id)sender {
    (void)sender;
    NSArray<NSString *> *pageKeys = [self restorableKeysForPageAtIndex:_selectedPageIndex];
    NSString *pageTitle = _selectedPageIndex >= 0 && _selectedPageIndex < (NSInteger)_pageTitles.count
        ? _pageTitles[_selectedPageIndex] : @"";
    NSAlert *alert = [NSAlert new];
    alert.alertStyle = NSAlertStyleWarning;
    alert.messageText = @"恢复默认设置？";
    alert.informativeText = pageKeys.count > 0
        ? [NSString stringWithFormat:@"「%@」页的设置会恢复为默认值。词库、学习记录、账号与语音密钥不受影响。", pageTitle]
        : @"这一页没有保存在本机的设置。恢复全部会重置其它页的选项；词库、学习记录、账号与语音密钥不受影响。";
    // Cancel is added first so it is the default button: the other two throw away settings, and a
    // destructive action should not be what Return picks.
    [alert addButtonWithTitle:@"取消"];
    if (pageKeys.count > 0) [alert addButtonWithTitle:[NSString stringWithFormat:@"恢复「%@」", pageTitle]];
    [alert addButtonWithTitle:@"恢复全部设置"];
    const NSModalResponse response = [alert runModal];
    if (response == NSAlertFirstButtonReturn) return;
    const BOOL restoreEverything = pageKeys.count == 0 || response == NSAlertThirdButtonReturn;
    [self removeStoredKeys:restoreEverything ? [self restorableKeys] : pageKeys];
}
- (void)showWindow:(id)sender { [self reloadSkins]; [super showWindow:sender]; }
- (void)pageShortcutChanged:(NSPopUpButton *)sender { self.pageShortcut = sender.indexOfSelectedItem; }
- (void)navigationChanged:(NSButton *)sender { [self setNavigation:sender.identifier enabled:sender.state == NSControlStateValueOn]; }
- (void)wordCharacterChanged:(id)sender {
    (void)sender;
    [self setWordCharacterEnabled:_wordCharacterToggle.state == NSControlStateValueOn keys:_wordCharacterKeys.indexOfSelectedItem == 1 ? @"minus_equal" : @"brackets"];
}
- (void)pageSizeChanged:(NSPopUpButton *)sender {
    self.pageSize = msime::mac::CandidatePageSizeForOptionIndex(MAX(0, sender.indexOfSelectedItem));
}
- (void)fontChanged:(NSPopUpButton *)sender {
    NSInteger index = sender.indexOfSelectedItem;
    self.fontSize = index >= 0 && index <= 20 ? index + 12 : 18;
}
- (void)englishFontFamilyChanged:(NSComboBox *)sender {
    self.candidateEnglishFont = sender.stringValue.length ? sender.stringValue : nil;
}
- (void)fontFamilyChanged:(NSComboBox *)sender { self.fontFamily = sender.stringValue; }
- (void)textColorChanged:(NSTextField *)sender { self.candidateTextColor = sender.stringValue.length ? sender.stringValue : nil; }
- (void)resetTextColor:(id)sender { (void)sender; self.candidateTextColor = nil; }
- (void)textColorWellChanged:(NSColorWell *)sender {
    NSColor *color = [sender.color colorUsingColorSpace:NSColorSpace.sRGBColorSpace];
    if (!color) return;
    auto channel = [](CGFloat value) { return (unsigned int)lround(MAX(0.0, MIN(1.0, value)) * 255); };
    self.candidateTextColor = [NSString stringWithFormat:@"#%02X%02X%02X", channel(color.redComponent), channel(color.greenComponent), channel(color.blueComponent)];
}
- (void)addFallbackFont:(id)sender {
    (void)sender;
    NSString *family = _fallbackFamilyControl.stringValue;
    if (!ValidFontFamily(family) || self.fallbackFonts.count >= 32) { NSBeep(); return; }
    self.fallbackFonts = [self.fallbackFonts arrayByAddingObject:family];
    [_fallbackList selectItemAtIndex:self.fallbackFonts.count - 1];
    _fallbackFamilyControl.stringValue = @"";
}
- (void)removeFallbackFont:(id)sender {
    (void)sender;
    NSInteger index = _fallbackList.indexOfSelectedItem;
    if (index < 0 || (NSUInteger)index >= self.fallbackFonts.count) return;
    NSMutableArray *fonts = [self.fallbackFonts mutableCopy];
    [fonts removeObjectAtIndex:index];
    self.fallbackFonts = fonts;
}
- (void)moveFallbackFontBy:(NSInteger)delta {
    NSInteger index = _fallbackList.indexOfSelectedItem;
    NSInteger next = index + delta;
    if (index < 0 || next < 0 || (NSUInteger)index >= self.fallbackFonts.count || (NSUInteger)next >= self.fallbackFonts.count) return;
    NSMutableArray *fonts = [self.fallbackFonts mutableCopy];
    [fonts exchangeObjectAtIndex:index withObjectAtIndex:next];
    self.fallbackFonts = fonts;
    [_fallbackList selectItemAtIndex:next];
}
- (void)moveFallbackFontUp:(id)sender { (void)sender; [self moveFallbackFontBy:-1]; }
- (void)moveFallbackFontDown:(id)sender { (void)sender; [self moveFallbackFontBy:1]; }
- (void)preeditFontChanged:(NSPopUpButton *)sender { self.preeditFontSize = sender.indexOfSelectedItem + 12; }
- (void)candidatePreeditChanged:(NSPopUpButton *)sender { self.showsCandidatePreedit = sender.indexOfSelectedItem == 0; }
@end
