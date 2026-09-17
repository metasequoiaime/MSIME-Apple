#import "AppearancePreferences.h"
#import "CandidateSkinPreviewView.h"
#import "SkinSettingsView.h"
#import "CloudAppearanceSettings.h"
#import "TranslationSettingsWindow.h"
#import "DesktopSettingsLauncher.h"
#import "AISettingsWindow.h"
#import "SharedVoicePreferences.h"
#import "UpdateController.h"
#import "BackendAccountEntry.h"
#import "SupportWindowController.h"
#import "VoiceSettings.h"
#include "ShuangpinProfileNames.h"
#include "CandidatePageSize.h"

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
static NSArray<NSString *> *HelpcodeSchemas() { return @[@"lantian", @"ziranma", @"shouyou2_0", @"shouyouplus", @"xiaohe"]; }
static BOOL ValidHelpcodeOption(NSString *key, id value) {
    return [key isEqual:@"schema"] ? [HelpcodeSchemas() containsObject:value] :
        ([key isEqual:@"show_in_candidate_window"] && LocalModeBoolean(value));
}
static NSString *const QuanpinHelpcodeKey = @"MSIMEClientQuanpinHelpcodeEnabled";
static NSString *const ShuangpinHelpcodeKey = @"MSIMEClientShuangpinHelpcodeEnabled";
static NSString *const KeymapKey = @"MSIMEClientShuangpinKeymap";
static NSString *const WubiKey = @"MSIMEClientWubiAutoCommitUnique";
static NSString *const InputModeShortcutKey = @"MSIMEClientInputModeShortcut";
static NSString *const ShiftTapShortcutKey = @"MSIMEClientShiftTapShortcut";
static NSString *const ControlTapShortcutKey = @"MSIMEClientControlTapShortcut";
static NSString *const ControlOptionSpaceShortcutKey = @"MSIMEClientControlOptionSpaceShortcut";
static NSString *const CharacterSetShortcutKey = @"MSIMEClientCharacterSetShortcut";
static NSString *const FloatingToolbarKey = @"MSIMEClientFloatingToolbarEnabled";
static NSString *const FloatingToolbarOptionsKey = @"MSIMEClientFloatingToolbarOptions";
static NSArray<NSString *> *FloatingToolbarComponentKeys() {
    return @[@"english_mode", @"punctuation", @"fullwidth", @"character_set", @"emoji", @"screen_keyboard", @"settings"];
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
// cd36eba4d2572f747785450959332c7f68f4715c, platforms/macos/src/PreferencesWindowController.mm.
// A 220pt sidebar of grouped navigation buttons drives a page container; each page is a scroll
// view whose content is section labels above bordered cards of label/control rows. Geometry,
// fonts, corner radii and the selected-row accent are the upstream values.
//
// The client README still pins b637828e for this window. That commit predates the sidebar — it
// had an NSToolbar — so it is not what ships today; the remote default branch is authoritative
// here, per AGENTS.md.

/// Scroll views lay an unflipped document view out from the bottom, which would park a short
/// page against the bottom edge instead of under the title.
@interface MSIMEPreferencesDocumentView : NSView
@end
@implementation MSIMEPreferencesDocumentView
- (BOOL)isFlipped { return YES; }
@end

/// Sidebar row: a tinted rounded pill plus a leading accent bar when selected, drawn rather than
/// assembled from subviews so the icon and label keep upstream's fixed offsets.
@interface MSIMESettingsNavigationButton : NSButton
@end
@implementation MSIMESettingsNavigationButton
- (void)drawRect:(NSRect)rect {
    (void)rect;
    if (self.state == NSControlStateValueOn) {
        [[[NSColor labelColor] colorWithAlphaComponent:0.06] setFill];
        [[NSBezierPath bezierPathWithRoundedRect:NSInsetRect(self.bounds, 0.0, 2.0) xRadius:6.0 yRadius:6.0] fill];
        [[NSColor colorWithSRGBRed:0.45 green:0.42 blue:0.77 alpha:1.0] setFill];
        [[NSBezierPath bezierPathWithRoundedRect:NSMakeRect(0.0, 12.0, 3.0, NSHeight(self.bounds) - 24.0)
                                         xRadius:1.5
                                         yRadius:1.5] fill];
    }
    NSImage *symbol = [self.image
        imageWithSymbolConfiguration:[NSImageSymbolConfiguration configurationWithPaletteColors:@[NSColor.labelColor]]];
    [symbol drawInRect:NSMakeRect(19.0, (NSHeight(self.bounds) - 20.0) / 2.0, 20.0, 20.0)];
    NSDictionary *attributes =
        @{NSFontAttributeName : [NSFont systemFontOfSize:16.0], NSForegroundColorAttributeName : NSColor.labelColor};
    NSSize size = [self.title sizeWithAttributes:attributes];
    [self.title drawAtPoint:NSMakePoint(57.0, (NSHeight(self.bounds) - size.height) / 2.0) withAttributes:attributes];
    if (self.window.firstResponder == self) {
        [NSColor.keyboardFocusIndicatorColor setStroke];
        [[NSBezierPath bezierPathWithRoundedRect:NSInsetRect(self.bounds, 1.0, 2.0) xRadius:6.0 yRadius:6.0] stroke];
    }
}
@end

static void ConfigureCard(NSBox *card) {
    card.boxType = NSBoxCustom;
    card.titlePosition = NSNoTitle;
    card.borderWidth = 0.5;
    card.cornerRadius = 12.0;
    card.borderColor = [NSColor separatorColor];
    card.fillColor = [NSColor controlBackgroundColor];
    card.translatesAutoresizingMaskIntoConstraints = NO;
}

static NSTextField *SectionLabel(NSString *title) {
    NSTextField *label = [NSTextField labelWithString:title];
    label.font = [NSFont systemFontOfSize:11.0 weight:NSFontWeightSemibold];
    label.textColor = [NSColor secondaryLabelColor];
    return label;
}

static NSView *PreferenceRow(NSString *title, NSView *control) {
    NSView *row = [[NSView alloc] initWithFrame:NSZeroRect];
    NSTextField *label = [NSTextField labelWithString:title];
    label.font = [NSFont systemFontOfSize:15.0 weight:NSFontWeightRegular];
    label.translatesAutoresizingMaskIntoConstraints = NO;
    control.translatesAutoresizingMaskIntoConstraints = NO;
    [row addSubview:label];
    [row addSubview:control];
    [NSLayoutConstraint activateConstraints:@[
        [row.heightAnchor constraintEqualToConstant:48.0],
        [label.leadingAnchor constraintEqualToAnchor:row.leadingAnchor],
        [label.centerYAnchor constraintEqualToAnchor:row.centerYAnchor],
        [label.trailingAnchor constraintLessThanOrEqualToAnchor:control.leadingAnchor constant:-12.0],
        [control.trailingAnchor constraintEqualToAnchor:row.trailingAnchor],
        [control.centerYAnchor constraintEqualToAnchor:row.centerYAnchor],
        [control.widthAnchor constraintEqualToConstant:[control isKindOfClass:NSSwitch.class] ? 52.0 : 188.0],
    ]];
    return row;
}

static NSView *CardHeader(NSString *title) {
    NSView *row = [[NSView alloc] initWithFrame:NSZeroRect];
    NSTextField *label = [NSTextField labelWithString:title];
    label.font = [NSFont systemFontOfSize:13.0 weight:NSFontWeightSemibold];
    label.textColor = [NSColor labelColor];
    label.accessibilityLabel = [title stringByAppendingString:@"标题"];
    label.translatesAutoresizingMaskIntoConstraints = NO;
    [row addSubview:label];
    [NSLayoutConstraint activateConstraints:@[
        [row.heightAnchor constraintEqualToConstant:34.0],
        [label.leadingAnchor constraintEqualToAnchor:row.leadingAnchor],
        [label.centerYAnchor constraintEqualToAnchor:row.centerYAnchor],
    ]];
    return row;
}

static void LinkifyButton(NSButton *button, NSString *accessibilityLabel) {
    button.bezelStyle = NSBezelStyleInline;
    button.accessibilityLabel = accessibilityLabel;
    button.contentTintColor = [NSColor linkColor];
    button.attributedTitle = [[NSAttributedString alloc]
        initWithString:button.title
            attributes:@{
                NSFontAttributeName : [NSFont systemFontOfSize:13.0 weight:NSFontWeightMedium],
                NSForegroundColorAttributeName : [NSColor linkColor],
            }];
}

static NSBox *CardSeparator() {
    NSBox *separator = [[NSBox alloc] initWithFrame:NSZeroRect];
    separator.boxType = NSBoxSeparator;
    separator.translatesAutoresizingMaskIntoConstraints = NO;
    [separator.heightAnchor constraintEqualToConstant:1.0].active = YES;
    return separator;
}

/// A scheme choice: the radio on the left, its scheme-specific popup trailing and disabled until
/// that scheme is the selected one.
static NSView *SchemeChoiceRow(NSButton *choice, NSView *accessory) {
    NSView *row = [[NSView alloc] initWithFrame:NSZeroRect];
    choice.translatesAutoresizingMaskIntoConstraints = NO;
    [row addSubview:choice];
    NSMutableArray<NSLayoutConstraint *> *constraints = [NSMutableArray arrayWithArray:@[
        [row.heightAnchor constraintEqualToConstant:44.0],
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
            [accessory.widthAnchor constraintEqualToConstant:150.0],
        ]];
    }
    [NSLayoutConstraint activateConstraints:constraints];
    return row;
}

static NSBox *CardWithViews(NSArray<NSView *> *views, CGFloat spacing) {
    NSBox *card = [[NSBox alloc] initWithFrame:NSZeroRect];
    ConfigureCard(card);
    NSStackView *stack = [NSStackView stackViewWithViews:views];
    stack.orientation = NSUserInterfaceLayoutOrientationVertical;
    stack.alignment = NSLayoutAttributeLeading;
    stack.distribution = NSStackViewDistributionFill;
    stack.spacing = spacing;
    stack.translatesAutoresizingMaskIntoConstraints = NO;
    for (NSView *view in views) [view.widthAnchor constraintEqualToAnchor:stack.widthAnchor].active = YES;
    [card addSubview:stack];
    [NSLayoutConstraint activateConstraints:@[
        [stack.leadingAnchor constraintEqualToAnchor:card.leadingAnchor constant:16.0],
        [stack.trailingAnchor constraintEqualToAnchor:card.trailingAnchor constant:-16.0],
        [stack.topAnchor constraintEqualToAnchor:card.topAnchor constant:12.0],
        [stack.bottomAnchor constraintEqualToAnchor:card.bottomAnchor constant:-12.0],
    ]];
    return card;
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
    titleLabel.font = [NSFont systemFontOfSize:24.0 weight:NSFontWeightSemibold];
    NSStackView *stack = [NSStackView stackViewWithViews:@[titleLabel]];
    stack.orientation = NSUserInterfaceLayoutOrientationVertical;
    stack.alignment = NSLayoutAttributeLeading;
    stack.distribution = NSStackViewDistributionFill;
    stack.spacing = 18.0;
    for (NSView *view in content) {
        [stack addArrangedSubview:view];
        [view.widthAnchor constraintEqualToAnchor:stack.widthAnchor].active = YES;
    }
    [stack setCustomSpacing:30.0 afterView:titleLabel];
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
        [stack.leadingAnchor constraintEqualToAnchor:document.leadingAnchor constant:30.0],
        [stack.trailingAnchor constraintEqualToAnchor:document.trailingAnchor constant:-30.0],
        [stack.topAnchor constraintEqualToAnchor:document.topAnchor constant:28.0],
        [stack.bottomAnchor constraintLessThanOrEqualToAnchor:document.bottomAnchor constant:-28.0],
    ]];
    NSLayoutConstraint *height = [document.heightAnchor constraintEqualToAnchor:page.contentView.heightAnchor];
    height.priority = NSLayoutPriorityDefaultLow;
    height.active = YES;
    return page;
}

@interface MSIMEAppearancePreferences ()
@end

@implementation MSIMEAppearancePreferences {
    NSUserDefaults *_defaults;
    NSArray<NSView *> *_preferencePages;
    NSArray<NSButton *> *_sidebarButtons;
    NSArray<NSButton *> *_schemeButtons;
    NSPopUpButton *_shuangpinSchemeButton;
    NSPopUpButton *_wubiSchemeButton;
    NSTextField *_versionLabel;
    NSTextField *_automaticUpdateLabel;
    NSButton *_updatePageButton;
    MSIMEUpdateController *_updateController;
    NSString *_sharedDefaultImeMode;
    NSString *_sharedImeModeScope;
    NSString *_activeModeApplication;
    BOOL _activeModeGlobal;
    NSMutableDictionary<NSString *, NSNumber *> *_applicationInputModes;
    NSNumber *_globalInputMode;
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
    NSNumber *_sharedShiftTapShortcut;
    NSNumber *_sharedControlTapShortcut;
    NSButton *_shiftTapShortcutButton;
    NSButton *_controlTapShortcutButton;
    NSNumber *_sharedControlOptionSpaceShortcut;
    NSButton *_controlOptionSpaceShortcutButton;
    NSNumber *_sharedCharacterSetShortcut;
    NSButton *_characterSetShortcutButton;
    NSMutableDictionary *_sharedHelpcodeOptions;
    NSMutableDictionary<NSString *, NSPopUpButton *> *_helpcodeSchemaButtons;
    NSMutableDictionary<NSString *, NSButton *> *_helpcodeDisplayButtons;
    NSNumber *_sharedChinesePunctuation;
    NSNumber *_sharedSmartPunctuation;
    NSNumber *_sharedSmartPunctuationRepeatToChinese;
    NSNumber *_sharedPairedPunctuation;
    NSString *_sharedPunctuationLock;
    NSButton *_pairedPunctuationButton;
    NSPopUpButton *_punctuationLockButton;
    NSMutableDictionary *_sharedMixedInput;
    NSButton *_mixedEnglishButton;
    NSPopUpButton *_mixedEnglishPrefixButton;
    NSButton *_mixedEmojiButton;
    NSButton *_mixedKaomojiButton;
    NSNumber *_sharedTraditionalOutput;
    NSNumber *_sharedAutocorrect;
    NSNumber *_sharedCloudCandidates;
    NSButton *_cloudCandidatesButton;
    NSNumber *_sharedCandidateTranslations;
    NSButton *_candidateTranslationsButton;
    NSNumber *_sharedCandidateEnglishGloss;
    NSButton *_candidateEnglishGlossButton;
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
    NSButton *_wordCharacterButton;
    NSPopUpButton *_wordCharacterKeys;
    NSMutableArray<NSButton *> *_navigationButtons;
    NSString *_sharedInputScheme;
    NSString *_sharedShuangpinProfile;
    NSNumber *_sharedShuangpinPreeditUsesRaw;
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
    NSPopUpButton *_skinButton;
    NSURL *_skinsRoot;
    NSImage *_decorationImage;
    msime::mac::ResolvedSkin _lightSkin;
    msime::mac::ResolvedSkin _darkSkin;
    std::vector<msime::mac::SkinListEntry> _skins;
    MSIMECandidatePreviewView *_preview;
    NSButton *_themeButton;
    NSWindowController *_skinWindow;
    NSString *_translationPreferencesDirectory;
    MSIMETranslationSettingsWindow *_translationWindow;
    MSIMEAISettingsWindow *_aiWindow;
    NSButton *_inputModeShortcutButton;
    NSButton *_fullWidthButton;
    NSButton *_keymapButton;
    NSButton *_wubiButton;
    NSButton *_punctuationButton;
    NSButton *_smartPunctuationButton;
    NSButton *_smartPunctuationRepeatButton;
    NSButton *_toolbarButton;
    NSButton *_transpositionButton;
    NSButton *_neighborButton;
    NSButton *_candidateFollowCursorButton;
    NSButton *_candidateLearningButton;
    NSPopUpButton *_frequencyModeButton;
    NSPopUpButton *_frequencyTriggerButton;
    NSPopUpButton *_frequencyStepButton;
    NSNumber *_sharedFuzzyPinyinEnabled;
    NSArray<NSString *> *_sharedFuzzyPinyinRules;
    NSNumber *_sharedCandidateLearning;
    NSString *_sharedFrequencyMode;
    NSNumber *_sharedFrequencyTriggerCount;
    NSNumber *_sharedFrequencyLinearStep;
    NSButton *_fuzzyPinyinButton;
    NSMutableDictionary<NSString *, NSButton *> *_fuzzyPinyinRuleButtons;
    NSButton *_quanpinHelpcodeButton;
    NSButton *_shuangpinHelpcodeButton;
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
    for (NSArray *entry in @[@[ShiftTapShortcutKey, @"switch_language_shift", @(self.shiftTapShortcut)],
                            @[ControlTapShortcutKey, @"switch_language_ctrl", @(self.controlTapShortcut)]]) {
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
    merged[@"candidate_layout"] = self.vertical ? @"vertical" : @"horizontal";
    merged[@"candidate_follow_cursor"] = @(self.candidateFollowCursor);
    merged[@"input_mode_hud"] = @(self.inputModeHUD);
    merged[@"scheme"] = self.inputScheme;
    merged[@"shuangpin_profile"] = self.shuangpinProfile;
    merged[@"shuangpin_preedit_uses_raw"] = @(self.shuangpinPreeditUsesRaw);
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
    toolbar[@"screen_keyboard"] = @(self.floatingToolbarScreenKeyboard);
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
    _sharedTraditionalOutput = nil;
    _sharedAutocorrect = nil;
    _sharedToolbarEnabled = nil;
    _sharedCandidateLearning = nil;
    _sharedQuanpinHelpcode = nil;
    _sharedShuangpinHelpcode = nil;
    _sharedHelpcodeOptions = nil;
    _sharedLocalModes = nil;
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
- (void)fuzzyPinyinChanged:(NSButton *)sender {
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
- (void)helpcodeDisplayChanged:(NSButton *)sender {
    [self setHelpcodeOption:@"show_in_candidate_window" value:@(sender.state == NSControlStateValueOn) scheme:sender.identifier];
}
- (NSString *)inputScheme { NSString *value = _sharedInputScheme ?: [_defaults stringForKey:SchemeKey]; return [@[@"quanpin", @"shuangpin", @"wubi", @"japanese"] containsObject:value] ? value : @"quanpin"; }
- (void)setInputScheme:(NSString *)value { if (![@[@"quanpin", @"shuangpin", @"wubi", @"japanese"] containsObject:value]) value = @"quanpin"; _sharedInputScheme = nil; [_defaults setObject:value forKey:SchemeKey]; [self preferencesChanged]; }
- (NSString *)shuangpinProfile { NSString *value = _sharedShuangpinProfile ?: [_defaults stringForKey:ShuangpinProfileKey]; return [@[@"xiaohe", @"ziranma", @"shoudao", @"microsoft"] containsObject:value] ? value : @"xiaohe"; }
- (void)setShuangpinProfile:(NSString *)value { if (![@[@"xiaohe", @"ziranma", @"shoudao", @"microsoft"] containsObject:value]) value = @"xiaohe"; _sharedShuangpinProfile = nil; [_defaults setObject:value forKey:ShuangpinProfileKey]; [self preferencesChanged]; }
- (BOOL)shuangpinPreeditUsesRaw { if (_sharedShuangpinPreeditUsesRaw) return _sharedShuangpinPreeditUsesRaw.boolValue; return [_defaults objectForKey:ShuangpinPreeditKey] == nil ? YES : [_defaults boolForKey:ShuangpinPreeditKey]; }
- (void)setShuangpinPreeditUsesRaw:(BOOL)value { _sharedShuangpinPreeditUsesRaw = nil; [_defaults setBool:value forKey:ShuangpinPreeditKey]; [self preferencesChanged]; }
- (MSIMEInlinePreeditStyle)inlinePreeditStyle {
    NSString *value = _sharedInlinePreeditStyle ?: @"raw";
    if ([value isEqual:@"raw"]) return MSIMEInlinePreeditStyleRaw;
    if ([value isEqual:@"empty"]) return MSIMEInlinePreeditStyleEmpty;
    return MSIMEInlinePreeditStylePinyin;
}
- (void)applySharedInputPreferences:(NSDictionary *)preferences {
    if (![preferences isKindOfClass:NSDictionary.class]) return;
    id defaultMode = preferences[@"default_ime_mode"], scope = preferences[@"ime_mode_scope"];
    if ([@[@"chinese", @"english"] containsObject:defaultMode]) _sharedDefaultImeMode = defaultMode;
    if ([@[@"app", @"global"] containsObject:scope]) _sharedImeModeScope = scope;
    id keys = preferences[@"keybindings"];
    if ([keys isKindOfClass:NSDictionary.class]) {
        if (LocalModeBoolean(keys[@"switch_language_shift"])) _sharedShiftTapShortcut = keys[@"switch_language_shift"];
        if (LocalModeBoolean(keys[@"switch_language_ctrl"])) _sharedControlTapShortcut = keys[@"switch_language_ctrl"];
        id inputMode = keys[@"switch_language_ctrl_alt_space"];
        if (LocalModeBoolean(inputMode)) _sharedControlOptionSpaceShortcut = inputMode;
        id enabled = keys[@"toggle_character_set_ctrl_shift_f"];
        if (LocalModeBoolean(enabled)) _sharedCharacterSetShortcut = enabled;
    }
    id punctuation = preferences[@"chinese_punctuation"];
    if (LocalModeBoolean(punctuation)) _sharedChinesePunctuation = punctuation;
    id smart = preferences[@"smart_punctuation"];
    if (LocalModeBoolean(smart)) _sharedSmartPunctuation = smart;
    id smartRepeat = preferences[@"smart_punctuation_repeat"];
    if (LocalModeBoolean(smartRepeat)) _sharedSmartPunctuationRepeatToChinese = smartRepeat;
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
    id cloud = preferences[@"cloud_candidates"];
    if (LocalModeBoolean(cloud)) _sharedCloudCandidates = cloud;
    id translations = preferences[@"candidate_translations"];
    if (LocalModeBoolean(translations)) _sharedCandidateTranslations = translations;
    id englishGloss = preferences[@"candidate_english_gloss"];
    if (LocalModeBoolean(englishGloss)) _sharedCandidateEnglishGloss = englishGloss;
    id scheme = preferences[@"scheme"];
    id profile = preferences[@"shuangpin_profile"];
    id raw = preferences[@"shuangpin_preedit_uses_raw"];
    if ([@[@"quanpin", @"shuangpin", @"wubi", @"japanese"] containsObject:scheme]) _sharedInputScheme = [scheme copy];
    if ([@[@"xiaohe", @"ziranma", @"shoudao", @"microsoft"] containsObject:profile]) _sharedShuangpinProfile = [profile copy];
    if (LocalModeBoolean(raw)) _sharedShuangpinPreeditUsesRaw = raw;
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
- (void)resetGlobalInputMode { _globalInputMode = nil; }
- (BOOL)traditionalOutput { return _sharedTraditionalOutput ? _sharedTraditionalOutput.boolValue : [_defaults boolForKey:TraditionalKey]; }
- (BOOL)fullWidthInput { return [_defaults boolForKey:FullWidthKey]; }
- (BOOL)chinesePunctuation { if (_sharedChinesePunctuation) return _sharedChinesePunctuation.boolValue; return [_defaults objectForKey:ChinesePunctuationKey] == nil ? YES : [_defaults boolForKey:ChinesePunctuationKey]; }
- (BOOL)smartPunctuation { return _sharedSmartPunctuation ? _sharedSmartPunctuation.boolValue : ([_defaults objectForKey:SmartPunctuationKey] == nil ? YES : [_defaults boolForKey:SmartPunctuationKey]); }
- (void)setSmartPunctuation:(BOOL)value { _sharedSmartPunctuation = nil; [_defaults setBool:value forKey:SmartPunctuationKey]; [self preferencesChanged]; }
- (BOOL)smartPunctuationRepeatToChinese { return _sharedSmartPunctuationRepeatToChinese ? _sharedSmartPunctuationRepeatToChinese.boolValue : ([_defaults objectForKey:SmartPunctuationRepeatToChineseKey] == nil ? YES : [_defaults boolForKey:SmartPunctuationRepeatToChineseKey]); }
- (void)setSmartPunctuationRepeatToChinese:(BOOL)value { _sharedSmartPunctuationRepeatToChinese = nil; [_defaults setBool:value forKey:SmartPunctuationRepeatToChineseKey]; [self preferencesChanged]; }
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
    [_defaults setBool:value forKey:FullWidthKey];
    [self preferencesChanged];
}
- (void)setChinesePunctuation:(BOOL)value {
    _sharedChinesePunctuation = nil;
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
- (BOOL)mixedEmojiInput { id value = [self mixedInputValues][@"emoji"]; return LocalModeBoolean(value) ? [value boolValue] : NO; }
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
    return [_defaults objectForKey:InputModeShortcutKey] == nil || [_defaults boolForKey:InputModeShortcutKey];
}
- (BOOL)shiftTapShortcut {
    if (_sharedShiftTapShortcut) return _sharedShiftTapShortcut.boolValue;
    return [_defaults objectForKey:ShiftTapShortcutKey] == nil || [_defaults boolForKey:ShiftTapShortcutKey];
}
- (void)setShiftTapShortcut:(BOOL)value {
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
- (void)setInputModeShortcut:(BOOL)value {
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
    return msime::mac::NormalizeCandidatePageSize(static_cast<NSUInteger>(MAX(0, value)));
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
    _wordCharacterButton.state = [wordCharacter[@"enabled"] boolValue] ? NSControlStateValueOn : NSControlStateValueOff;
    [_wordCharacterKeys selectItemAtIndex:[wordCharacter[@"keys"] isEqual:@"minus_equal"] ? 1 : 0];
    for (NSButton *button in _navigationButtons)
        button.state = [self navigationEnabled:button.identifier] ? NSControlStateValueOn : NSControlStateValueOff;
    for (NSString *scheme in _helpcodeSchemaButtons) {
        NSDictionary *values = [self helpcodeOptionsForScheme:scheme];
        [_helpcodeSchemaButtons[scheme] selectItemAtIndex:[HelpcodeSchemas() indexOfObject:values[@"schema"]]];
        _helpcodeDisplayButtons[scheme].state = [values[@"show_in_candidate_window"] boolValue] ? NSControlStateValueOn : NSControlStateValueOff;
    }
    _fullWidthButton.state = self.fullWidthInput ? NSControlStateValueOn : NSControlStateValueOff;
    _keymapButton.state = self.shuangpinKeymap ? NSControlStateValueOn : NSControlStateValueOff;
    _wubiButton.state = self.wubiAutoCommitUnique ? NSControlStateValueOn : NSControlStateValueOff;
    _punctuationButton.state = self.chinesePunctuation ? NSControlStateValueOn : NSControlStateValueOff;
    _smartPunctuationButton.state = self.smartPunctuation ? NSControlStateValueOn : NSControlStateValueOff;
    _smartPunctuationRepeatButton.state = self.smartPunctuationRepeatToChinese ? NSControlStateValueOn : NSControlStateValueOff;
    _pairedPunctuationButton.state = self.pairedPunctuation ? NSControlStateValueOn : NSControlStateValueOff;
    NSDictionary *punctuationLockIndexes = @{@"follow": @0, @"chinese": @1, @"english": @2};
    [_punctuationLockButton selectItemAtIndex:[punctuationLockIndexes[self.punctuationLock] integerValue]];
    _mixedEnglishButton.state = self.mixedEnglishInput ? NSControlStateValueOn : NSControlStateValueOff;
    _mixedEnglishPrefixButton.enabled = self.mixedEnglishInput;
    [_mixedEnglishPrefixButton selectItemAtIndex:self.mixedEnglishMinimumPrefix - 1];
    _mixedEmojiButton.state = self.mixedEmojiInput ? NSControlStateValueOn : NSControlStateValueOff;
    _mixedKaomojiButton.state = self.mixedKaomojiInput ? NSControlStateValueOn : NSControlStateValueOff;
    _toolbarButton.state = self.floatingToolbarEnabled ? NSControlStateValueOn : NSControlStateValueOff;
    _toolbarPunctuationButton.state = self.floatingToolbarPunctuation ? NSControlStateValueOn : NSControlStateValueOff;
    _toolbarFullWidthButton.state = self.floatingToolbarFullWidth ? NSControlStateValueOn : NSControlStateValueOff;
    _toolbarCharacterSetButton.state = self.floatingToolbarCharacterSet ? NSControlStateValueOn : NSControlStateValueOff;
    _toolbarEmojiButton.state = self.floatingToolbarEmoji ? NSControlStateValueOn : NSControlStateValueOff;
    _toolbarScreenKeyboardButton.state = self.floatingToolbarScreenKeyboard ? NSControlStateValueOn : NSControlStateValueOff;
    _toolbarSettingsButton.state = self.floatingToolbarSettings ? NSControlStateValueOn : NSControlStateValueOff;
    [_toolbarScaleButton selectItemAtIndex:[@[@75, @100, @125, @150] indexOfObject:@(self.floatingToolbarScalePercent)]];
    [_toolbarFontSizeButton selectItemAtIndex:self.floatingToolbarFontSize - 16];
    _transpositionButton.state = self.autocorrectTransposition ? NSControlStateValueOn : NSControlStateValueOff;
    _neighborButton.state = self.autocorrectNeighbor ? NSControlStateValueOn : NSControlStateValueOff;
    _candidateFollowCursorButton.state = self.candidateFollowCursor ? NSControlStateValueOn : NSControlStateValueOff;
    _candidateLearningButton.state = self.candidateLearningEnabled ? NSControlStateValueOn : NSControlStateValueOff;
    [_frequencyModeButton selectItemAtIndex:[FrequencyModes() indexOfObject:self.frequencyAdjustmentMode]];
    [_frequencyTriggerButton selectItemAtIndex:self.frequencyTriggerCount - 1];
    [_frequencyStepButton selectItemAtIndex:self.frequencyLinearStep - 1];
    _fuzzyPinyinButton.state = self.fuzzyPinyinEnabled ? NSControlStateValueOn : NSControlStateValueOff;
    for (NSString *rule in _fuzzyPinyinRuleButtons) {
        NSButton *button = _fuzzyPinyinRuleButtons[rule];
        button.state = [self fuzzyPinyinRuleEnabled:rule] ? NSControlStateValueOn : NSControlStateValueOff;
        button.enabled = self.fuzzyPinyinEnabled;
    }
    _cloudCandidatesButton.state = self.cloudCandidates ? NSControlStateValueOn : NSControlStateValueOff;
    _candidateTranslationsButton.state = self.candidateTranslations ? NSControlStateValueOn : NSControlStateValueOff;
    _candidateEnglishGlossButton.state = self.candidateEnglishGloss ? NSControlStateValueOn : NSControlStateValueOff;
    _quanpinHelpcodeButton.state = self.quanpinHelpcodeEnabled ? NSControlStateValueOn : NSControlStateValueOff;
    _shuangpinHelpcodeButton.state = self.shuangpinHelpcodeEnabled ? NSControlStateValueOn : NSControlStateValueOff;
    for (NSButton *button in _localModeButtons)
        button.state = [self localModeEnabled:button.identifier] ? NSControlStateValueOn : NSControlStateValueOff;
    _inputModeShortcutButton.state = self.inputModeShortcut ? NSControlStateValueOn : NSControlStateValueOff;
    _shiftTapShortcutButton.state = self.shiftTapShortcut ? NSControlStateValueOn : NSControlStateValueOff;
    _controlTapShortcutButton.state = self.controlTapShortcut ? NSControlStateValueOn : NSControlStateValueOff;
    _controlOptionSpaceShortcutButton.state = self.controlOptionSpaceShortcut ? NSControlStateValueOn : NSControlStateValueOff;
    _characterSetShortcutButton.state = self.characterSetShortcut ? NSControlStateValueOn : NSControlStateValueOff;
    [_layoutButton selectItemAtIndex:self.vertical ? 1 : 0];
    NSDictionary *schemeIndexes = @{@"quanpin": @0, @"shuangpin": @1, @"wubi": @2, @"japanese": @3};
    const NSInteger storedScheme = [schemeIndexes[self.inputScheme] integerValue];
    // The radios and the scheme popups mirror the same stored value: only the selected scheme's
    // popup is usable, so a disabled row cannot look like it is configuring the active scheme.
    for (NSInteger index = 0; index < (NSInteger)_schemeButtons.count; ++index)
        _schemeButtons[index].state = index == storedScheme ? NSControlStateValueOn : NSControlStateValueOff;
    _shuangpinSchemeButton.enabled = storedScheme == 1;
    _wubiSchemeButton.enabled = storedScheme == 2;
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
    [_skinButton removeAllItems];
    for (const auto &entry : _skins) {
        NSMenuItem *item = [[NSMenuItem alloc] initWithTitle:@(entry.name.c_str()) action:nil keyEquivalent:@""];
        item.representedObject = @(entry.id.c_str());
        [_skinButton.menu addItem:item];
    }
    for (NSMenuItem *item in _skinButton.itemArray) {
        if ([item.representedObject isEqual:@(_lightSkin.id.c_str())]) { [_skinButton selectItem:item]; break; }
    }
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
    NSWindow *window = [[NSWindow alloc] initWithContentRect:NSMakeRect(0, 0, 980, 800)
                                                   styleMask:NSWindowStyleMaskTitled | NSWindowStyleMaskClosable |
                                                             NSWindowStyleMaskMiniaturizable | NSWindowStyleMaskResizable
                                                     backing:NSBackingStoreBuffered
                                                       defer:NO];
    window.title = @"水杉输入法设置";
    window.restorable = NO;
    window.contentMinSize = NSMakeSize(900, 650);
    window.releasedWhenClosed = NO;
    _layoutButton = [[NSPopUpButton alloc] initWithFrame:NSZeroRect pullsDown:NO];
    [_layoutButton addItemsWithTitles:@[@"横向排列", @"纵向列表"]];
    _layoutButton.accessibilityLabel = @"候选排列";
    _layoutButton.target = self;
    _layoutButton.action = @selector(layoutChanged:);
    _candidateFollowCursorButton = [NSButton checkboxWithTitle:@"候选窗口跟随光标" target:self action:@selector(candidateFollowCursorChanged:)];
    _candidateFollowCursorButton.accessibilityLabel = @"候选窗口跟随光标";
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
    [_textColorField.widthAnchor constraintEqualToConstant:160].active = YES;
    _textColorWell = [[NSColorWell alloc] initWithFrame:NSMakeRect(0, 0, 40, 24)];
    _textColorWell.accessibilityLabel = @"选择候选文字颜色";
    _textColorWell.target = self;
    _textColorWell.action = @selector(textColorWellChanged:);
    NSStackView *textColorControls = [NSStackView stackViewWithViews:@[_textColorField, _textColorWell,
        [NSButton buttonWithTitle:@"跟随皮肤" target:self action:@selector(resetTextColor:)]]];
    textColorControls.orientation = NSUserInterfaceLayoutOrientationHorizontal;
    _fallbackList = [[NSPopUpButton alloc] initWithFrame:NSZeroRect pullsDown:NO];
    _fallbackList.accessibilityLabel = @"补充字体顺序";
    [_fallbackList.widthAnchor constraintEqualToConstant:180].active = YES;
    _fallbackFamilyControl = [[NSComboBox alloc] initWithFrame:NSZeroRect];
    [_fallbackFamilyControl addItemsWithObjectValues:_fontFamilyControl.objectValues];
    _fallbackFamilyControl.completes = YES;
    _fallbackFamilyControl.accessibilityLabel = @"添加补充字体";
    _fallbackFamilyControl.placeholderString = @"字体家族名称";
    [_fallbackFamilyControl.widthAnchor constraintEqualToConstant:200].active = YES;
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
    _wordCharacterButton = [NSButton checkboxWithTitle:@"以词定字（首字／尾字）" target:self action:@selector(wordCharacterChanged:)];
    _wordCharacterButton.accessibilityLabel = @"以词定字";
    _wordCharacterButton.toolTip = @"须先关闭所选键组的翻页功能";
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
    NSStackView *navigationControls = [NSStackView stackViewWithViews:_navigationButtons];
    navigationControls.orientation = NSUserInterfaceLayoutOrientationVertical;
    navigationControls.alignment = NSLayoutAttributeLeading;
    _pageSizeButton = [[NSPopUpButton alloc] initWithFrame:NSZeroRect pullsDown:NO];
    for (NSUInteger size : {static_cast<NSUInteger>(5), static_cast<NSUInteger>(7), static_cast<NSUInteger>(9)})
        [_pageSizeButton addItemWithTitle:[NSString stringWithFormat:@"%lu 个", (unsigned long)size]];
    _pageSizeButton.accessibilityLabel = @"每页候选";
    _pageSizeButton.target = self;
    _pageSizeButton.action = @selector(pageSizeChanged:);
    _skinButton = [[NSPopUpButton alloc] initWithFrame:NSZeroRect pullsDown:NO];
    _skinButton.accessibilityLabel = @"候选皮肤";
    _skinButton.target = self;
    _skinButton.action = @selector(skinChanged:);
    NSButton *reload = [NSButton buttonWithTitle:@"重新读取皮肤" target:self action:@selector(reloadSkinsFromButton:)];
    NSButton *browse = [NSButton buttonWithTitle:@"浏览所有皮肤…" target:self action:@selector(showSkinCatalog:)];
    _inputModeShortcutButton = [NSButton checkboxWithTitle:@"Shift + 空格切换中英文" target:self action:@selector(inputModeShortcutChanged:)];
    _defaultImeModeButton = [[NSPopUpButton alloc] initWithFrame:NSZeroRect pullsDown:NO];
    [_defaultImeModeButton addItemsWithTitles:@[@"中文", @"英文"]];
    _defaultImeModeButton.target = self; _defaultImeModeButton.action = @selector(defaultImeModeChanged:);
    _imeModeScopeButton = [[NSPopUpButton alloc] initWithFrame:NSZeroRect pullsDown:NO];
    [_imeModeScopeButton addItemsWithTitles:@[@"按应用", @"全局"]];
    _imeModeScopeButton.target = self; _imeModeScopeButton.action = @selector(imeModeScopeChanged:);
    _imeModeScopeButton.toolTip = @"下一次激活时生效；中英文状态仅在当前输入法进程内记忆";
    _shiftTapShortcutButton = [NSButton checkboxWithTitle:@"单按 Shift 切换中英文" target:self action:@selector(shiftTapShortcutChanged:)];
    _controlTapShortcutButton = [NSButton checkboxWithTitle:@"单按 Control 切换中英文" target:self action:@selector(controlTapShortcutChanged:)];
    _controlOptionSpaceShortcutButton = [NSButton checkboxWithTitle:@"Control + Option + 空格切换中英文" target:self action:@selector(controlOptionSpaceShortcutChanged:)];
    _characterSetShortcutButton = [NSButton checkboxWithTitle:@"Control + Shift + F 切换简繁" target:self action:@selector(characterSetShortcutChanged:)];
    _fullWidthButton = [NSButton checkboxWithTitle:@"全角输入（Option + Shift + H）" target:self action:@selector(fullWidthChanged:)];
    _fullWidthButton.toolTip = @"Control+Shift+Space 或 Option+Shift+H 切换全半角";
    _keymapButton = [NSButton checkboxWithTitle:@"输入时显示双拼键位提示" target:self action:@selector(keymapChanged:)];
    _wubiButton = [NSButton checkboxWithTitle:@"五笔四码唯一候选自动上屏" target:self action:@selector(wubiChanged:)];
    _punctuationButton = [NSButton checkboxWithTitle:@"中文标点" target:self action:@selector(punctuationChanged:)];
    _punctuationButton.toolTip = @"Control+. 切换中英文标点";
    _smartPunctuationButton = [NSButton checkboxWithTitle:@"智能标点" target:self action:@selector(smartPunctuationChanged:)];
    _smartPunctuationButton.toolTip = @"前一个字符为字母或数字时保留逗号、句号和冒号为 ASCII 形式";
    _smartPunctuationRepeatButton = [NSButton checkboxWithTitle:@"重复标点转中文" target:self action:@selector(smartPunctuationRepeatChanged:)];
    _smartPunctuationRepeatButton.toolTip = @"短时间重复输入 ASCII 标点时替换为中文标点";
    _pairedPunctuationButton = [NSButton checkboxWithTitle:@"成对标点" target:self action:@selector(pairedPunctuationChanged:)];
    _pairedPunctuationButton.toolTip = @"自动插入并配对引号、括号等标点";
    _punctuationLockButton = [[NSPopUpButton alloc] initWithFrame:NSZeroRect pullsDown:NO];
    [_punctuationLockButton addItemsWithTitles:@[@"跟随中文标点", @"始终中文", @"始终英文"]];
    _punctuationLockButton.accessibilityLabel = @"标点锁定";
    _punctuationLockButton.target = self;
    _punctuationLockButton.action = @selector(punctuationLockChanged:);
    _mixedEnglishButton = [NSButton checkboxWithTitle:@"中英混输" target:self action:@selector(mixedEnglishChanged:)];
    _mixedEnglishButton.toolTip = @"在中文组词中允许英文候选";
    _mixedEnglishPrefixButton = [[NSPopUpButton alloc] initWithFrame:NSZeroRect pullsDown:NO];
    NSMutableArray<NSString *> *mixedPrefixes = [NSMutableArray array];
    for (NSInteger prefix = 1; prefix <= 8; ++prefix)
        [mixedPrefixes addObject:[NSString stringWithFormat:@"%ld 个字符", (long)prefix]];
    [_mixedEnglishPrefixButton addItemsWithTitles:mixedPrefixes];
    _mixedEnglishPrefixButton.accessibilityLabel = @"中英混输触发字符数";
    _mixedEnglishPrefixButton.target = self;
    _mixedEnglishPrefixButton.action = @selector(mixedEnglishPrefixChanged:);
    _mixedEmojiButton = [NSButton checkboxWithTitle:@"Emoji 混输" target:self action:@selector(mixedEmojiChanged:)];
    _mixedEmojiButton.toolTip = @"在中文组词中提供 Emoji 候选";
    _mixedKaomojiButton = [NSButton checkboxWithTitle:@"颜文字混输" target:self action:@selector(mixedKaomojiChanged:)];
    _mixedKaomojiButton.toolTip = @"在中文组词中提供颜文字候选";
    _toolbarButton = [NSButton checkboxWithTitle:@"显示浮动工具栏" target:self action:@selector(toolbarChanged:)];
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
    _transpositionButton = [NSButton checkboxWithTitle:@"全拼乱序纠错（sahng → shang）" target:self action:@selector(transpositionChanged:)];
    _neighborButton = [NSButton checkboxWithTitle:@"全拼邻键纠错（shabg → shang）" target:self action:@selector(neighborChanged:)];
    _candidateLearningButton = [NSButton checkboxWithTitle:@"学习候选词频" target:self action:@selector(candidateLearningChanged:)];
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
    _fuzzyPinyinButton = [NSButton checkboxWithTitle:@"启用模糊音" target:self action:@selector(fuzzyPinyinChanged:)];
    _cloudCandidatesButton = [NSButton checkboxWithTitle:@"启用云候选（将查询发送至 Google 输入工具）" target:self action:@selector(cloudCandidatesChanged:)];
    _candidateTranslationsButton = [NSButton checkboxWithTitle:@"显示候选释义" target:self action:@selector(candidateTranslationsChanged:)];
    _candidateEnglishGlossButton = [NSButton checkboxWithTitle:@"显示离线英文释义" target:self action:@selector(candidateEnglishGlossChanged:)];
    _quanpinHelpcodeButton = [NSButton checkboxWithTitle:@"启用全拼辅助码" target:self action:@selector(quanpinHelpcodeChanged:)];
    _shuangpinHelpcodeButton = [NSButton checkboxWithTitle:@"启用双拼辅助码" target:self action:@selector(shuangpinHelpcodeChanged:)];
    _helpcodeSchemaButtons = [NSMutableDictionary dictionary];
    _helpcodeDisplayButtons = [NSMutableDictionary dictionary];
    _fuzzyPinyinRuleButtons = [NSMutableDictionary dictionary];
    _localModeButtons = [NSMutableArray array];

    // ---- 输入 -------------------------------------------------------------------------------
    NSButton *wubiSettingsButton = [NSButton buttonWithTitle:@"五笔功能设置" target:self action:@selector(showWubiSettings:)];
    LinkifyButton(wubiSettingsButton, @"五笔功能设置");
    wubiSettingsButton.image = [NSImage imageWithSystemSymbolName:@"chevron.right" accessibilityDescription:nil];
    wubiSettingsButton.imagePosition = NSImageRight;
    wubiSettingsButton.alignment = NSTextAlignmentRight;

    NSBox *inputModeCard = CardWithViews(@[
        PreferenceRow(@"输入模式", _defaultImeModeButton),
        PreferenceRow(@"模式作用范围", _imeModeScopeButton),
    ], 0.0);
    inputModeCard.accessibilityLabel = @"输入模式卡片";

    // The scheme is one choice, so it reads as radios with each scheme's own popup trailing it,
    // disabled until that scheme is selected. The stored value stays the same scheme string.
    NSArray<NSString *> *schemeTitles = @[@"全拼输入", @"双拼输入", @"五笔输入", @"日语输入"];
    NSMutableArray<NSButton *> *schemeButtons = [NSMutableArray array];
    NSMutableArray<NSView *> *schemeRows = [NSMutableArray arrayWithObjects:CardHeader(@"输入方式"), CardSeparator(), nil];
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
        if (index < (NSInteger)schemeTitles.count - 1) [schemeRows addObject:CardSeparator()];
    }
    _schemeButtons = schemeButtons;
    NSBox *schemeCard = CardWithViews(schemeRows, 0.0);
    schemeCard.accessibilityLabel = @"输入方式卡片";

    NSBox *shuangpinCard = CardWithViews(@[
        PreferenceRow(@"双拼预编辑", _preeditButton),
        PreferenceRow(@"双拼初学者", _keymapButton),
    ], 0.0);
    shuangpinCard.accessibilityLabel = @"双拼选项卡片";
    NSBox *wubiEntryCard = CardWithViews(@[PreferenceRow(@"五笔功能", wubiSettingsButton)], 0.0);
    wubiEntryCard.accessibilityLabel = @"五笔入口卡片";

    NSBox *punctuationCard = CardWithViews(@[
        _punctuationButton, _smartPunctuationButton, _smartPunctuationRepeatButton, _pairedPunctuationButton,
        PreferenceRow(@"标点锁定", _punctuationLockButton),
    ], 9.0);
    punctuationCard.accessibilityLabel = @"标点输入卡片";
    NSBox *mixedCard = CardWithViews(@[
        _mixedEnglishButton, PreferenceRow(@"中英混输触发长度", _mixedEnglishPrefixButton),
        _mixedEmojiButton, _mixedKaomojiButton,
    ], 9.0);
    mixedCard.accessibilityLabel = @"中英混输卡片";
    NSBox *correctionCard = CardWithViews(@[_transpositionButton, _neighborButton], 9.0);
    correctionCard.accessibilityLabel = @"拼音纠错卡片";
    NSMutableArray<NSView *> *fuzzyRows = [NSMutableArray arrayWithObject:_fuzzyPinyinButton];
    for (NSArray *entry in FuzzyPinyinRuleControls()) {
        NSButton *button = [NSButton checkboxWithTitle:entry[1] target:self action:@selector(fuzzyPinyinRuleChanged:)];
        button.identifier = entry[0];
        _fuzzyPinyinRuleButtons[entry[0]] = button;
        [fuzzyRows addObject:button];
    }
    NSBox *fuzzyCard = CardWithViews(fuzzyRows, 9.0);
    fuzzyCard.accessibilityLabel = @"模糊音卡片";

    NSScrollView *generalPage = PreferencesPage(@"键盘输入", @"选择中文或日语输入模式，并调整日常输入行为。", @[
        inputModeCard, SectionLabel(@"中文输入方案"), schemeCard, shuangpinCard, wubiEntryCard,
        SectionLabel(@"标点输入"), punctuationCard, SectionLabel(@"中英混输"), mixedCard,
        SectionLabel(@"拼音纠错"), correctionCard, SectionLabel(@"模糊音"), fuzzyCard,
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
    NSBox *candidateWindowCard = CardWithViews(@[
        PreferenceRow(@"候选排列", _layoutButton),
        PreferenceRow(@"每页候选", _pageSizeButton),
        PreferenceRow(@"候选字号", _fontButton),
        PreferenceRow(@"候选窗拼音字号", _preeditFontButton),
        PreferenceRow(@"候选窗预编辑", _candidatePreeditButton),
        _candidateFollowCursorButton,
    ], 0.0);
    candidateWindowCard.accessibilityLabel = @"候选窗口卡片";
    NSBox *fontCard = CardWithViews(@[
        PreferenceRow(@"候选字体", _fontFamilyControl),
        PreferenceRow(@"候选窗英文字体", _englishFontFamilyControl),
        PreferenceRow(@"候选文字颜色", textColorControls),
        PreferenceRow(@"补充字体（最多 32 项）", fallbackAdd),
        PreferenceRow(@"补充字体优先顺序", fallbackOrder),
    ], 0.0);
    fontCard.accessibilityLabel = @"候选字体卡片";
    NSScrollView *appearancePage = PreferencesPage(@"外观", @"调整候选窗口与输入状态栏的显示方式。", @[
        SectionLabel(@"效果预览"), _preview, previewControls,
        SectionLabel(@"候选窗口"), candidateWindowCard,
        SectionLabel(@"候选字体"), fontCard,
    ]);

    // ---- 皮肤 -------------------------------------------------------------------------------
    NSBox *skinCard = CardWithViews(@[
        PreferenceRow(@"候选皮肤", _skinButton),
        PreferenceRow(@"外部皮肤", reload),
        PreferenceRow(@"皮肤卡片", browse),
    ], 0.0);
    skinCard.accessibilityLabel = @"候选皮肤卡片";
    NSScrollView *skinPage = PreferencesPage(@"皮肤", @"选择内置皮肤，或加载放入皮肤目录的外部皮肤包。", @[
        SectionLabel(@"候选皮肤"), skinCard,
    ]);

    // ---- 词库与数据 --------------------------------------------------------------------------
    NSBox *learningCard = CardWithViews(@[
        _candidateLearningButton,
        PreferenceRow(@"词频调整方式", _frequencyModeButton),
        PreferenceRow(@"词频触发次数", _frequencyTriggerButton),
        PreferenceRow(@"线性调整步长", _frequencyStepButton),
    ], 0.0);
    learningCard.accessibilityLabel = @"候选与学习卡片";
    NSButton *aiButton = [NSButton buttonWithTitle:@"配置 AI 联想…" target:self action:@selector(showAISettings:)];
    NSButton *translationButton = [NSButton buttonWithTitle:@"配置候选翻译…" target:self action:@selector(showTranslationSettings:)];
    NSBox *cloudCard = CardWithViews(@[
        _cloudCandidatesButton, _candidateTranslationsButton, _candidateEnglishGlossButton,
        PreferenceRow(@"AI 联想", aiButton),
        PreferenceRow(@"翻译服务与目标语言", translationButton),
    ], 9.0);
    cloudCard.accessibilityLabel = @"云端与智能候选卡片";
    NSScrollView *dataPage = PreferencesPage(@"词库与数据", @"管理本机词库、用户词条与学习数据。", @[
        SectionLabel(@"候选与学习"), learningCard, SectionLabel(@"云端与智能候选"), cloudCard,
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
    NSBox *updateCard = CardWithViews(@[
        PreferenceRow(@"当前版本", _versionLabel),
        PreferenceRow(@"自动更新", _automaticUpdateLabel),
        PreferenceRow(@"立即检查", _updatePageButton),
    ], 0.0);
    updateCard.accessibilityLabel = @"软件更新卡片";
    NSButton *websiteButton = [NSButton buttonWithTitle:@"访问 msime.app" target:self action:@selector(openProductWebsite:)];
    LinkifyButton(websiteButton, @"访问水杉官网");
    NSBox *aboutCard = CardWithViews(@[PreferenceRow(@"产品主页", websiteButton)], 0.0);
    aboutCard.accessibilityLabel = @"关于卡片";
    NSScrollView *aboutPage = PreferencesPage(@"关于", @"版本与更新，以及水杉输入法的产品主页。", @[
        SectionLabel(@"软件更新"), updateCard, SectionLabel(@"产品信息"), aboutCard,
    ]);

    // ---- 五笔设置（输入页的子页，不在侧边栏里） ------------------------------------------------
    NSButton *backToKeyboardButton = [NSButton buttonWithTitle:@"返回键盘输入" target:self action:@selector(backToKeyboardInput:)];
    backToKeyboardButton.bezelStyle = NSBezelStyleInline;
    backToKeyboardButton.image = [NSImage imageWithSystemSymbolName:@"chevron.left" accessibilityDescription:nil];
    backToKeyboardButton.imagePosition = NSImageLeft;
    backToKeyboardButton.alignment = NSTextAlignmentLeft;
    NSTextField *wubiSchemeLabel = [NSTextField labelWithString:@"86 五笔"];
    wubiSchemeLabel.textColor = [NSColor secondaryLabelColor];
    NSBox *wubiCard = CardWithViews(@[PreferenceRow(@"编码方案", wubiSchemeLabel), _wubiButton], 8.0);
    wubiCard.accessibilityLabel = @"五笔选项卡片";
    NSScrollView *wubiPage = PreferencesPage(@"五笔设置", @"调整 86 五笔的输入与上屏行为。", @[
        backToKeyboardButton, SectionLabel(@"输入行为"), wubiCard,
    ]);

    // ---- 辅助码 -----------------------------------------------------------------------------
    NSMutableArray<NSView *> *helpcodeRows = [NSMutableArray arrayWithObjects:_quanpinHelpcodeButton, _shuangpinHelpcodeButton, nil];
    for (NSString *scheme in @[@"quanpin", @"shuangpin"]) {
        NSString *name = [scheme isEqual:@"quanpin"] ? @"全拼" : @"双拼";
        NSPopUpButton *schemas = [[NSPopUpButton alloc] initWithFrame:NSZeroRect pullsDown:NO];
        [schemas addItemsWithTitles:@[@"蓝天小雨点", @"自然码", @"首右2.0", @"首右plus", @"小鹤"]];
        for (NSUInteger index = 0; index < HelpcodeSchemas().count; ++index)
            [schemas itemAtIndex:index].representedObject = HelpcodeSchemas()[index];
        schemas.identifier = scheme;
        schemas.target = self;
        schemas.action = @selector(helpcodeSchemaChanged:);
        schemas.accessibilityLabel = [name stringByAppendingString:@"辅助码方案"];
        NSButton *display = [NSButton checkboxWithTitle:[NSString stringWithFormat:@"在候选窗口中显示%@辅助码", name] target:self action:@selector(helpcodeDisplayChanged:)];
        display.identifier = scheme;
        _helpcodeSchemaButtons[scheme] = schemas;
        _helpcodeDisplayButtons[scheme] = display;
        [helpcodeRows addObject:PreferenceRow(schemas.accessibilityLabel, schemas)];
        [helpcodeRows addObject:display];
    }
    NSBox *helpcodeCard = CardWithViews(helpcodeRows, 9.0);
    helpcodeCard.accessibilityLabel = @"辅助码卡片";
    NSScrollView *helpcodePage = PreferencesPage(@"辅助码", @"为全拼与双拼分别选择辅助码方案。", @[
        SectionLabel(@"辅助码方案"), helpcodeCard,
    ]);

    // ---- 快捷键 -----------------------------------------------------------------------------
    NSBox *pagingCard = CardWithViews(@[
        PreferenceRow(@"上翻 / 下翻", _pageShortcutButton),
        PreferenceRow(@"独立候选导航", navigationControls),
        _wordCharacterButton,
        PreferenceRow(@"首字／尾字键组", _wordCharacterKeys),
    ], 0.0);
    pagingCard.accessibilityLabel = @"候选翻页卡片";
    NSBox *switchingCard = CardWithViews(@[
        _inputModeShortcutButton, _shiftTapShortcutButton, _controlTapShortcutButton,
        _controlOptionSpaceShortcutButton, _characterSetShortcutButton, _fullWidthButton,
    ], 9.0);
    switchingCard.accessibilityLabel = @"输入状态切换卡片";
    NSScrollView *shortcutsPage = PreferencesPage(@"快捷键", @"设置候选翻页与输入状态切换快捷键。", @[
        SectionLabel(@"候选翻页与选字"), pagingCard, SectionLabel(@"输入状态切换"), switchingCard,
    ]);

    // ---- 悬浮工具栏 --------------------------------------------------------------------------
    NSBox *toolbarCard = CardWithViews(@[
        _toolbarButton, _toolbarPunctuationButton, _toolbarFullWidthButton, _toolbarCharacterSetButton,
        _toolbarEmojiButton, _toolbarScreenKeyboardButton, _toolbarSettingsButton,
    ], 9.0);
    toolbarCard.accessibilityLabel = @"悬浮工具栏卡片";
    NSBox *toolbarSizeCard = CardWithViews(@[
        PreferenceRow(@"工具栏缩放", _toolbarScaleButton),
        PreferenceRow(@"工具栏字号", _toolbarFontSizeButton),
    ], 0.0);
    toolbarSizeCard.accessibilityLabel = @"悬浮工具栏尺寸卡片";
    NSScrollView *floatingPage = PreferencesPage(@"悬浮工具栏", @"随时查看输入状态，通过工具栏切换常用输入选项。", @[
        SectionLabel(@"显示与组件"), toolbarCard, SectionLabel(@"尺寸"), toolbarSizeCard,
    ]);

    // ---- 账号 -------------------------------------------------------------------------------
    NSButton *accountButton = [NSButton buttonWithTitle:@"管理水杉账号…" target:self action:@selector(showBackendAccount:)];
    accountButton.accessibilityIdentifier = @"MSIMEClientBackendAccount";
    NSBox *accountCard = CardWithViews(@[PreferenceRow(@"登录与账号管理", accountButton)], 0.0);
    accountCard.accessibilityLabel = @"水杉账号卡片";
    NSScrollView *accountPage = PreferencesPage(@"账号", @"登录水杉账号后，候选词翻译、云同步等需要账号的功能才会生效。", @[
        SectionLabel(@"水杉账号"), accountCard,
    ]);

    // ---- 帮助 / 反馈 -------------------------------------------------------------------------
    // Upstream builds both pages out of its own help copy and a local issue form. This host has
    // neither; it routes to the existing support window instead of inventing the content here.
    NSButton *helpButton = [NSButton buttonWithTitle:@"打开使用帮助…" target:self action:@selector(showSupport:)];
    NSBox *helpCard = CardWithViews(@[PreferenceRow(@"常用按键与常见问题", helpButton)], 0.0);
    helpCard.accessibilityLabel = @"帮助卡片";
    NSScrollView *helpPage = PreferencesPage(@"帮助", @"常用按键、候选词释义的工作方式，以及常见问题。", @[
        SectionLabel(@"使用帮助"), helpCard,
    ]);
    NSButton *feedbackButton = [NSButton buttonWithTitle:@"提交反馈…" target:self action:@selector(showSupport:)];
    NSBox *feedbackCard = CardWithViews(@[PreferenceRow(@"问题反馈与功能建议", feedbackButton)], 0.0);
    feedbackCard.accessibilityLabel = @"反馈卡片";
    NSScrollView *feedbackPage = PreferencesPage(@"反馈", @"在这里写清问题，提交时会带上版本与系统信息。", @[
        SectionLabel(@"问题反馈"), feedbackCard,
    ]);

    // ---- 语音输入 ---------------------------------------------------------------------------
    NSButton *voiceButton = [NSButton buttonWithTitle:@"配置语音输入…" target:self action:@selector(showVoiceSettings:)];
    NSBox *voiceCard = CardWithViews(@[PreferenceRow(@"识别服务与文本整理", voiceButton)], 0.0);
    voiceCard.accessibilityLabel = @"语音输入卡片";
    NSScrollView *voicePage = PreferencesPage(@"语音输入", @"配置听写使用的识别服务，以及识别后的文本整理。", @[
        SectionLabel(@"语音输入"), voiceCard,
    ]);

    // ---- 实用功能 ---------------------------------------------------------------------------
    for (NSArray<NSString *> *entry in LocalModeControls()) {
        NSButton *button = [NSButton checkboxWithTitle:entry[1] target:self action:@selector(localModeChanged:)];
        button.identifier = entry[0];
        [_localModeButtons addObject:button];
    }
    NSBox *localModesCard = CardWithViews(_localModeButtons, 9.0);
    localModesCard.accessibilityLabel = @"扩展输入卡片";
    NSScrollView *utilitiesPage = PreferencesPage(@"实用功能", @"未组词时用 Shift 加一个字母，临时切到另一种输入方式。", @[
        SectionLabel(@"扩展输入模式"), localModesCard,
    ]);

    // The index is both the page index and the navigation button tag. 五笔设置 trails the list:
    // it is a sub-page of 输入, entered from that page's row, so no sidebar item points at it.
    _preferencePages = @[
        generalPage, appearancePage, skinPage, dataPage, aboutPage, wubiPage, helpcodePage, shortcutsPage,
        floatingPage, accountPage, helpPage, feedbackPage, voicePage, utilitiesPage,
    ];

    NSView *contentView = window.contentView;
    NSView *sidebar = [[NSView alloc] initWithFrame:NSZeroRect];
    sidebar.translatesAutoresizingMaskIntoConstraints = NO;
    NSTextField *brand = [NSTextField labelWithString:@"水杉 IME"];
    brand.font = [NSFont systemFontOfSize:19.0 weight:NSFontWeightSemibold];
    NSImageView *logo = [[NSImageView alloc] initWithFrame:NSZeroRect];
    logo.image = [NSImage imageWithSystemSymbolName:@"character.cursor.ibeam" accessibilityDescription:@"水杉 IME"];
    logo.translatesAutoresizingMaskIntoConstraints = NO;
    [logo.widthAnchor constraintEqualToConstant:26.0].active = YES;
    [logo.heightAnchor constraintEqualToConstant:32.0].active = YES;
    NSStackView *brandRow = [NSStackView stackViewWithViews:@[logo, brand]];
    brandRow.spacing = 12.0;
    brandRow.edgeInsets = NSEdgeInsetsMake(0.0, 18.0, 0.0, 0.0);
    NSStackView *navigation = [NSStackView stackViewWithViews:@[brandRow]];
    navigation.orientation = NSUserInterfaceLayoutOrientationVertical;
    navigation.alignment = NSLayoutAttributeLeading;
    navigation.spacing = 2.0;
    navigation.translatesAutoresizingMaskIntoConstraints = NO;
    [navigation setCustomSpacing:30.0 afterView:brandRow];
    NSArray<NSString *> *navigationLabels = @[
        @"输入", @"外观", @"皮肤", @"词库", @"关于", @"五笔", @"辅助码", @"快捷键", @"悬浮工具栏", @"账号", @"帮助",
        @"反馈", @"语音输入", @"实用功能",
    ];
    NSArray<NSString *> *navigationSymbols = @[
        @"keyboard", @"paintpalette", @"photo.on.rectangle", @"book", @"info.circle", @"keyboard", @"a.circle",
        @"command", @"ellipsis.rectangle", @"person.crop.circle", @"questionmark.square", @"ladybug", @"mic",
        @"wand.and.stars",
    ];
    NSArray<NSArray<NSNumber *> *> *navigationGroups = @[
        @[@0, @6, @7, @13, @12],  // 输入 · 辅助码 · 快捷键 · 实用功能 · 语音输入
        @[@1, @2, @8],            // 外观 · 皮肤 · 悬浮工具栏
        @[@3, @9],                // 词库 · 账号
        @[@10, @11, @4],          // 帮助 · 反馈 · 关于
    ];
    NSMutableArray<NSButton *> *navigationButtons = [NSMutableArray array];
    for (NSArray<NSNumber *> *group in navigationGroups) {
        NSButton *lastInGroup = nil;
        for (NSNumber *pageIndex in group) {
            NSInteger index = pageIndex.integerValue;
            NSButton *button = [[MSIMESettingsNavigationButton alloc] initWithFrame:NSZeroRect];
            button.title = navigationLabels[index];
            button.target = self;
            button.action = @selector(selectPreferencesPage:);
            button.tag = index;
            [button setButtonType:NSButtonTypePushOnPushOff];
            button.bordered = NO;
            button.alignment = NSTextAlignmentLeft;
            button.imagePosition = NSImageLeft;
            button.image = [NSImage imageWithSystemSymbolName:navigationSymbols[index] accessibilityDescription:nil];
            button.font = [NSFont systemFontOfSize:14.0 weight:NSFontWeightMedium];
            button.accessibilityLabel = navigationLabels[index];
            [navigation addArrangedSubview:button];
            [button.widthAnchor constraintEqualToAnchor:navigation.widthAnchor].active = YES;
            [button.heightAnchor constraintEqualToConstant:42.0].active = YES;
            [navigationButtons addObject:button];
            lastInGroup = button;
        }
        if (lastInGroup != nil && group != navigationGroups.lastObject)
            [navigation setCustomSpacing:16.0 afterView:lastInGroup];
    }
    _sidebarButtons = navigationButtons;
    [sidebar addSubview:navigation];
    [contentView addSubview:sidebar];
    [NSLayoutConstraint activateConstraints:@[
        [sidebar.leadingAnchor constraintEqualToAnchor:contentView.leadingAnchor],
        [sidebar.topAnchor constraintEqualToAnchor:contentView.topAnchor],
        [sidebar.bottomAnchor constraintEqualToAnchor:contentView.bottomAnchor],
        [sidebar.widthAnchor constraintEqualToConstant:220.0],
        [navigation.leadingAnchor constraintEqualToAnchor:sidebar.leadingAnchor constant:10.0],
        [navigation.trailingAnchor constraintEqualToAnchor:sidebar.trailingAnchor constant:-10.0],
        [navigation.topAnchor constraintEqualToAnchor:sidebar.topAnchor constant:30.0],
    ]];

    NSView *pageContainer = [[NSView alloc] initWithFrame:NSZeroRect];
    pageContainer.translatesAutoresizingMaskIntoConstraints = NO;
    [contentView addSubview:pageContainer];
    for (NSView *page in _preferencePages) {
        [pageContainer addSubview:page];
        [NSLayoutConstraint activateConstraints:@[
            [page.leadingAnchor constraintEqualToAnchor:pageContainer.leadingAnchor],
            [page.trailingAnchor constraintEqualToAnchor:pageContainer.trailingAnchor],
            [page.topAnchor constraintEqualToAnchor:pageContainer.topAnchor],
            [page.bottomAnchor constraintEqualToAnchor:pageContainer.bottomAnchor],
        ]];
    }
    NSButton *restoreButton = [NSButton buttonWithTitle:@"恢复默认设置" target:self action:@selector(restoreDefaults:)];
    restoreButton.bezelStyle = NSBezelStyleRounded;
    restoreButton.translatesAutoresizingMaskIntoConstraints = NO;
    NSButton *closeButton = [NSButton buttonWithTitle:@"关闭" target:self action:@selector(closePreferences:)];
    closeButton.bezelStyle = NSBezelStyleRounded;
    closeButton.keyEquivalent = @"\r";
    closeButton.translatesAutoresizingMaskIntoConstraints = NO;
    [contentView addSubview:restoreButton];
    [contentView addSubview:closeButton];
    [NSLayoutConstraint activateConstraints:@[
        [pageContainer.leadingAnchor constraintEqualToAnchor:sidebar.trailingAnchor],
        [pageContainer.trailingAnchor constraintEqualToAnchor:contentView.trailingAnchor],
        [pageContainer.topAnchor constraintEqualToAnchor:contentView.topAnchor],
        [pageContainer.bottomAnchor constraintEqualToAnchor:restoreButton.topAnchor constant:-16.0],
        [restoreButton.leadingAnchor constraintEqualToAnchor:pageContainer.leadingAnchor constant:30.0],
        [restoreButton.bottomAnchor constraintEqualToAnchor:contentView.bottomAnchor constant:-20.0],
        [closeButton.trailingAnchor constraintEqualToAnchor:contentView.trailingAnchor constant:-30.0],
        [closeButton.centerYAnchor constraintEqualToAnchor:restoreButton.centerYAnchor],
        [closeButton.widthAnchor constraintGreaterThanOrEqualToConstant:80.0],
    ]];
    self.window = window;
    [self showPreferencesPageAtIndex:0 navigationIndex:0];
    [self refreshUpdateControls];
    [self refreshControls];
    [window center];
}
- (void)layoutChanged:(NSPopUpButton *)sender { self.vertical = sender.indexOfSelectedItem == 1; }
- (void)candidateFollowCursorChanged:(NSButton *)sender { self.candidateFollowCursor = sender.state == NSControlStateValueOn; }
- (void)transpositionChanged:(NSButton *)sender { self.autocorrectTransposition = sender.state == NSControlStateValueOn; }
- (void)neighborChanged:(NSButton *)sender { self.autocorrectNeighbor = sender.state == NSControlStateValueOn; }
- (void)candidateLearningChanged:(NSButton *)sender { self.candidateLearningEnabled = sender.state == NSControlStateValueOn; }
- (void)frequencyModeChanged:(NSPopUpButton *)sender { self.frequencyAdjustmentMode = FrequencyModes()[sender.indexOfSelectedItem]; }
- (void)frequencyTriggerChanged:(NSPopUpButton *)sender { self.frequencyTriggerCount = sender.indexOfSelectedItem + 1; }
- (void)frequencyStepChanged:(NSPopUpButton *)sender { self.frequencyLinearStep = sender.indexOfSelectedItem + 1; }
- (void)cloudCandidatesChanged:(NSButton *)sender { self.cloudCandidates = sender.state == NSControlStateValueOn; }
- (void)candidateTranslationsChanged:(NSButton *)sender { self.candidateTranslations = sender.state == NSControlStateValueOn; }
- (void)candidateEnglishGlossChanged:(NSButton *)sender { self.candidateEnglishGloss = sender.state == NSControlStateValueOn; }
- (void)quanpinHelpcodeChanged:(NSButton *)sender { self.quanpinHelpcodeEnabled = sender.state == NSControlStateValueOn; }
- (void)shuangpinHelpcodeChanged:(NSButton *)sender { self.shuangpinHelpcodeEnabled = sender.state == NSControlStateValueOn; }
- (void)profileChanged:(NSPopUpButton *)sender { self.shuangpinProfile = @[@"xiaohe", @"ziranma", @"shoudao", @"microsoft"][sender.indexOfSelectedItem]; }
- (void)preeditChanged:(NSPopUpButton *)sender { self.shuangpinPreeditUsesRaw = sender.indexOfSelectedItem == 1; }
- (void)inputModeShortcutChanged:(NSButton *)sender { self.inputModeShortcut = sender.state == NSControlStateValueOn; }
- (void)defaultImeModeChanged:(NSPopUpButton *)sender { self.defaultImeMode = sender.indexOfSelectedItem == 1 ? @"english" : @"chinese"; }
- (void)imeModeScopeChanged:(NSPopUpButton *)sender { self.imeModeScope = sender.indexOfSelectedItem == 1 ? @"global" : @"app"; }
- (void)shiftTapShortcutChanged:(NSButton *)sender { self.shiftTapShortcut = sender.state == NSControlStateValueOn; }
- (void)controlTapShortcutChanged:(NSButton *)sender { self.controlTapShortcut = sender.state == NSControlStateValueOn; }
- (void)controlOptionSpaceShortcutChanged:(NSButton *)sender { self.controlOptionSpaceShortcut = sender.state == NSControlStateValueOn; }
- (void)characterSetShortcutChanged:(NSButton *)sender { self.characterSetShortcut = sender.state == NSControlStateValueOn; }
- (void)fullWidthChanged:(NSButton *)sender { self.fullWidthInput = sender.state == NSControlStateValueOn; }
- (void)keymapChanged:(NSButton *)sender { self.shuangpinKeymap = sender.state == NSControlStateValueOn; }
- (void)wubiChanged:(NSButton *)sender { self.wubiAutoCommitUnique = sender.state == NSControlStateValueOn; }
- (void)punctuationChanged:(NSButton *)sender { self.chinesePunctuation = sender.state == NSControlStateValueOn; }
- (void)smartPunctuationChanged:(NSButton *)sender { self.smartPunctuation = sender.state == NSControlStateValueOn; }
- (void)smartPunctuationRepeatChanged:(NSButton *)sender { self.smartPunctuationRepeatToChinese = sender.state == NSControlStateValueOn; }
- (void)pairedPunctuationChanged:(NSButton *)sender { self.pairedPunctuation = sender.state == NSControlStateValueOn; }
- (void)punctuationLockChanged:(NSPopUpButton *)sender { self.punctuationLock = @[@"follow", @"chinese", @"english"][sender.indexOfSelectedItem]; }
- (void)mixedEnglishChanged:(NSButton *)sender { self.mixedEnglishInput = sender.state == NSControlStateValueOn; }
- (void)mixedEnglishPrefixChanged:(NSPopUpButton *)sender { self.mixedEnglishMinimumPrefix = sender.indexOfSelectedItem + 1; }
- (void)mixedEmojiChanged:(NSButton *)sender { self.mixedEmojiInput = sender.state == NSControlStateValueOn; }
- (void)mixedKaomojiChanged:(NSButton *)sender { self.mixedKaomojiInput = sender.state == NSControlStateValueOn; }
- (void)toolbarChanged:(NSButton *)sender { self.floatingToolbarEnabled = sender.state == NSControlStateValueOn; }
- (void)toolbarPunctuationChanged:(NSButton *)sender { self.floatingToolbarPunctuation = sender.state == NSControlStateValueOn; }
- (void)toolbarFullWidthChanged:(NSButton *)sender { self.floatingToolbarFullWidth = sender.state == NSControlStateValueOn; }
- (void)toolbarCharacterSetChanged:(NSButton *)sender { self.floatingToolbarCharacterSet = sender.state == NSControlStateValueOn; }
- (void)toolbarEmojiChanged:(NSButton *)sender { self.floatingToolbarEmoji = sender.state == NSControlStateValueOn; }
- (void)toolbarScreenKeyboardChanged:(NSButton *)sender { self.floatingToolbarScreenKeyboard = sender.state == NSControlStateValueOn; }
- (void)toolbarSettingsChanged:(NSButton *)sender { self.floatingToolbarSettings = sender.state == NSControlStateValueOn; }
- (void)toolbarScaleChanged:(NSPopUpButton *)sender { self.floatingToolbarScalePercent = [@[@75, @100, @125, @150][sender.indexOfSelectedItem] integerValue]; }
- (void)toolbarFontSizeChanged:(NSPopUpButton *)sender { self.floatingToolbarFontSize = 16 + sender.indexOfSelectedItem * 2; }
- (NSWindowController *)skinCatalogController {
    if (!_skinWindow) {
        NSWindow *window = [[NSWindow alloc] initWithContentRect:NSMakeRect(0, 0, 700, 720) styleMask:NSWindowStyleMaskTitled | NSWindowStyleMaskClosable backing:NSBackingStoreBuffered defer:NO];
        window.title = @"皮肤";
        window.releasedWhenClosed = NO;
        MetasequoiaSkinSettingsView *cards = [[MetasequoiaSkinSettingsView alloc] initWithFrame:NSZeroRect preferences:self];
        [window.contentView addSubview:cards];
        [NSLayoutConstraint activateConstraints:@[
            [cards.leadingAnchor constraintEqualToAnchor:window.contentView.leadingAnchor],
            [cards.trailingAnchor constraintEqualToAnchor:window.contentView.trailingAnchor],
            [cards.topAnchor constraintEqualToAnchor:window.contentView.topAnchor],
            [cards.bottomAnchor constraintEqualToAnchor:window.contentView.bottomAnchor]
        ]];
        _skinWindow = [[NSWindowController alloc] initWithWindow:window];
        [window center];
    } else {
        [(MetasequoiaSkinSettingsView *)_skinWindow.window.contentView.subviews.firstObject reload];
    }
    return _skinWindow;
}
- (void)showSkinCatalog:(id)sender {
    __weak MSIMEAppearancePreferences *weakSelf = self;
    MSIMEOpenDesktopSettings(MSIMEDesktopSettingsPage::Skin, [self desktopSettingsWorkspace], ^{
        MSIMEAppearancePreferences *strongSelf = weakSelf;
        if (strongSelf) [[strongSelf skinCatalogController] showWindow:sender];
    });
}
- (void)togglePreviewTheme:(id)sender { (void)sender; [_preview toggleForcedTheme]; }
- (void)togglePreviewShowcase:(NSButton *)sender { [_preview setShowsLayoutShowcase:sender.state == NSControlStateValueOn]; }
- (void)selectPreferencesPage:(id)sender {
    NSButton *button = [sender isKindOfClass:NSButton.class] ? (NSButton *)sender : nil;
    const NSInteger index = button == nil ? 0 : button.tag;
    [self showPreferencesPageAtIndex:index navigationIndex:index];
}
- (void)showPreferencesPageAtIndex:(NSInteger)pageIndex navigationIndex:(NSInteger)navigationIndex {
    for (NSInteger index = 0; index < (NSInteger)_preferencePages.count; ++index)
        _preferencePages[index].hidden = index != pageIndex;
    for (NSButton *button in _sidebarButtons)
        button.state = button.tag == navigationIndex ? NSControlStateValueOn : NSControlStateValueOff;
}
// 五笔设置是「输入」页的子页,靠页内按钮进出,所以侧边栏保持停在「输入」上。
- (void)showWubiSettings:(id)sender {
    (void)sender;
    [self refreshControls];
    [self showPreferencesPageAtIndex:5 navigationIndex:0];
}
- (void)backToKeyboardInput:(id)sender {
    (void)sender;
    [self showPreferencesPageAtIndex:0 navigationIndex:0];
}
- (void)schemeRadioChanged:(NSButton *)sender {
    self.inputScheme = @[@"quanpin", @"shuangpin", @"wubi", @"japanese"][sender.tag];
}
- (void)showBackendAccount:(id)sender {
    (void)sender;
    MSIMEOpenBackendAccount(NSClassFromString(@"MSIMEBackendAccountWindow"));
}
- (void)showSupport:(id)sender {
    (void)sender;
    Class supportClass = NSClassFromString(@"MSIMESupportWindowController");
    if (![supportClass respondsToSelector:@selector(sharedController)]) return;
    [[supportClass sharedController] showWindow:self];
    [NSApp activateIgnoringOtherApps:YES];
}
- (void)showVoiceSettings:(id)sender {
    (void)sender;
    Class voiceClass = NSClassFromString(@"MSIMEVoiceSettings");
    if (![voiceClass respondsToSelector:@selector(sharedSettings)]) return;
    [[voiceClass sharedSettings] showWindow:self];
    [NSApp activateIgnoringOtherApps:YES];
}
- (void)openProductWebsite:(id)sender {
    (void)sender;
    [NSWorkspace.sharedWorkspace openURL:[NSURL URLWithString:@"https://msime.app"]];
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
- (void)restoreDefaults:(id)sender {
    (void)sender;
    for (NSString *key in @[
             LayoutKey, CandidateFollowCursorKey, InputModeHUDKey, SchemeKey, ShuangpinProfileKey,
             ShuangpinPreeditKey, LocalModesKey, HelpcodeKey, HelpcodeOptionsKey, QuanpinHelpcodeKey,
             ShuangpinHelpcodeKey, KeymapKey, WubiKey, InputModeShortcutKey, ShiftTapShortcutKey,
             ControlTapShortcutKey, ControlOptionSpaceShortcutKey, CharacterSetShortcutKey,
             FloatingToolbarKey, FloatingToolbarOptionsKey,
         ])
        [_defaults removeObjectForKey:key];
    [self refreshControls];
    [NSNotificationCenter.defaultCenter postNotificationName:MSIMEAppearanceDidChangeNotification object:self];
}
- (void)closePreferences:(id)sender {
    (void)sender;
    [self.window performClose:nil];
}
- (void)skinChanged:(NSPopUpButton *)sender {
    self.skinID = sender.selectedItem.representedObject ?: @"fluent";
}
- (void)reloadSkinsFromButton:(id)sender { (void)sender; [self reloadSkins]; }
- (void)showWindow:(id)sender { [self reloadSkins]; [super showWindow:sender]; }
- (void)pageShortcutChanged:(NSPopUpButton *)sender { self.pageShortcut = sender.indexOfSelectedItem; }
- (void)navigationChanged:(NSButton *)sender { [self setNavigation:sender.identifier enabled:sender.state == NSControlStateValueOn]; }
- (void)wordCharacterChanged:(id)sender {
    (void)sender;
    [self setWordCharacterEnabled:_wordCharacterButton.state == NSControlStateValueOn keys:_wordCharacterKeys.indexOfSelectedItem == 1 ? @"minus_equal" : @"brackets"];
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
