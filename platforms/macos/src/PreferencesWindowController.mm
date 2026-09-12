extern "C" void MSIMEShowBackendAccount(void);
// Implemented in CandidateTranslationBridge.swift.
extern "C" bool MSIMEBackendAccountSignedIn(void);

#import "PreferencesWindowController.h"

#include "CandidateFontSize.h"
#include "CandidatePageSize.h"
#include "CandidatePanelStyle.h"
#include "CandidateSkin.h"
#include "FrequencyAdjustmentPreference.h"
#include "HelpcodeSchemaPreference.h"
#include "InputControllerKeyRouting.h"
#include "InputBehaviorPreferences.h"
#include "CandidateTranslationLanguage.h"
#include "InputSchemePreference.h"
#import "CandidateSkinAppearance.h"
#import "CandidateSkinPreviewView.h"
#import "DictionaryInstaller.h"
#import "SkinSettingsView.h"
#import "UpdateController.h"
#import "VoiceSettings.h"

#include <cstring>

@interface MetasequoiaPreferencesDocumentView : NSView
@end
@implementation MetasequoiaPreferencesDocumentView
- (BOOL)isFlipped
{
    return YES;
}
@end

@interface MetasequoiaSettingsSurface : NSView
@end
@implementation MetasequoiaSettingsSurface
- (void)drawRect:(NSRect)rect
{
    BOOL dark = [[self.effectiveAppearance
        bestMatchFromAppearancesWithNames:@[ NSAppearanceNameAqua, NSAppearanceNameDarkAqua ]]
        isEqualToString:NSAppearanceNameDarkAqua];
    [(dark ? [NSColor colorWithWhite:0.12 alpha:1.0] : [NSColor colorWithWhite:0.96 alpha:1.0]) setFill];
    NSRectFill(rect);
}
@end

@interface MetasequoiaSettingsNavigationButton : NSButton
@end
@implementation MetasequoiaSettingsNavigationButton
- (void)drawRect:(NSRect)rect
{
    (void)rect;
    if (self.state == NSControlStateValueOn)
    {
        [[[NSColor labelColor] colorWithAlphaComponent:0.06] setFill];
        [[NSBezierPath bezierPathWithRoundedRect:NSInsetRect(self.bounds, 0.0, 2.0) xRadius:6.0 yRadius:6.0] fill];
        [[NSColor colorWithSRGBRed:0.45 green:0.42 blue:0.77 alpha:1.0] setFill];
        [[NSBezierPath bezierPathWithRoundedRect:NSMakeRect(0.0, 12.0, 3.0, NSHeight(self.bounds) - 24.0)
                                         xRadius:1.5
                                         yRadius:1.5] fill];
    }
    NSImage *symbol =
        [self.image imageWithSymbolConfiguration:[NSImageSymbolConfiguration
                                                     configurationWithPaletteColors:@[ [NSColor labelColor] ]]];
    [symbol drawInRect:NSMakeRect(19.0, (NSHeight(self.bounds) - 20.0) / 2.0, 20.0, 20.0)];
    NSDictionary *attributes =
        @{NSFontAttributeName : [NSFont systemFontOfSize:16.0], NSForegroundColorAttributeName : [NSColor labelColor]};
    NSSize size = [self.title sizeWithAttributes:attributes];
    [self.title drawAtPoint:NSMakePoint(57.0, (NSHeight(self.bounds) - size.height) / 2.0) withAttributes:attributes];
    if (self.window.firstResponder == self)
    {
        [[NSColor keyboardFocusIndicatorColor] setStroke];
        [[NSBezierPath bezierPathWithRoundedRect:NSInsetRect(self.bounds, 1.0, 2.0) xRadius:6.0 yRadius:6.0] stroke];
    }
}
@end

NSNotificationName const MetasequoiaWillResetLearnedDataNotification = @"MetasequoiaWillResetLearnedDataNotification";
NSNotificationName const MetasequoiaStandalonePreferencesDidCloseNotification =
    @"MetasequoiaStandalonePreferencesDidCloseNotification";
NSNotificationName const MetasequoiaFloatingToolbarDidChangeNotification =
    @"MetasequoiaFloatingToolbarDidChangeNotification";
NSNotificationName const MetasequoiaTraditionalChineseOutputDidChangeNotification =
    @"MetasequoiaTraditionalChineseOutputDidChangeNotification";

bool MetasequoiaShouldShowPreferences(int argc, const char *argv[])
{
    return argc == 2 && argv != nullptr && argv[1] != nullptr && std::strcmp(argv[1], "--show-settings") == 0;
}

namespace
{
constexpr CGFloat kWindowWidth = 980.0;
constexpr CGFloat kWindowHeight = 800.0;
NSString *const kSchemePreferenceKey = @"MetasequoiaImeInputScheme";
NSString *const kShuangpinSchemaPreferenceKey = @"MetasequoiaImeShuangpinSchema";
NSString *const kAutocorrectPreferenceKey = @"MetasequoiaImeQuanpinAutocorrect";
NSString *const kHelpcodePreferenceKey = @"MetasequoiaImeHelpcodeEnabled";
NSString *const kQuanpinHelpcodeSchemaPreferenceKey = @"MetasequoiaImeQuanpinHelpcodeSchema";
NSString *const kShuangpinHelpcodeSchemaPreferenceKey = @"MetasequoiaImeShuangpinHelpcodeSchema";
NSString *const kChinesePunctuationPreferenceKey = @"MetasequoiaImeChinesePunctuation";
NSString *const kCandidatePanelStylePreferenceKey = @"MetasequoiaImeCandidatePanelStyle";
NSString *const kCandidatePageSizePreferenceKey = @"MetasequoiaImeCandidatePageSize";
NSString *const kCandidateFontSizePreferenceKey = @"MetasequoiaImeCandidateFontSize";
NSString *const kCandidateTranslationsPreferenceKey = @"MetasequoiaImeCandidateTranslationsEnabled";
NSString *const kCandidatePageShortcutPreferenceKey = @"MetasequoiaImeCandidatePageShortcut";
NSString *const kCandidateLearningPreferenceKey = @"MetasequoiaImeCandidateLearning";
NSString *const kFrequencyAdjustmentModePreferenceKey = @"MetasequoiaImeFrequencyAdjustmentMode";
NSString *const kFrequencyTriggerCountPreferenceKey = @"MetasequoiaImeFrequencyTriggerCount";
NSString *const kFrequencyLinearStepPreferenceKey = @"MetasequoiaImeFrequencyLinearStep";
NSString *const kEnglishInputModePreferenceKey = @"MetasequoiaImeEnglishInputMode";
NSString *const kInputModeShortcutPreferenceKey = @"MetasequoiaImeInputModeShortcutEnabled";
// Absent from the cloud snapshot until the backend schema declares it, like the wubi keys below.
NSString *const kInputModeHUDPreferenceKey = @"MetasequoiaImeInputModeHUD";
NSString *const kFullWidthInputPreferenceKey = @"MetasequoiaImeFullWidthInputEnabled";
NSString *const kFloatingToolbarPreferenceKey = @"MetasequoiaImeFloatingToolbarEnabled";
NSString *const kTraditionalChineseOutputPreferenceKey = @"MetasequoiaImeTraditionalChineseOutput";
NSString *const kWubiAutoCommitUniquePreferenceKey = @"MetasequoiaImeWubiAutoCommitUnique";
// Deliberately absent from the cloud snapshot until the backend schema declares it:
// mergedPreferences rejects the whole upload with 503 for any key the schema does not
// know, and the download side refuses a snapshot whose key count does not match, so
// syncing this early would break settings sync entirely rather than just this option.
NSString *const kWubiMixedPinyinPreferenceKey = @"MetasequoiaImeWubiMixedPinyin";
// Absent from the cloud snapshot for the same reason as the key above.
NSString *const kWubiCodeHintPreferenceKey = @"MetasequoiaImeWubiCodeHint";
NSString *const kShuangpinKeymapPreferenceKey = @"MetasequoiaImeShuangpinKeymapEnabled";
NSString *const kLocalInputModesPreferenceKey = @"MetasequoiaImeLocalInputModesEnabled";

void ConfigureCard(NSBox *card)
{
    card.boxType = NSBoxCustom;
    card.titlePosition = NSNoTitle;
    card.borderWidth = 0.5;
    card.cornerRadius = 12.0;
    card.borderColor = [NSColor separatorColor];
    card.fillColor = [NSColor controlBackgroundColor];
    card.translatesAutoresizingMaskIntoConstraints = NO;
}

NSTextField *SectionLabel(NSString *title)
{
    NSTextField *label = [NSTextField labelWithString:title];
    label.font = [NSFont systemFontOfSize:11.0 weight:NSFontWeightSemibold];
    label.textColor = [NSColor secondaryLabelColor];
    return label;
}

NSView *PreferenceRow(NSString *title, NSView *control)
{
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

NSView *CardHeader(NSString *title)
{
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

NSBox *CardSeparator()
{
    NSBox *separator = [[NSBox alloc] initWithFrame:NSZeroRect];
    separator.boxType = NSBoxSeparator;
    separator.translatesAutoresizingMaskIntoConstraints = NO;
    [separator.heightAnchor constraintEqualToConstant:1.0].active = YES;
    return separator;
}

NSView *SchemeChoiceRow(NSButton *choice, NSView *accessory)
{
    NSView *row = [[NSView alloc] initWithFrame:NSZeroRect];
    choice.translatesAutoresizingMaskIntoConstraints = NO;
    [row addSubview:choice];
    NSMutableArray<NSLayoutConstraint *> *constraints = [NSMutableArray arrayWithArray:@[
        [row.heightAnchor constraintEqualToConstant:44.0],
        [choice.leadingAnchor constraintEqualToAnchor:row.leadingAnchor],
        [choice.centerYAnchor constraintEqualToAnchor:row.centerYAnchor],
    ]];
    if (accessory == nil)
    {
        [constraints addObject:[choice.trailingAnchor constraintLessThanOrEqualToAnchor:row.trailingAnchor]];
    }
    else
    {
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

NSBox *CardWithViews(NSArray<NSView *> *views, CGFloat spacing)
{
    NSBox *card = [[NSBox alloc] initWithFrame:NSZeroRect];
    ConfigureCard(card);
    NSStackView *stack = [NSStackView stackViewWithViews:views];
    stack.orientation = NSUserInterfaceLayoutOrientationVertical;
    stack.alignment = NSLayoutAttributeLeading;
    stack.distribution = NSStackViewDistributionFill;
    stack.spacing = spacing;
    stack.translatesAutoresizingMaskIntoConstraints = NO;
    for (NSView *view in views)
    {
        [view.widthAnchor constraintEqualToAnchor:stack.widthAnchor].active = YES;
    }
    [card addSubview:stack];
    [NSLayoutConstraint activateConstraints:@[
        [stack.leadingAnchor constraintEqualToAnchor:card.leadingAnchor constant:16.0],
        [stack.trailingAnchor constraintEqualToAnchor:card.trailingAnchor constant:-16.0],
        [stack.topAnchor constraintEqualToAnchor:card.topAnchor constant:12.0],
        [stack.bottomAnchor constraintEqualToAnchor:card.bottomAnchor constant:-12.0],
    ]];
    return card;
}

NSView *PreferencesPage(NSString *title, NSString *summary, NSArray<NSView *> *content)
{
    NSScrollView *page = [[NSScrollView alloc] initWithFrame:NSZeroRect];
    page.translatesAutoresizingMaskIntoConstraints = NO;
    page.hasVerticalScroller = YES;
    page.autohidesScrollers = YES;
    page.drawsBackground = NO;
    NSTextField *titleLabel = [NSTextField labelWithString:title];
    titleLabel.font = [NSFont systemFontOfSize:24.0 weight:NSFontWeightSemibold];
    page.accessibilityHelp = summary;
    NSStackView *stack = [NSStackView stackViewWithViews:@[ titleLabel ]];
    stack.orientation = NSUserInterfaceLayoutOrientationVertical;
    stack.alignment = NSLayoutAttributeLeading;
    stack.distribution = NSStackViewDistributionFill;
    stack.spacing = 18.0;
    for (NSView *view in content)
    {
        [stack addArrangedSubview:view];
        [view.widthAnchor constraintEqualToAnchor:stack.widthAnchor].active = YES;
    }
    [stack setCustomSpacing:30.0 afterView:titleLabel];
    stack.translatesAutoresizingMaskIntoConstraints = NO;
    NSView *document = [[MetasequoiaPreferencesDocumentView alloc] initWithFrame:NSZeroRect];
    document.translatesAutoresizingMaskIntoConstraints = NO;
    page.documentView = document;
    [document addSubview:stack];
    [NSLayoutConstraint activateConstraints:@[
        [document.widthAnchor constraintEqualToAnchor:page.contentView.widthAnchor],
        [document.heightAnchor constraintGreaterThanOrEqualToAnchor:page.contentView.heightAnchor],
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
} // namespace

@interface MetasequoiaPreferencesWindowController ()
- (void)updateFrequencyControlEnabled;
@end

@implementation MetasequoiaPreferencesWindowController
{
    NSArray<NSButton *> *_schemeButtons;
    NSPopUpButton *_shuangpinSchemeButton;
    NSPopUpButton *_wubiSchemeButton;
    NSButton *_shuangpinKeymapButton;
    NSView *_shuangpinKeymapRow;
    NSView *_shuangpinKeymapSeparator;
    NSView *_wubiSettingsRow;
    NSButton *_autocorrectButton;
    NSButton *_helpcodeButton;
    NSButton *_shuangpinHelpcodeEnabledButton;
    NSButton *_quanpinHelpcodeHintsButton;
    NSButton *_shuangpinHelpcodeHintsButton;
    NSButton *_localInputModesButton;
    NSPopUpButton *_quanpinHelpcodeSchemaButton;
    NSPopUpButton *_shuangpinHelpcodeSchemaButton;
    NSButton *_chinesePunctuationButton;
    NSPopUpButton *_candidatePanelStyleButton;
    NSPopUpButton *_candidatePageSizeButton;
    NSPopUpButton *_candidateFontSizeButton;
    NSButton *_candidateTranslationsButton;
    NSPopUpButton *_candidateFontButton;
    NSPopUpButton *_candidateFallbackFontButton;
    NSPopUpButton *_preeditFontSizeButton;
    NSPopUpButton *_themeButton;
    NSSwitch *_followCaretSwitch;
    NSColorWell *_candidateColorWell;
    NSPopUpButton *_candidatePageShortcutButton;
    NSMutableArray<NSButton *> *_inputBehaviorButtons;
    NSPopUpButton *_englishMinimumPrefixButton;
    NSPopUpButton *_defaultInputModeButton;
    NSPopUpButton *_inputModeScopeButton;
    NSPopUpButton *_outputScriptButton;
    NSPopUpButton *_languageModeButton;
    NSButton *_alwaysChinesePunctuationButton;
    NSButton *_alwaysEnglishPunctuationButton;
    NSButton *_smartPunctuationButton;
    NSButton *_pairedPunctuationButton;
    NSButton *_repeatPunctuationButton;
    NSButton *_candidateTranslationButton;
    NSButton *_cloudCandidatesButton;
    NSPopUpButton *_translationProviderButton;
    NSPopUpButton *_translationLanguageButton;
    NSTextField *_translationSecretIdField;
    NSSecureTextField *_translationSecretKeyField;
    NSTextField *_translationEndpointField;
    NSView *_translationTencentIdRow;
    NSView *_translationTencentKeyRow;
    NSView *_translationEndpointRow;
    NSView *_translationAccountRow;
    NSTextField *_translationAccountLabel;
    NSButton *_translationAccountButton;
    MetasequoiaCandidatePreviewView *_candidatePreview;
    MetasequoiaSkinSettingsView *_skinSettings;
    NSButton *_candidateLearningButton;
    NSPopUpButton *_frequencyModeButton;
    NSPopUpButton *_frequencyTriggerCountButton;
    NSPopUpButton *_frequencyLinearStepButton;
    NSButton *_inputModeShortcutButton;
    NSButton *_inputModeHUDButton;
    NSButton *_fullWidthInputButton;
    NSButton *_floatingToolbarButton;
    NSButton *_wubiAutoCommitButton;
    NSButton *_wubiMixedPinyinButton;
    NSButton *_wubiCodeHintButton;
    NSButton *_resetLearningButton;
    NSTextField *_statusLabel;
    NSTextField *_versionLabel;
    NSTextField *_automaticUpdateLabel;
    NSButton *_updatePageButton;
    NSArray<NSView *> *_preferencePages;
    NSArray<NSButton *> *_navigationButtons;
    MetasequoiaUpdateController *_updateController;
    BOOL _standaloneLaunch;
}

+ (instancetype)sharedController
{
    static MetasequoiaPreferencesWindowController *controller = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
      controller = [[self alloc] init];
    });
    return controller;
}

+ (void)prepareInputSessionsForLearnedDataReset
{
    [[NSNotificationCenter defaultCenter] postNotificationName:MetasequoiaWillResetLearnedDataNotification object:nil];
}

+ (NSDictionary<NSString *, id> *)cloudSettingsSnapshot
{
    return @{
        @"platform.macos.candidate_skin" : [self storedCandidateSkin],
        @"platform.macos.input_scheme" : @([self storedScheme]),
        @"platform.macos.quanpin_helpcode_schema" : @([self storedQuanpinHelpcodeSchema]),
        @"platform.macos.shuangpin_helpcode_schema" : @([self storedShuangpinHelpcodeSchema]),
        @"platform.macos.candidate_panel_style" : @([self storedCandidatePanelStyle]),
        // Expanded local values are not sent to the older cloud enum contract.
        @"platform.macos.candidate_page_size" :
            @([@[ @5, @7, @9 ]
                  containsObject:[NSUserDefaults.standardUserDefaults objectForKey:kCandidatePageSizePreferenceKey]]
                  ? [NSUserDefaults.standardUserDefaults integerForKey:kCandidatePageSizePreferenceKey]
                  : 9),
        @"platform.macos.candidate_font_size" :
            @([@[ @16, @18, @20 ]
                  containsObject:[NSUserDefaults.standardUserDefaults objectForKey:kCandidateFontSizePreferenceKey]]
                  ? [NSUserDefaults.standardUserDefaults integerForKey:kCandidateFontSizePreferenceKey]
                  : 18),
        @"platform.macos.candidate_page_shortcut" : @([self storedCandidatePageShortcut]),
        @"platform.macos.autocorrect" : @([self storedAutocorrectEnabled]),
        @"platform.macos.helpcode" : @([self storedHelpcodeEnabled]),
        @"platform.macos.chinese_punctuation" : @([self storedChinesePunctuationEnabled]),
        @"platform.macos.candidate_learning" : @([self storedCandidateLearningEnabled]),
        @"platform.macos.english_input_mode" : @([self storedEnglishInputMode]),
        @"platform.macos.input_mode_shortcut" : @([self storedInputModeShortcutEnabled]),
        @"platform.macos.full_width_input" : @([self storedFullWidthInputEnabled]),
        @"platform.macos.floating_toolbar" : @([self storedFloatingToolbarEnabled]),
        @"platform.macos.traditional_chinese_output" : @([self storedTraditionalChineseOutputEnabled]),
        @"platform.macos.wubi_auto_commit_unique" : @([self storedWubiAutoCommitUniqueEnabled]),
        @"platform.macos.shuangpin_keymap" : @([self storedShuangpinKeymapEnabled]),
        @"platform.macos.local_input_modes" : @([self storedLocalInputModesEnabled]),
    };
}

+ (NSNumber *)validateCloudSettingsSnapshot:(NSDictionary<NSString *, id> *)values
{
    if (![NSThread isMainThread] || ![values isKindOfClass:[NSDictionary class]] || values.count != 20)
        return @NO;
    NSString *skin = values[@"platform.macos.candidate_skin"];
    if (![skin isKindOfClass:NSString.class] || skin.UTF8String == nullptr ||
        !metasequoia::mac::IsSafeSkinId(
            std::string_view(skin.UTF8String, [skin lengthOfBytesUsingEncoding:NSUTF8StringEncoding])))
        return @NO;
    {
        NSNumber *value = values[@"platform.macos.input_scheme"];
        if (![value isKindOfClass:[NSNumber class]])
            return @NO;
        if (CFGetTypeID((__bridge CFTypeRef)value) == CFBooleanGetTypeID() || value.doubleValue != value.integerValue ||
            ![@[ @0, @1, @2 ] containsObject:value])
            return @NO;
    }
    {
        NSNumber *value = values[@"platform.macos.quanpin_helpcode_schema"];
        if (![value isKindOfClass:[NSNumber class]])
            return @NO;
        if (CFGetTypeID((__bridge CFTypeRef)value) == CFBooleanGetTypeID() || value.doubleValue != value.integerValue ||
            ![@[ @0, @1, @2, @3, @4 ] containsObject:value])
            return @NO;
    }
    {
        NSNumber *value = values[@"platform.macos.shuangpin_helpcode_schema"];
        if (![value isKindOfClass:[NSNumber class]])
            return @NO;
        if (CFGetTypeID((__bridge CFTypeRef)value) == CFBooleanGetTypeID() || value.doubleValue != value.integerValue ||
            ![@[ @0, @1, @2, @3, @4 ] containsObject:value])
            return @NO;
    }
    {
        NSNumber *value = values[@"platform.macos.candidate_panel_style"];
        if (![value isKindOfClass:[NSNumber class]])
            return @NO;
        if (CFGetTypeID((__bridge CFTypeRef)value) == CFBooleanGetTypeID() || value.doubleValue != value.integerValue ||
            ![@[ @0, @1 ] containsObject:value])
            return @NO;
    }
    {
        NSNumber *value = values[@"platform.macos.candidate_page_size"];
        if (![value isKindOfClass:[NSNumber class]])
            return @NO;
        if (CFGetTypeID((__bridge CFTypeRef)value) == CFBooleanGetTypeID() || value.doubleValue != value.integerValue ||
            ![@[ @5, @7, @9 ] containsObject:value])
            return @NO;
    }
    {
        NSNumber *value = values[@"platform.macos.candidate_font_size"];
        if (![value isKindOfClass:[NSNumber class]])
            return @NO;
        if (CFGetTypeID((__bridge CFTypeRef)value) == CFBooleanGetTypeID() || value.doubleValue != value.integerValue ||
            ![@[ @16, @18, @20 ] containsObject:value])
            return @NO;
    }
    {
        NSNumber *value = values[@"platform.macos.candidate_page_shortcut"];
        if (![value isKindOfClass:[NSNumber class]])
            return @NO;
        if (CFGetTypeID((__bridge CFTypeRef)value) == CFBooleanGetTypeID() || value.doubleValue != value.integerValue ||
            ![@[ @0, @1, @2 ] containsObject:value])
            return @NO;
    }
    {
        NSNumber *value = values[@"platform.macos.autocorrect"];
        if (![value isKindOfClass:[NSNumber class]])
            return @NO;
        if (CFGetTypeID((__bridge CFTypeRef)value) != CFBooleanGetTypeID())
            return @NO;
    }
    {
        NSNumber *value = values[@"platform.macos.helpcode"];
        if (![value isKindOfClass:[NSNumber class]])
            return @NO;
        if (CFGetTypeID((__bridge CFTypeRef)value) != CFBooleanGetTypeID())
            return @NO;
    }
    {
        NSNumber *value = values[@"platform.macos.chinese_punctuation"];
        if (![value isKindOfClass:[NSNumber class]])
            return @NO;
        if (CFGetTypeID((__bridge CFTypeRef)value) != CFBooleanGetTypeID())
            return @NO;
    }
    {
        NSNumber *value = values[@"platform.macos.candidate_learning"];
        if (![value isKindOfClass:[NSNumber class]])
            return @NO;
        if (CFGetTypeID((__bridge CFTypeRef)value) != CFBooleanGetTypeID())
            return @NO;
    }
    {
        NSNumber *value = values[@"platform.macos.english_input_mode"];
        if (![value isKindOfClass:[NSNumber class]])
            return @NO;
        if (CFGetTypeID((__bridge CFTypeRef)value) != CFBooleanGetTypeID())
            return @NO;
    }
    {
        NSNumber *value = values[@"platform.macos.input_mode_shortcut"];
        if (![value isKindOfClass:[NSNumber class]])
            return @NO;
        if (CFGetTypeID((__bridge CFTypeRef)value) != CFBooleanGetTypeID())
            return @NO;
    }
    {
        NSNumber *value = values[@"platform.macos.full_width_input"];
        if (![value isKindOfClass:[NSNumber class]])
            return @NO;
        if (CFGetTypeID((__bridge CFTypeRef)value) != CFBooleanGetTypeID())
            return @NO;
    }
    {
        NSNumber *value = values[@"platform.macos.floating_toolbar"];
        if (![value isKindOfClass:[NSNumber class]])
            return @NO;
        if (CFGetTypeID((__bridge CFTypeRef)value) != CFBooleanGetTypeID())
            return @NO;
    }
    {
        NSNumber *value = values[@"platform.macos.traditional_chinese_output"];
        if (![value isKindOfClass:[NSNumber class]])
            return @NO;
        if (CFGetTypeID((__bridge CFTypeRef)value) != CFBooleanGetTypeID())
            return @NO;
    }
    {
        NSNumber *value = values[@"platform.macos.wubi_auto_commit_unique"];
        if (![value isKindOfClass:[NSNumber class]])
            return @NO;
        if (CFGetTypeID((__bridge CFTypeRef)value) != CFBooleanGetTypeID())
            return @NO;
    }
    {
        NSNumber *value = values[@"platform.macos.shuangpin_keymap"];
        if (![value isKindOfClass:[NSNumber class]])
            return @NO;
        if (CFGetTypeID((__bridge CFTypeRef)value) != CFBooleanGetTypeID())
            return @NO;
    }
    {
        NSNumber *value = values[@"platform.macos.local_input_modes"];
        if (![value isKindOfClass:[NSNumber class]])
            return @NO;
        if (CFGetTypeID((__bridge CFTypeRef)value) != CFBooleanGetTypeID())
            return @NO;
    }
    return @YES;
}

+ (NSNumber *)applyCloudSettingsSnapshot:(NSDictionary<NSString *, id> *)values
{
    if (![[self validateCloudSettingsSnapshot:values] boolValue])
        return @NO;
    // Validate the complete snapshot before calling any mutating setter.
    [self setStoredCandidateSkin:values[@"platform.macos.candidate_skin"]];
    [self setStoredScheme:[values[@"platform.macos.input_scheme"] integerValue]];
    [self setQuanpinHelpcodeSchema:[values[@"platform.macos.quanpin_helpcode_schema"] integerValue]];
    [self setShuangpinHelpcodeSchema:[values[@"platform.macos.shuangpin_helpcode_schema"] integerValue]];
    [self setCandidatePanelStyle:[values[@"platform.macos.candidate_panel_style"] integerValue]];
    [self setCandidatePageSize:[values[@"platform.macos.candidate_page_size"] integerValue]];
    [self setCandidateFontSize:[values[@"platform.macos.candidate_font_size"] integerValue]];
    [self setCandidatePageShortcut:[values[@"platform.macos.candidate_page_shortcut"] integerValue]];
    [self setAutocorrectEnabled:[values[@"platform.macos.autocorrect"] boolValue]];
    [self setHelpcodeEnabled:[values[@"platform.macos.helpcode"] boolValue]];
    [self setChinesePunctuationEnabled:[values[@"platform.macos.chinese_punctuation"] boolValue]];
    [self setCandidateLearningEnabled:[values[@"platform.macos.candidate_learning"] boolValue]];
    [self setEnglishInputMode:[values[@"platform.macos.english_input_mode"] boolValue]];
    [self setInputModeShortcutEnabled:[values[@"platform.macos.input_mode_shortcut"] boolValue]];
    [self setFullWidthInputEnabled:[values[@"platform.macos.full_width_input"] boolValue]];
    [self setFloatingToolbarEnabled:[values[@"platform.macos.floating_toolbar"] boolValue]];
    [self setTraditionalChineseOutputEnabled:[values[@"platform.macos.traditional_chinese_output"] boolValue]];
    [self setWubiAutoCommitUniqueEnabled:[values[@"platform.macos.wubi_auto_commit_unique"] boolValue]];
    [self setShuangpinKeymapEnabled:[values[@"platform.macos.shuangpin_keymap"] boolValue]];
    [self setLocalInputModesEnabled:[values[@"platform.macos.local_input_modes"] boolValue]];
    return @YES;
}

+ (NSInteger)storedScheme
{
    const NSInteger scheme = [[NSUserDefaults standardUserDefaults] integerForKey:kSchemePreferenceKey];
    return metasequoia::mac::NormalizeStoredInputScheme(static_cast<int>(scheme));
}

+ (void)setStoredScheme:(NSInteger)scheme
{
    const NSInteger normalizedScheme = metasequoia::mac::NormalizeStoredInputScheme(static_cast<int>(scheme));
    [[NSUserDefaults standardUserDefaults] setInteger:normalizedScheme forKey:kSchemePreferenceKey];
    [[NSNotificationCenter defaultCenter] postNotificationName:@"MetasequoiaInputSchemeDidChangeNotification"
                                                        object:@(normalizedScheme)];
}

+ (NSString *)storedShuangpinSchema
{
    NSString *value = [[NSUserDefaults standardUserDefaults] stringForKey:kShuangpinSchemaPreferenceKey];
    return @(metasequoia::mac::NormalizeShuangpinSchema(value.UTF8String != nullptr ? value.UTF8String : ""));
}

+ (void)setShuangpinSchema:(NSString *)schema
{
    NSString *normalized =
        @(metasequoia::mac::NormalizeShuangpinSchema(schema.UTF8String != nullptr ? schema.UTF8String : ""));
    [[NSUserDefaults standardUserDefaults] setObject:normalized forKey:kShuangpinSchemaPreferenceKey];
    [[NSNotificationCenter defaultCenter] postNotificationName:@"MetasequoiaShuangpinSchemaDidChangeNotification"
                                                        object:normalized];
}

+ (BOOL)storedAutocorrectEnabled
{
    id value = [[NSUserDefaults standardUserDefaults] objectForKey:kAutocorrectPreferenceKey];
    return value == nil ? YES : [value boolValue];
}

+ (void)setAutocorrectEnabled:(BOOL)enabled
{
    [[NSUserDefaults standardUserDefaults] setBool:enabled forKey:kAutocorrectPreferenceKey];
    [[NSNotificationCenter defaultCenter] postNotificationName:@"MetasequoiaQuanpinAutocorrectDidChangeNotification"
                                                        object:@(enabled)];
}

+ (BOOL)storedHelpcodeEnabled
{
    id value = [[NSUserDefaults standardUserDefaults] objectForKey:kHelpcodePreferenceKey];
    return value == nil ? YES : [value boolValue];
}

+ (void)setHelpcodeEnabled:(BOOL)enabled
{
    [[NSUserDefaults standardUserDefaults] setBool:enabled forKey:kHelpcodePreferenceKey];
    [[NSNotificationCenter defaultCenter] postNotificationName:@"MetasequoiaHelpcodeDidChangeNotification"
                                                        object:@(enabled)];
}

+ (NSInteger)storedQuanpinHelpcodeSchema
{
    const NSInteger schema = [[NSUserDefaults standardUserDefaults] integerForKey:kQuanpinHelpcodeSchemaPreferenceKey];
    return metasequoia::mac::NormalizeHelpcodeSchemaPreference(static_cast<int>(schema));
}

+ (void)setQuanpinHelpcodeSchema:(NSInteger)schema
{
    const NSInteger normalizedSchema = metasequoia::mac::NormalizeHelpcodeSchemaPreference(static_cast<int>(schema));
    [[NSUserDefaults standardUserDefaults] setInteger:normalizedSchema forKey:kQuanpinHelpcodeSchemaPreferenceKey];
    [[NSNotificationCenter defaultCenter] postNotificationName:@"MetasequoiaQuanpinHelpcodeSchemaDidChangeNotification"
                                                        object:@(normalizedSchema)];
}

+ (NSInteger)storedShuangpinHelpcodeSchema
{
    const NSInteger schema =
        [[NSUserDefaults standardUserDefaults] integerForKey:kShuangpinHelpcodeSchemaPreferenceKey];
    return metasequoia::mac::NormalizeHelpcodeSchemaPreference(static_cast<int>(schema));
}

+ (void)setShuangpinHelpcodeSchema:(NSInteger)schema
{
    const NSInteger normalizedSchema = metasequoia::mac::NormalizeHelpcodeSchemaPreference(static_cast<int>(schema));
    [[NSUserDefaults standardUserDefaults] setInteger:normalizedSchema forKey:kShuangpinHelpcodeSchemaPreferenceKey];
    [[NSNotificationCenter defaultCenter]
        postNotificationName:@"MetasequoiaShuangpinHelpcodeSchemaDidChangeNotification"
                      object:@(normalizedSchema)];
}

+ (BOOL)storedChinesePunctuationEnabled
{
    id value = [[NSUserDefaults standardUserDefaults] objectForKey:kChinesePunctuationPreferenceKey];
    return value == nil ? YES : [value boolValue];
}

+ (void)setChinesePunctuationEnabled:(BOOL)enabled
{
    [[NSUserDefaults standardUserDefaults] setBool:enabled forKey:kChinesePunctuationPreferenceKey];
    [[NSNotificationCenter defaultCenter] postNotificationName:@"MetasequoiaChinesePunctuationDidChangeNotification"
                                                        object:@(enabled)];
}

+ (NSString *)storedCandidateSkin
{
    return MetasequoiaStoredCandidateSkin();
}

+ (void)setStoredCandidateSkin:(NSString *)skinId
{
    MetasequoiaSetStoredCandidateSkin(skinId);
}

+ (NSInteger)storedCandidatePanelStyle
{
    const NSInteger value = [[NSUserDefaults standardUserDefaults] integerForKey:kCandidatePanelStylePreferenceKey];
    return static_cast<NSInteger>(metasequoia::mac::NormalizeCandidatePanelStyle(value));
}

+ (void)setCandidatePanelStyle:(NSInteger)style
{
    const NSInteger normalizedStyle = static_cast<NSInteger>(metasequoia::mac::NormalizeCandidatePanelStyle(style));
    [[NSUserDefaults standardUserDefaults] setInteger:normalizedStyle forKey:kCandidatePanelStylePreferenceKey];
    [[NSNotificationCenter defaultCenter] postNotificationName:@"MetasequoiaCandidatePanelStyleDidChangeNotification"
                                                        object:@(normalizedStyle)];
}

+ (NSInteger)storedCandidatePageSize
{
    const NSInteger value = [[NSUserDefaults standardUserDefaults] integerForKey:kCandidatePageSizePreferenceKey];
    return MetasequoiaAppearanceInteger(
        @"pageSize", static_cast<NSInteger>(metasequoia::mac::NormalizeCandidatePageSize(static_cast<size_t>(value))),
        1, 9);
}

+ (void)setCandidatePageSize:(NSInteger)pageSize
{
    const NSInteger normalizedPageSize =
        static_cast<NSInteger>(metasequoia::mac::NormalizeCandidatePageSize(static_cast<size_t>(pageSize)));
    if ([@[ @5, @7, @9 ] containsObject:@(normalizedPageSize)])
    {
        [[NSUserDefaults standardUserDefaults] setInteger:normalizedPageSize forKey:kCandidatePageSizePreferenceKey];
        MetasequoiaSetAppearancePreference(@"pageSize", nil);
    }
    else
        MetasequoiaSetAppearancePreference(@"pageSize", @(normalizedPageSize));
    [[NSNotificationCenter defaultCenter] postNotificationName:@"MetasequoiaCandidatePageSizeDidChangeNotification"
                                                        object:@(normalizedPageSize)];
}

+ (NSInteger)storedCandidateFontSize
{
    const NSInteger value = [[NSUserDefaults standardUserDefaults] integerForKey:kCandidateFontSizePreferenceKey];
    return MetasequoiaAppearanceInteger(
        @"fontSize", static_cast<NSInteger>(metasequoia::mac::NormalizeCandidateFontSize(static_cast<size_t>(value))),
        12, 36);
}

+ (void)setCandidateFontSize:(NSInteger)fontSize
{
    const NSInteger normalizedFontSize =
        static_cast<NSInteger>(metasequoia::mac::NormalizeCandidateFontSize(static_cast<size_t>(fontSize)));
    if ([@[ @16, @18, @20 ] containsObject:@(normalizedFontSize)])
    {
        [[NSUserDefaults standardUserDefaults] setInteger:normalizedFontSize forKey:kCandidateFontSizePreferenceKey];
        MetasequoiaSetAppearancePreference(@"fontSize", nil);
    }
    else
        MetasequoiaSetAppearancePreference(@"fontSize", @(normalizedFontSize));
    [[NSNotificationCenter defaultCenter] postNotificationName:@"MetasequoiaCandidateFontSizeDidChangeNotification"
                                                        object:@(normalizedFontSize)];
}

+ (BOOL)storedCandidateTranslationsEnabled
{
    id value = [[NSUserDefaults standardUserDefaults] objectForKey:kCandidateTranslationsPreferenceKey];
    return value == nil ? YES : [value boolValue];
}

+ (void)setCandidateTranslationsEnabled:(BOOL)enabled
{
    [[NSUserDefaults standardUserDefaults] setBool:enabled forKey:kCandidateTranslationsPreferenceKey];
    [[NSNotificationCenter defaultCenter] postNotificationName:@"MetasequoiaCandidateTranslationsDidChangeNotification"
                                                        object:@(enabled)];
}

+ (NSInteger)storedCandidatePageShortcut
{
    const NSInteger value = [[NSUserDefaults standardUserDefaults] integerForKey:kCandidatePageShortcutPreferenceKey];
    return static_cast<NSInteger>(metasequoia::mac::NormalizeCandidatePageShortcut(static_cast<int>(value)));
}

+ (void)setCandidatePageShortcut:(NSInteger)shortcut
{
    const NSInteger normalizedShortcut =
        static_cast<NSInteger>(metasequoia::mac::NormalizeCandidatePageShortcut(static_cast<int>(shortcut)));
    [[NSUserDefaults standardUserDefaults] setInteger:normalizedShortcut forKey:kCandidatePageShortcutPreferenceKey];
    [[NSNotificationCenter defaultCenter] postNotificationName:@"MetasequoiaCandidatePageShortcutDidChangeNotification"
                                                        object:@(normalizedShortcut)];
}

+ (BOOL)storedCandidateLearningEnabled
{
    id value = [[NSUserDefaults standardUserDefaults] objectForKey:kCandidateLearningPreferenceKey];
    return value == nil ? YES : [value boolValue];
}

+ (void)setCandidateLearningEnabled:(BOOL)enabled
{
    [[NSUserDefaults standardUserDefaults] setBool:enabled forKey:kCandidateLearningPreferenceKey];
    [[NSNotificationCenter defaultCenter] postNotificationName:@"MetasequoiaCandidateLearningDidChangeNotification"
                                                        object:@(enabled)];
}

+ (NSString *)storedFrequencyAdjustmentMode
{
    NSString *value = [[NSUserDefaults standardUserDefaults] stringForKey:kFrequencyAdjustmentModePreferenceKey];
    return @(metasequoia::mac::NormalizeFrequencyAdjustmentMode(value.UTF8String));
}

+ (void)setFrequencyAdjustmentMode:(NSString *)mode
{
    NSString *normalized = @(metasequoia::mac::NormalizeFrequencyAdjustmentMode(mode.UTF8String));
    [[NSUserDefaults standardUserDefaults] setObject:normalized forKey:kFrequencyAdjustmentModePreferenceKey];
    [[NSNotificationCenter defaultCenter] postNotificationName:@"MetasequoiaFrequencyAdjustmentDidChangeNotification"
                                                        object:normalized];
}

+ (NSInteger)storedFrequencyTriggerCount
{
    id value = [[NSUserDefaults standardUserDefaults] objectForKey:kFrequencyTriggerCountPreferenceKey];
    return metasequoia::mac::NormalizeFrequencyAdjustmentCount(value == nil ? 1 : [value integerValue]);
}

+ (void)setFrequencyTriggerCount:(NSInteger)count
{
    const NSInteger normalized = metasequoia::mac::NormalizeFrequencyAdjustmentCount(static_cast<int>(count));
    [[NSUserDefaults standardUserDefaults] setInteger:normalized forKey:kFrequencyTriggerCountPreferenceKey];
    [[NSNotificationCenter defaultCenter] postNotificationName:@"MetasequoiaFrequencyAdjustmentDidChangeNotification"
                                                        object:@(normalized)];
}

+ (NSInteger)storedFrequencyLinearStep
{
    id value = [[NSUserDefaults standardUserDefaults] objectForKey:kFrequencyLinearStepPreferenceKey];
    return metasequoia::mac::NormalizeFrequencyAdjustmentCount(value == nil ? 1 : [value integerValue]);
}

+ (void)setFrequencyLinearStep:(NSInteger)step
{
    const NSInteger normalized = metasequoia::mac::NormalizeFrequencyAdjustmentCount(static_cast<int>(step));
    [[NSUserDefaults standardUserDefaults] setInteger:normalized forKey:kFrequencyLinearStepPreferenceKey];
    [[NSNotificationCenter defaultCenter] postNotificationName:@"MetasequoiaFrequencyAdjustmentDidChangeNotification"
                                                        object:@(normalized)];
}

+ (BOOL)storedEnglishInputMode
{
    return [[NSUserDefaults standardUserDefaults] boolForKey:kEnglishInputModePreferenceKey];
}

+ (void)setEnglishInputMode:(BOOL)enabled
{
    [[NSUserDefaults standardUserDefaults] setBool:enabled forKey:kEnglishInputModePreferenceKey];
    [[NSNotificationCenter defaultCenter] postNotificationName:@"MetasequoiaEnglishInputModeDidChangeNotification"
                                                        object:@(enabled)];
}

// On unless it was turned off. The floating toolbar is the only other sign of which mode is live,
// and it is off by default, so without this a switch leaves nothing on screen to confirm it.
+ (BOOL)storedInputModeHUDEnabled
{
    id value = [[NSUserDefaults standardUserDefaults] objectForKey:kInputModeHUDPreferenceKey];
    return value == nil ? YES : [value boolValue];
}

+ (void)setInputModeHUDEnabled:(BOOL)enabled
{
    [[NSUserDefaults standardUserDefaults] setBool:enabled forKey:kInputModeHUDPreferenceKey];
    [[NSNotificationCenter defaultCenter] postNotificationName:@"MetasequoiaInputModeHUDDidChangeNotification"
                                                        object:@(enabled)];
}

+ (BOOL)storedInputModeShortcutEnabled
{
    id value = [[NSUserDefaults standardUserDefaults] objectForKey:kInputModeShortcutPreferenceKey];
    return value == nil ? YES : [value boolValue];
}

+ (void)setInputModeShortcutEnabled:(BOOL)enabled
{
    [[NSUserDefaults standardUserDefaults] setBool:enabled forKey:kInputModeShortcutPreferenceKey];
    [[NSNotificationCenter defaultCenter] postNotificationName:@"MetasequoiaInputModeShortcutDidChangeNotification"
                                                        object:@(enabled)];
}

+ (BOOL)storedFullWidthInputEnabled
{
    id value = [[NSUserDefaults standardUserDefaults] objectForKey:kFullWidthInputPreferenceKey];
    return value == nil ? NO : [value boolValue];
}

+ (void)setFullWidthInputEnabled:(BOOL)enabled
{
    [[NSUserDefaults standardUserDefaults] setBool:enabled forKey:kFullWidthInputPreferenceKey];
    [[NSNotificationCenter defaultCenter] postNotificationName:@"MetasequoiaFullWidthInputDidChangeNotification"
                                                        object:@(enabled)];
}

+ (BOOL)storedFloatingToolbarEnabled
{
    id value = [[NSUserDefaults standardUserDefaults] objectForKey:kFloatingToolbarPreferenceKey];
    return value == nil ? YES : [value boolValue];
}

+ (void)setFloatingToolbarEnabled:(BOOL)enabled
{
    [[NSUserDefaults standardUserDefaults] setBool:enabled forKey:kFloatingToolbarPreferenceKey];
    [[NSNotificationCenter defaultCenter] postNotificationName:MetasequoiaFloatingToolbarDidChangeNotification
                                                        object:@(enabled)];
}

+ (BOOL)storedTraditionalChineseOutputEnabled
{
    return [[NSUserDefaults standardUserDefaults] boolForKey:kTraditionalChineseOutputPreferenceKey];
}

+ (void)setTraditionalChineseOutputEnabled:(BOOL)enabled
{
    if ([self storedTraditionalChineseOutputEnabled] == enabled)
    {
        return;
    }
    [[NSUserDefaults standardUserDefaults] setBool:enabled forKey:kTraditionalChineseOutputPreferenceKey];
    [[NSNotificationCenter defaultCenter] postNotificationName:MetasequoiaTraditionalChineseOutputDidChangeNotification
                                                        object:@(enabled)];
}

+ (BOOL)storedWubiMixedPinyinEnabled
{
    return [[NSUserDefaults standardUserDefaults] boolForKey:kWubiMixedPinyinPreferenceKey];
}

+ (void)setWubiMixedPinyinEnabled:(BOOL)enabled
{
    [[NSUserDefaults standardUserDefaults] setBool:enabled forKey:kWubiMixedPinyinPreferenceKey];
    [[NSNotificationCenter defaultCenter] postNotificationName:@"MetasequoiaWubiMixedPinyinDidChangeNotification"
                                                        object:@(enabled)];
}

// On unless it was turned off: a wubi table is read by code, and a candidate list that shows the
// keys still to press is what every wubi frontend puts in front of a typist.
+ (BOOL)storedWubiCodeHintEnabled
{
    id value = [[NSUserDefaults standardUserDefaults] objectForKey:kWubiCodeHintPreferenceKey];
    return value == nil ? YES : [value boolValue];
}

+ (void)setWubiCodeHintEnabled:(BOOL)enabled
{
    [[NSUserDefaults standardUserDefaults] setBool:enabled forKey:kWubiCodeHintPreferenceKey];
    [[NSNotificationCenter defaultCenter] postNotificationName:@"MetasequoiaWubiCodeHintDidChangeNotification"
                                                        object:@(enabled)];
}

+ (BOOL)storedWubiAutoCommitUniqueEnabled
{
    return [[NSUserDefaults standardUserDefaults] boolForKey:kWubiAutoCommitUniquePreferenceKey];
}

+ (void)setWubiAutoCommitUniqueEnabled:(BOOL)enabled
{
    [[NSUserDefaults standardUserDefaults] setBool:enabled forKey:kWubiAutoCommitUniquePreferenceKey];
    [[NSNotificationCenter defaultCenter] postNotificationName:@"MetasequoiaWubiAutoCommitUniqueDidChangeNotification"
                                                        object:@(enabled)];
}

+ (BOOL)storedShuangpinKeymapEnabled
{
    return [[NSUserDefaults standardUserDefaults] boolForKey:kShuangpinKeymapPreferenceKey];
}

+ (void)setShuangpinKeymapEnabled:(BOOL)enabled
{
    [[NSUserDefaults standardUserDefaults] setBool:enabled forKey:kShuangpinKeymapPreferenceKey];
    [[NSNotificationCenter defaultCenter] postNotificationName:@"MetasequoiaShuangpinKeymapDidChangeNotification"
                                                        object:@(enabled)];
}

// Off unless asked for. Turning it on gives Shift+U, Shift+T, Shift+K and Shift+J to the engine's
// local input modes, and those keystrokes currently insert a bare capital, so a user who types
// "USA" in Chinese mode would lose that.
+ (BOOL)storedLocalInputModesEnabled
{
    return [[NSUserDefaults standardUserDefaults] boolForKey:kLocalInputModesPreferenceKey];
}

+ (void)setLocalInputModesEnabled:(BOOL)enabled
{
    [[NSUserDefaults standardUserDefaults] setBool:enabled forKey:kLocalInputModesPreferenceKey];
}

- (instancetype)initWithWindowNibName:(NSNibName)windowNibName owner:(id)owner
{
    (void)windowNibName;
    (void)owner;
    return [self init];
}

- (instancetype)initWithWindowNibName:(NSNibName)windowNibName
{
    (void)windowNibName;
    return [self init];
}

- (instancetype)init
{
    return [self initWithUpdateController:[MetasequoiaUpdateController sharedController]];
}

- (instancetype)initWithUpdateController:(MetasequoiaUpdateController *)updateController
{
    NSRect frame = NSMakeRect(0.0, 0.0, kWindowWidth, kWindowHeight);
    NSWindow *window =
        [[NSWindow alloc] initWithContentRect:frame
                                    styleMask:(NSWindowStyleMaskTitled | NSWindowStyleMaskClosable |
                                               NSWindowStyleMaskMiniaturizable | NSWindowStyleMaskResizable)
                                      backing:NSBackingStoreBuffered
                                        defer:NO];
    window.title = @"水杉输入法设置";
    window.releasedWhenClosed = NO;
    window.restorable = NO;
    window.titleVisibility = NSWindowTitleVisible;
    window.titlebarAppearsTransparent = NO;
    window.movableByWindowBackground = NO;
    window.contentMinSize = NSMakeSize(900.0, 650.0);

    self = [super initWithWindow:window];
    if (self == nil)
    {
        return nil;
    }
    window.delegate = self;
    window.appearance = MetasequoiaForcedAppearance();
    [NSNotificationCenter.defaultCenter addObserver:self
                                           selector:@selector(appearancePreferencesChanged:)
                                               name:MetasequoiaAppearanceDidChange
                                             object:nil];
    [NSDistributedNotificationCenter.defaultCenter addObserver:self
                                                      selector:@selector(appearancePreferencesChanged:)
                                                          name:MetasequoiaAppearanceDidChange
                                                        object:nil];
    _updateController = updateController;
    // The floating toolbar menu can hide the bar while this window is open, and this checkbox is the documented way to
    // bring it back, so it must follow the preference instead of waiting for the next refreshControls.
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(floatingToolbarPreferenceDidChange:)
                                                 name:MetasequoiaFloatingToolbarDidChangeNotification
                                               object:nil];
    // The toolbar menu writes the punctuation and full-width preferences too, and refreshControls only runs on
    // presentation or on an explicit page change, so without these observers the checkboxes would keep showing a stale
    // state and write it back on the next click.
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(chinesePunctuationPreferenceDidChange:)
                                                 name:@"MetasequoiaChinesePunctuationDidChangeNotification"
                                               object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(fullWidthInputPreferenceDidChange:)
                                                 name:@"MetasequoiaFullWidthInputDidChangeNotification"
                                               object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(candidateSkinPreferenceDidChange:)
                                                 name:MetasequoiaCandidateSkinDidChangeNotification
                                               object:nil];
    NSView *contentView = [[MetasequoiaSettingsSurface alloc] initWithFrame:frame];
    window.contentView = contentView;

    NSView *sidebar = [[MetasequoiaSettingsSurface alloc] initWithFrame:NSZeroRect];
    sidebar.translatesAutoresizingMaskIntoConstraints = NO;
    sidebar.accessibilityLabel = @"水杉输入法导航";
    NSTextField *brand = [NSTextField labelWithString:@"水杉 IME"];
    brand.font = [NSFont systemFontOfSize:20.0 weight:NSFontWeightSemibold];
    NSImageView *logo = [[NSImageView alloc] initWithFrame:NSZeroRect];
    logo.image = [NSImage imageWithSize:NSMakeSize(26.0, 32.0)
                                flipped:YES
                         drawingHandler:^BOOL(NSRect bounds) {
                           [[NSColor colorWithWhite:0.15 alpha:1.0] setFill];
                           [[NSBezierPath bezierPathWithRoundedRect:bounds xRadius:2.0 yRadius:2.0] fill];
                           NSBezierPath *mark = [NSBezierPath bezierPath];
                           [mark moveToPoint:NSMakePoint(20.0, 5.0)];
                           [mark lineToPoint:NSMakePoint(6.0, 12.0)];
                           [mark lineToPoint:NSMakePoint(20.0, 16.0)];
                           [mark lineToPoint:NSMakePoint(6.0, 23.0)];
                           [mark curveToPoint:NSMakePoint(20.0, 26.0)
                                controlPoint1:NSMakePoint(10.0, 27.0)
                                controlPoint2:NSMakePoint(15.0, 28.0)];
                           mark.lineWidth = 2.0;
                           mark.lineCapStyle = NSLineCapStyleRound;
                           mark.lineJoinStyle = NSLineJoinStyleRound;
                           [[NSColor whiteColor] setStroke];
                           [mark stroke];
                           return YES;
                         }];
    [logo.widthAnchor constraintEqualToConstant:26.0].active = YES;
    [logo.heightAnchor constraintEqualToConstant:32.0].active = YES;
    NSStackView *brandRow = [NSStackView stackViewWithViews:@[ logo, brand ]];
    brandRow.spacing = 12.0;
    brandRow.edgeInsets = NSEdgeInsetsMake(0.0, 18.0, 0.0, 0.0);
    NSStackView *navigation = [NSStackView stackViewWithViews:@[ brandRow ]];
    navigation.orientation = NSUserInterfaceLayoutOrientationVertical;
    navigation.alignment = NSLayoutAttributeLeading;
    navigation.spacing = 2.0;
    navigation.translatesAutoresizingMaskIntoConstraints = NO;
    [navigation setCustomSpacing:30.0 afterView:brandRow];
    NSArray<NSString *> *labels = @[
        @"输入", @"外观", @"皮肤", @"词库", @"关于与更新", @"五笔", @"辅助码", @"快捷键", @"悬浮工具栏", @"语音输入",
        @"帮助", @"反馈"
    ];
    NSArray<NSString *> *symbols = @[
        @"keyboard", @"paintpalette", @"photo.on.rectangle", @"book", @"info.circle", @"keyboard", @"a.circle",
        @"command", @"ellipsis.rectangle", @"mic", @"questionmark.square", @"ladybug"
    ];
    NSMutableArray<NSButton *> *buttons = [NSMutableArray array];
    // Keep page indices stable; appearance leads the navigation to match the visual settings workflow.
    for (NSNumber *pageIndex in @[ @1, @0, @6, @7, @3, @2, @9, @8, @10, @4, @11 ])
    {
        NSInteger index = pageIndex.integerValue;
        NSButton *button = [[MetasequoiaSettingsNavigationButton alloc] initWithFrame:NSZeroRect];
        button.title = labels[index];
        button.target = self;
        button.action = @selector(selectPreferencesPage:);
        button.tag = index;
        [button setButtonType:NSButtonTypePushOnPushOff];
        button.bordered = NO;
        button.alignment = NSTextAlignmentLeft;
        button.imagePosition = NSImageLeft;
        button.image = [NSImage imageWithSystemSymbolName:symbols[index] accessibilityDescription:nil];
        button.font = [NSFont systemFontOfSize:14.0 weight:NSFontWeightMedium];
        button.accessibilityLabel = labels[index];
        [navigation addArrangedSubview:button];
        [button.widthAnchor constraintEqualToAnchor:navigation.widthAnchor].active = YES;
        [button.heightAnchor constraintEqualToConstant:42.0].active = YES;
        [buttons addObject:button];
    }
    _navigationButtons = buttons;
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

    NSView *settingsPanel = [[NSView alloc] initWithFrame:NSZeroRect];
    settingsPanel.translatesAutoresizingMaskIntoConstraints = NO;
    NSView *pageContainer = [[NSView alloc] initWithFrame:NSZeroRect];
    pageContainer.translatesAutoresizingMaskIntoConstraints = NO;

    NSArray<NSString *> *schemeTitles = @[ @"全拼输入", @"双拼输入", @"五笔输入" ];
    NSMutableArray<NSButton *> *schemeButtons = [NSMutableArray arrayWithCapacity:schemeTitles.count];
    NSMutableArray<NSView *> *schemeRows = [NSMutableArray arrayWithObject:CardHeader(@"输入方式")];
    [schemeRows addObject:CardSeparator()];
    _shuangpinSchemeButton = [[NSPopUpButton alloc] initWithFrame:NSZeroRect pullsDown:NO];
    for (const char *identifier : metasequoia::mac::kShuangpinSchemaIdentifiers)
    {
        [_shuangpinSchemeButton addItemWithTitle:@(metasequoia::mac::ShuangpinSchemaTitle(identifier))];
        [_shuangpinSchemeButton itemAtIndex:_shuangpinSchemeButton.numberOfItems - 1].representedObject = @(identifier);
    }
    _shuangpinSchemeButton.target = self;
    _shuangpinSchemeButton.action = @selector(shuangpinSchemaChanged:);
    _shuangpinSchemeButton.accessibilityLabel = @"双拼方案";
    _wubiSchemeButton = [[NSPopUpButton alloc] initWithFrame:NSZeroRect pullsDown:NO];
    [_wubiSchemeButton addItemWithTitle:@"86 五笔"];
    _wubiSchemeButton.accessibilityLabel = @"五笔方案";
    _shuangpinKeymapButton = [NSButton checkboxWithTitle:@"显示双拼键位提示"
                                                  target:self
                                                  action:@selector(shuangpinKeymapChanged:)];
    _shuangpinKeymapButton.accessibilityLabel = @"显示双拼键位提示";
    _shuangpinKeymapRow = PreferenceRow(@"双拼初学者", _shuangpinKeymapButton);
    _shuangpinKeymapRow.accessibilityLabel = @"双拼键位提示行";
    _shuangpinKeymapSeparator = CardSeparator();
    for (NSInteger index = 0; index < static_cast<NSInteger>(schemeTitles.count); ++index)
    {
        NSButton *button = [NSButton radioButtonWithTitle:schemeTitles[index]
                                                   target:self
                                                   action:@selector(schemeChanged:)];
        button.tag = index;
        button.font = [NSFont systemFontOfSize:13.0 weight:NSFontWeightMedium];
        button.accessibilityLabel = schemeTitles[index];
        [schemeButtons addObject:button];
        NSView *accessory = index == 1 ? _shuangpinSchemeButton : (index == 2 ? _wubiSchemeButton : nil);
        [schemeRows addObject:SchemeChoiceRow(button, accessory)];
        [schemeRows addObject:CardSeparator()];
        if (index == 1)
        {
            [schemeRows addObject:_shuangpinKeymapRow];
            [schemeRows addObject:_shuangpinKeymapSeparator];
        }
    }
    _schemeButtons = [schemeButtons copy];
    NSButton *wubiSettingsButton = [NSButton buttonWithTitle:@"设置" target:self action:@selector(showWubiSettings:)];
    wubiSettingsButton.bordered = NO;
    wubiSettingsButton.alignment = NSTextAlignmentRight;
    wubiSettingsButton.image = [NSImage imageWithSystemSymbolName:@"chevron.right" accessibilityDescription:nil];
    wubiSettingsButton.imagePosition = NSImageTrailing;
    wubiSettingsButton.contentTintColor = [NSColor labelColor];
    wubiSettingsButton.attributedTitle = [[NSAttributedString alloc]
        initWithString:wubiSettingsButton.title
            attributes:@{
                NSFontAttributeName : [NSFont systemFontOfSize:13.0 weight:NSFontWeightMedium],
                NSForegroundColorAttributeName : [NSColor labelColor],
            }];
    wubiSettingsButton.accessibilityLabel = @"五笔功能设置";
    _wubiSettingsRow = PreferenceRow(@"五笔功能", wubiSettingsButton);
    _wubiSettingsRow.accessibilityLabel = @"五笔功能行";
    [schemeRows addObject:_wubiSettingsRow];

    _autocorrectButton = [NSButton checkboxWithTitle:@"启用全拼自动纠错"
                                              target:self
                                              action:@selector(autocorrectChanged:)];
    _chinesePunctuationButton = [NSButton checkboxWithTitle:@"使用中文标点"
                                                     target:self
                                                     action:@selector(chinesePunctuationChanged:)];
    _inputModeShortcutButton = [NSButton checkboxWithTitle:@"Shift 切换中英文"
                                                    target:self
                                                    action:@selector(inputModeShortcutChanged:)];
    _inputModeShortcutButton.accessibilityLabel = @"Shift 切换中英文";
    _inputModeShortcutButton.toolTip =
        @"单独按一下 Shift 切换中英文，Shift+Space 同样可用。正在输入时按 Shift 则把已经打出的字母按英文上屏。";
    _inputModeHUDButton = [NSButton checkboxWithTitle:@"切换中英文时显示提示"
                                               target:self
                                               action:@selector(inputModeHUDChanged:)];
    _inputModeHUDButton.accessibilityLabel = @"切换中英文时显示提示";
    _inputModeHUDButton.toolTip = @"切换后在光标下方短暂显示「中」或「英」。";
    _fullWidthInputButton = [NSButton checkboxWithTitle:@"Option+Shift+H 切换全半角"
                                                 target:self
                                                 action:@selector(fullWidthInputChanged:)];
    _fullWidthInputButton.accessibilityLabel = @"Option+Shift+H 切换全半角";

    _candidatePageShortcutButton = [[NSPopUpButton alloc] initWithFrame:NSZeroRect pullsDown:NO];
    [_candidatePageShortcutButton addItemsWithTitles:@[ @"- / =", @"[ / ]", @"Page Up / Page Down" ]];
    _candidatePageShortcutButton.target = self;
    _candidatePageShortcutButton.action = @selector(candidatePageShortcutChanged:);
    _candidatePageShortcutButton.accessibilityLabel = @"候选翻页快捷键";

    NSBox *schemeCard = CardWithViews(schemeRows, 0.0);
    _languageModeButton = [[NSPopUpButton alloc] initWithFrame:NSZeroRect pullsDown:NO];
    [_languageModeButton addItemsWithTitles:@[ @"中文", @"日语 · 罗马字输入" ]];
    _languageModeButton.identifier = @"japaneseMode";
    _languageModeButton.accessibilityLabel = @"输入语言模式";
    _languageModeButton.toolTip = @"中文方案独立保存；切换模式在当前组合结束后生效。";
    _languageModeButton.target = self;
    _languageModeButton.action = @selector(inputModePreferenceChanged:);
    _languageModeButton.autoenablesItems = NO;
    [_languageModeButton itemAtIndex:1].enabled = [NSBundle.mainBundle URLForResource:@"dict_japanese"
                                                                        withExtension:@"dat"] != nil;
    NSBox *languageCard = CardWithViews(@[ PreferenceRow(@"输入模式", _languageModeButton) ], 12.0);
    NSBox *behaviorCard = CardWithViews(@[ _autocorrectButton, _chinesePunctuationButton ], 9.0);
    NSBox *shortcutCard = CardWithViews(
        @[
            PreferenceRow(@"上翻 / 下翻", _candidatePageShortcutButton), CardSeparator(), _inputModeShortcutButton,
            _inputModeHUDButton, _fullWidthInputButton
        ],
        12.0);
    schemeCard.accessibilityLabel = @"输入方式卡片";
    behaviorCard.accessibilityLabel = @"中英文状态切换卡片";
    shortcutCard.accessibilityLabel = @"候选翻页快捷键卡片";
    _inputBehaviorButtons = [NSMutableArray array];
    NSMutableArray<NSView *> *pagingRows = [NSMutableArray array];
    NSArray<NSArray<NSString *> *> *pagingDefinitions = @[
        @[ @"pageMinus", @"减号 / 等号（- / =）" ],
        @[ @"pageComma", @"逗号 / 句号（, / .）" ],
        @[ @"pageBrackets", @"方括号（[ / ]）" ],
        @[ @"pageKeys", @"Page Up / Page Down" ],
        @[ @"verticalNavigation", @"上 / 下方向键选择候选" ],
    ];
    for (NSArray<NSString *> *definition in pagingDefinitions)
    {
        NSButton *button = [NSButton checkboxWithTitle:definition[1]
                                                target:self
                                                action:@selector(inputBehaviorChanged:)];
        button.identifier = definition[0];
        button.accessibilityLabel = definition[1];
        [_inputBehaviorButtons addObject:button];
        [pagingRows addObject:button];
    }
    NSButton *edgeButton = [NSButton checkboxWithTitle:@"以词定字：[ 取首字，] 取末字"
                                                target:self
                                                action:@selector(inputBehaviorChanged:)];
    edgeButton.identifier = @"edgeSelection";
    edgeButton.accessibilityLabel = @"以词定字";
    edgeButton.toolTip = @"对当前高亮候选生效，与方括号翻页互斥。";
    [_inputBehaviorButtons addObject:edgeButton];
    NSButton *mixedButton = [NSButton checkboxWithTitle:@"中文输入时显示英文候选"
                                                 target:self
                                                 action:@selector(inputBehaviorChanged:)];
    mixedButton.identifier = @"mixedEnglish";
    mixedButton.accessibilityLabel = @"中英混输";
    [_inputBehaviorButtons addObject:mixedButton];
    _englishMinimumPrefixButton = [[NSPopUpButton alloc] initWithFrame:NSZeroRect pullsDown:NO];
    for (NSInteger length = 1; length <= 10; ++length)
        [_englishMinimumPrefixButton addItemWithTitle:[NSString stringWithFormat:@"%ld 个字母", (long)length]];
    _englishMinimumPrefixButton.target = self;
    _englishMinimumPrefixButton.action = @selector(englishMinimumPrefixChanged:);
    _englishMinimumPrefixButton.accessibilityLabel = @"英文候选最短前缀";
    NSBox *pagingCard = CardWithViews(pagingRows, 12.0);
    NSBox *edgeCard = CardWithViews(@[ edgeButton ], 12.0);
    NSBox *mixedCard = CardWithViews(
        @[ mixedButton, CardSeparator(), PreferenceRow(@"英文候选最短前缀", _englishMinimumPrefixButton) ], 12.0);
    _defaultInputModeButton = [[NSPopUpButton alloc] initWithFrame:NSZeroRect pullsDown:NO];
    [_defaultInputModeButton addItemsWithTitles:@[ @"中文", @"英文" ]];
    _defaultInputModeButton.identifier = @"defaultEnglish";
    _defaultInputModeButton.accessibilityLabel = @"默认输入状态";
    _defaultInputModeButton.toolTip = @"输入法下次启动及首次进入未记忆的应用时使用。";
    _defaultInputModeButton.target = self;
    _defaultInputModeButton.action = @selector(inputModePreferenceChanged:);
    _inputModeScopeButton = [[NSPopUpButton alloc] initWithFrame:NSZeroRect pullsDown:NO];
    [_inputModeScopeButton addItemsWithTitles:@[ @"全局共享", @"按应用记忆" ]];
    _inputModeScopeButton.identifier = @"perApplicationMode";
    _inputModeScopeButton.accessibilityLabel = @"中英文状态作用范围";
    _inputModeScopeButton.target = self;
    _inputModeScopeButton.action = @selector(inputModePreferenceChanged:);
    _outputScriptButton = [[NSPopUpButton alloc] initWithFrame:NSZeroRect pullsDown:NO];
    [_outputScriptButton addItemsWithTitles:@[ @"简体中文", @"繁體中文" ]];
    _outputScriptButton.identifier = @"outputScript";
    _outputScriptButton.accessibilityLabel = @"简繁输出";
    _outputScriptButton.target = self;
    _outputScriptButton.action = @selector(inputModePreferenceChanged:);
    NSBox *modeCard = CardWithViews(
        @[
            PreferenceRow(@"默认输入状态", _defaultInputModeButton), CardSeparator(),
            PreferenceRow(@"中英文状态作用范围", _inputModeScopeButton), CardSeparator(),
            PreferenceRow(@"简繁输出", _outputScriptButton)
        ],
        12.0);
    _alwaysChinesePunctuationButton = [NSButton checkboxWithTitle:@"始终使用中文标点"
                                                           target:self
                                                           action:@selector(inputBehaviorChanged:)];
    _alwaysChinesePunctuationButton.identifier = @"alwaysChinesePunctuation";
    _alwaysEnglishPunctuationButton = [NSButton checkboxWithTitle:@"始终使用英文标点"
                                                           target:self
                                                           action:@selector(inputBehaviorChanged:)];
    _alwaysEnglishPunctuationButton.identifier = @"alwaysEnglishPunctuation";
    _smartPunctuationButton = [NSButton checkboxWithTitle:@"智能标点"
                                                   target:self
                                                   action:@selector(inputBehaviorChanged:)];
    _smartPunctuationButton.identifier = @"smartPunctuation";
    _pairedPunctuationButton = [NSButton checkboxWithTitle:@"成对标点自动补全"
                                                    target:self
                                                    action:@selector(inputBehaviorChanged:)];
    _pairedPunctuationButton.identifier = @"pairedPunctuation";
    _repeatPunctuationButton = [NSButton checkboxWithTitle:@"重复标点转中文（2 秒内）"
                                                    target:self
                                                    action:@selector(inputBehaviorChanged:)];
    _repeatPunctuationButton.identifier = @"repeatPunctuation";
    NSBox *punctuationCard = CardWithViews(
        @[
            _alwaysChinesePunctuationButton, _alwaysEnglishPunctuationButton, CardSeparator(), _smartPunctuationButton,
            _pairedPunctuationButton, _repeatPunctuationButton
        ],
        8.0);
    _candidateTranslationButton = [NSButton checkboxWithTitle:@"候选词翻译"
                                                       target:self
                                                       action:@selector(inputBehaviorChanged:)];
    _candidateTranslationButton.identifier = @"candidateTranslation";
    _cloudCandidatesButton = [NSButton checkboxWithTitle:@"云候选（输入内容会离开本机）"
                                                  target:self
                                                  action:@selector(inputBehaviorChanged:)];
    _cloudCandidatesButton.identifier = @"cloudCandidates";
    _translationProviderButton = [[NSPopUpButton alloc] initWithFrame:NSZeroRect pullsDown:NO];
    [_translationProviderButton addItemsWithTitles:@[ @"水杉账号 AI", @"腾讯云", @"DeepLX（自部署）" ]];
    _translationProviderButton.accessibilityLabel = @"候选翻译在线服务";
    _translationProviderButton.identifier = @"translationProvider";
    _translationProviderButton.target = self;
    _translationProviderButton.action = @selector(translationProviderChanged:);
    _translationLanguageButton = [[NSPopUpButton alloc] initWithFrame:NSZeroRect pullsDown:NO];
    [_translationLanguageButton addItemsWithTitles:@[ @"英语", @"日语", @"韩语", @"西班牙语", @"法语", @"德语" ]];
    _translationLanguageButton.accessibilityLabel = @"候选翻译目标语言";
    _translationLanguageButton.identifier = @"translationLanguage";
    _translationLanguageButton.target = self;
    _translationLanguageButton.action = @selector(inputBehaviorChanged:);
    _translationSecretIdField = [NSTextField textFieldWithString:@""];
    _translationSecretIdField.placeholderString = @"SecretId";
    _translationSecretIdField.identifier = @"translationSecretId";
    _translationSecretIdField.target = self;
    _translationSecretIdField.action = @selector(translationCredentialChanged:);
    _translationSecretKeyField = [[NSSecureTextField alloc] initWithFrame:NSZeroRect];
    _translationSecretKeyField.stringValue = @"";
    _translationSecretKeyField.placeholderString = @"SecretKey";
    _translationSecretKeyField.identifier = @"translationSecretKey";
    _translationSecretKeyField.target = self;
    _translationSecretKeyField.action = @selector(translationCredentialChanged:);
    _translationEndpointField = [NSTextField textFieldWithString:@""];
    _translationEndpointField.placeholderString = @"https://your-deeplx.example/translate";
    _translationEndpointField.identifier = @"translationEndpoint";
    _translationEndpointField.target = self;
    _translationEndpointField.action = @selector(translationCredentialChanged:);
    _translationTencentIdRow = PreferenceRow(@"腾讯云 SecretId", _translationSecretIdField);
    _translationTencentKeyRow = PreferenceRow(@"腾讯云 SecretKey", _translationSecretKeyField);
    _translationEndpointRow = PreferenceRow(@"DeepLX Endpoint", _translationEndpointField);
    _translationAccountLabel = [NSTextField labelWithString:@""];
    _translationAccountLabel.textColor = [NSColor secondaryLabelColor];
    _translationAccountLabel.font = [NSFont systemFontOfSize:NSFont.smallSystemFontSize];
    _translationAccountLabel.accessibilityLabel = @"候选翻译账号状态";
    // Signed out, the line that names the requirement also offers the way to meet it: the sign-in
    // entry lives on another page, and a setting that names one without a route to it is how someone
    // ends up hunting the settings for a button that was never on that page.
    _translationAccountButton = [NSButton buttonWithTitle:@"登录…" target:self action:@selector(showBackendAccount:)];
    _translationAccountButton.bezelStyle = NSBezelStyleRounded;
    _translationAccountButton.accessibilityLabel = @"登录水杉账号";
    NSStackView *translationAccountStatus =
        [NSStackView stackViewWithViews:@[ _translationAccountLabel, _translationAccountButton ]];
    translationAccountStatus.orientation = NSUserInterfaceLayoutOrientationHorizontal;
    translationAccountStatus.alignment = NSLayoutAttributeCenterY;
    translationAccountStatus.spacing = 8.0;
    _translationAccountRow = PreferenceRow(@"", translationAccountStatus);
    // The rows are addressed by label so the settings test can watch each provider reveal its own.
    _translationTencentIdRow.accessibilityLabel = @"腾讯云 SecretId 行";
    _translationTencentKeyRow.accessibilityLabel = @"腾讯云 SecretKey 行";
    _translationEndpointRow.accessibilityLabel = @"DeepLX Endpoint 行";
    _translationAccountRow.accessibilityLabel = @"候选翻译账号状态行";
    NSBox *translationCard = CardWithViews(
        @[
            _candidateTranslationButton, PreferenceRow(@"在线服务", _translationProviderButton),
            PreferenceRow(@"目标语言", _translationLanguageButton), _translationAccountRow, _translationTencentIdRow,
            _translationTencentKeyRow, _translationEndpointRow
        ],
        8.0);
    NSView *shortcutsPage = PreferencesPage(@"快捷键", @"设置候选翻页与输入状态切换快捷键。", @[ shortcutCard ]);
    shortcutsPage.accessibilityLabel = @"快捷键设置页";

    NSButton *backToKeyboardButton = [NSButton buttonWithTitle:@"返回键盘输入"
                                                        target:self
                                                        action:@selector(backToKeyboardInput:)];
    backToKeyboardButton.bezelStyle = NSBezelStyleInline;
    backToKeyboardButton.image = [NSImage imageWithSystemSymbolName:@"chevron.left" accessibilityDescription:nil];
    backToKeyboardButton.imagePosition = NSImageLeft;
    backToKeyboardButton.alignment = NSTextAlignmentLeft;
    _wubiAutoCommitButton = [NSButton checkboxWithTitle:@"四码唯一候选自动上屏"
                                                 target:self
                                                 action:@selector(wubiAutoCommitUniqueChanged:)];
    _wubiAutoCommitButton.accessibilityLabel = @"四码唯一候选自动上屏";
    _wubiMixedPinyinButton = [NSButton checkboxWithTitle:@"编码打不出时用拼音候选"
                                                  target:self
                                                  action:@selector(wubiMixedPinyinChanged:)];
    _wubiMixedPinyinButton.accessibilityLabel = @"编码打不出时用拼音候选";
    _wubiMixedPinyinButton.toolTip = @"五笔词库答不上当前编码时，用同一串字母查全拼。词库答得上的编码不受影响。";
    _wubiCodeHintButton = [NSButton checkboxWithTitle:@"候选显示剩余编码"
                                               target:self
                                               action:@selector(wubiCodeHintChanged:)];
    _wubiCodeHintButton.accessibilityLabel = @"候选显示剩余编码";
    _wubiCodeHintButton.toolTip = @"在候选后面标出还要再打哪几个字母才能单独打出它。已经打完整码的候选不标。";
    NSTextField *wubiSchemeLabel = [NSTextField labelWithString:@"86 五笔"];
    wubiSchemeLabel.textColor = [NSColor secondaryLabelColor];
    NSBox *wubiOptionsCard = CardWithViews(
        @[
            PreferenceRow(@"编码方案", wubiSchemeLabel), _wubiAutoCommitButton, _wubiMixedPinyinButton,
            _wubiCodeHintButton
        ],
        8.0);
    wubiOptionsCard.accessibilityLabel = @"五笔选项卡片";
    NSView *wubiPage = PreferencesPage(@"五笔设置", @"调整 86 五笔的输入与上屏行为。",
                                       @[ backToKeyboardButton, SectionLabel(@"输入行为"), wubiOptionsCard ]);
    wubiPage.accessibilityLabel = @"五笔设置页";

    _candidatePanelStyleButton = [[NSPopUpButton alloc] initWithFrame:NSZeroRect pullsDown:NO];
    [_candidatePanelStyleButton addItemsWithTitles:@[ @"横向排列", @"纵向列表" ]];
    _candidatePanelStyleButton.target = self;
    _candidatePanelStyleButton.action = @selector(candidatePanelStyleChanged:);
    _candidatePanelStyleButton.accessibilityLabel = @"候选排列";

    _candidatePageSizeButton = [[NSPopUpButton alloc] initWithFrame:NSZeroRect pullsDown:NO];
    for (NSInteger count = 1; count <= 9; ++count)
        [_candidatePageSizeButton addItemWithTitle:[NSString stringWithFormat:@"%ld 个", (long)count]];
    _candidatePageSizeButton.target = self;
    _candidatePageSizeButton.action = @selector(candidatePageSizeChanged:);
    _candidatePageSizeButton.accessibilityLabel = @"每页候选";

    _candidateFontSizeButton = [[NSPopUpButton alloc] initWithFrame:NSZeroRect pullsDown:NO];
    for (NSInteger size = 12; size <= 36; ++size)
        [_candidateFontSizeButton addItemWithTitle:[NSString stringWithFormat:@"%ld", (long)size]];
    _candidateFontSizeButton.target = self;
    _candidateFontSizeButton.action = @selector(candidateFontSizeChanged:);
    _candidateFontSizeButton.accessibilityLabel = @"候选字号";
    _candidateTranslationsButton = [NSButton checkboxWithTitle:@"竖排候选显示英文释义"
                                                        target:self
                                                        action:@selector(candidateTranslationsChanged:)];
    _candidateTranslationsButton.accessibilityLabel = @"竖排候选显示英文释义";
    _candidateTranslationsButton.toolTip =
        @"仅竖排候选窗口在词条右侧显示本地英文释义。开启「候选词翻译」时改用在线译文。";

    _candidateFontButton = [[NSPopUpButton alloc] initWithFrame:NSZeroRect pullsDown:NO];
    _candidateFallbackFontButton = [[NSPopUpButton alloc] initWithFrame:NSZeroRect pullsDown:NO];
    for (NSPopUpButton *button in @[ _candidateFontButton, _candidateFallbackFontButton ])
    {
        [button addItemWithTitle:@"跟随系统"];
        button.lastItem.representedObject = @"";
        for (NSString *family in [NSFontManager.sharedFontManager.availableFontFamilies
                 sortedArrayUsingSelector:@selector(localizedStandardCompare:)])
        {
            [button addItemWithTitle:family];
            button.lastItem.representedObject = family;
        }
        button.target = self;
        button.action = @selector(advancedAppearanceChanged:);
    }
    _candidateFontButton.accessibilityLabel = @"候选窗主字体";
    _candidateFallbackFontButton.accessibilityLabel = @"候选窗中文补充字体";
    _preeditFontSizeButton = [[NSPopUpButton alloc] initWithFrame:NSZeroRect pullsDown:NO];
    for (NSInteger size = 10; size <= 36; ++size)
        [_preeditFontSizeButton addItemWithTitle:[NSString stringWithFormat:@"%ld", (long)size]];
    _preeditFontSizeButton.target = self;
    _preeditFontSizeButton.action = @selector(advancedAppearanceChanged:);
    _preeditFontSizeButton.accessibilityLabel = @"候选窗预编辑字号";
    _followCaretSwitch = [[NSSwitch alloc] initWithFrame:NSZeroRect];
    _followCaretSwitch.target = self;
    _followCaretSwitch.action = @selector(advancedAppearanceChanged:);
    _followCaretSwitch.accessibilityLabel = @"候选窗口跟随光标";
    _followCaretSwitch.toolTip = @"关闭后保持本次组合首次出现的位置，直到候选窗口消失。";
    _themeButton = [[NSPopUpButton alloc] initWithFrame:NSZeroRect pullsDown:NO];
    [_themeButton addItemsWithTitles:@[ @"跟随系统", @"浅色", @"深色" ]];
    _themeButton.target = self;
    _themeButton.action = @selector(advancedAppearanceChanged:);
    _themeButton.accessibilityLabel = @"主题模式";
    _candidateColorWell = [[NSColorWell alloc] initWithFrame:NSMakeRect(0, 0, 40, 26)];
    _candidateColorWell.target = self;
    _candidateColorWell.action = @selector(advancedAppearanceChanged:);
    _candidateColorWell.accessibilityLabel = @"候选文字颜色";
    NSButton *resetColor = [NSButton buttonWithTitle:@"跟随主题" target:self action:@selector(resetCandidateColor:)];
    NSStackView *colorControls = [NSStackView stackViewWithViews:@[ _candidateColorWell, resetColor ]];
    colorControls.spacing = 8;
    [_candidateColorWell.widthAnchor constraintEqualToConstant:40].active = YES;
    [_candidateColorWell.heightAnchor constraintEqualToConstant:26].active = YES;

    _candidatePreview = [[MetasequoiaCandidatePreviewView alloc] initWithFrame:NSZeroRect];
    NSBox *appearanceCard = CardWithViews(
        @[
            PreferenceRow(@"候选窗口跟随光标", _followCaretSwitch),
            CardSeparator(),
            PreferenceRow(@"候选窗主字体", _candidateFontButton),
            CardSeparator(),
            PreferenceRow(@"候选窗中文补充字体", _candidateFallbackFontButton),
            CardSeparator(),
            PreferenceRow(@"候选字号", _candidateFontSizeButton),
            CardSeparator(),
            PreferenceRow(@"候选窗预编辑字号", _preeditFontSizeButton),
            CardSeparator(),
            PreferenceRow(@"候选文字颜色", colorControls),
            CardSeparator(),
            PreferenceRow(@"每页候选项数量", _candidatePageSizeButton),
            CardSeparator(),
            _candidateTranslationsButton,
        ],
        4.0);
    appearanceCard.accessibilityLabel = @"候选窗口卡片";
    _floatingToolbarButton = [NSButton checkboxWithTitle:@"显示悬浮状态栏"
                                                  target:self
                                                  action:@selector(floatingToolbarChanged:)];
    _floatingToolbarButton.accessibilityLabel = @"显示悬浮状态栏";
    NSBox *floatingToolbarCard = CardWithViews(@[ _floatingToolbarButton ], 0.0);
    floatingToolbarCard.accessibilityLabel = @"悬浮状态栏卡片";
    NSView *appearancePage = PreferencesPage(@"外观", @"调整候选窗口与输入状态栏的显示方式。", @[
        _candidatePreview, appearanceCard, CardWithViews(@[ PreferenceRow(@"主题模式", _themeButton) ], 0),
        CardWithViews(@[ PreferenceRow(@"候选项排列方式", _candidatePanelStyleButton) ], 0)
    ]);
    appearancePage.accessibilityLabel = @"外观设置页";
    NSView *floatingPage =
        PreferencesPage(@"悬浮工具栏", @"随时查看输入状态，通过工具栏切换常用输入选项。", @[ floatingToolbarCard ]);
    floatingPage.accessibilityLabel = @"悬浮工具栏设置页";

    _skinSettings = [[MetasequoiaSkinSettingsView alloc] initWithFrame:NSZeroRect];

    _helpcodeButton = [NSButton checkboxWithTitle:@"全拼辅助码" target:self action:@selector(schemeHelpcodeChanged:)];
    _helpcodeButton.identifier = @"quanpinHelpcodeEnabled";
    _shuangpinHelpcodeEnabledButton = [NSButton checkboxWithTitle:@"双拼辅助码"
                                                           target:self
                                                           action:@selector(schemeHelpcodeChanged:)];
    _shuangpinHelpcodeEnabledButton.identifier = @"shuangpinHelpcodeEnabled";
    _quanpinHelpcodeHintsButton = [NSButton checkboxWithTitle:@"在候选窗口中显示全拼辅助码"
                                                       target:self
                                                       action:@selector(schemeHelpcodeChanged:)];
    _quanpinHelpcodeHintsButton.identifier = @"quanpinHelpcodeHints";
    _shuangpinHelpcodeHintsButton = [NSButton checkboxWithTitle:@"在候选窗口中显示双拼辅助码"
                                                         target:self
                                                         action:@selector(schemeHelpcodeChanged:)];
    _shuangpinHelpcodeHintsButton.identifier = @"shuangpinHelpcodeHints";
    _localInputModesButton = [NSButton checkboxWithTitle:@"启用本地输入模式（Shift+U/T/K/J）"
                                                  target:self
                                                  action:@selector(localInputModesChanged:)];
    _localInputModesButton.toolTip =
        @"未组词时按 Shift+U 输入 Unicode 码点，Shift+T 输入日期时间，Shift+K 输入快捷短语，Shift+J 超级简拼。"
        @"关闭时这些组合照常输入大写字母。";
    NSArray<NSString *> *helpcodeSchemeTitles = @[ @"蓝天小雨点", @"自然码", @"首右2.0", @"首右plus", @"小鹤" ];
    _quanpinHelpcodeSchemaButton = [[NSPopUpButton alloc] initWithFrame:NSZeroRect pullsDown:NO];
    [_quanpinHelpcodeSchemaButton addItemsWithTitles:helpcodeSchemeTitles];
    _quanpinHelpcodeSchemaButton.target = self;
    _quanpinHelpcodeSchemaButton.action = @selector(quanpinHelpcodeSchemaChanged:);
    _quanpinHelpcodeSchemaButton.accessibilityLabel = @"全拼辅助码方案";
    _shuangpinHelpcodeSchemaButton = [[NSPopUpButton alloc] initWithFrame:NSZeroRect pullsDown:NO];
    [_shuangpinHelpcodeSchemaButton addItemsWithTitles:helpcodeSchemeTitles];
    _shuangpinHelpcodeSchemaButton.target = self;
    _shuangpinHelpcodeSchemaButton.action = @selector(shuangpinHelpcodeSchemaChanged:);
    _shuangpinHelpcodeSchemaButton.accessibilityLabel = @"双拼辅助码方案";
    _candidateLearningButton = [NSButton checkboxWithTitle:@"记住候选词频"
                                                    target:self
                                                    action:@selector(candidateLearningChanged:)];
    _frequencyModeButton = [[NSPopUpButton alloc] initWithFrame:NSZeroRect pullsDown:NO];
    [_frequencyModeButton addItemsWithTitles:@[ @"一次置顶", @"折半调频", @"线性调频", @"一次置前" ]];
    _frequencyModeButton.target = self;
    _frequencyModeButton.action = @selector(frequencyModeChanged:);
    _frequencyModeButton.accessibilityLabel = @"调频方式";
    _frequencyTriggerCountButton = [[NSPopUpButton alloc] initWithFrame:NSZeroRect pullsDown:NO];
    [_frequencyTriggerCountButton addItemsWithTitles:@[ @"1", @"2", @"3", @"4", @"5", @"6" ]];
    _frequencyTriggerCountButton.target = self;
    _frequencyTriggerCountButton.action = @selector(frequencyTriggerCountChanged:);
    _frequencyTriggerCountButton.accessibilityLabel = @"触发频次";
    _frequencyLinearStepButton = [[NSPopUpButton alloc] initWithFrame:NSZeroRect pullsDown:NO];
    [_frequencyLinearStepButton addItemsWithTitles:@[ @"1", @"2", @"3", @"4", @"5", @"6" ]];
    _frequencyLinearStepButton.target = self;
    _frequencyLinearStepButton.action = @selector(frequencyLinearStepChanged:);
    _frequencyLinearStepButton.accessibilityLabel = @"线性调频步长";

    _statusLabel = [NSTextField labelWithString:@"检查词库状态…"];
    _statusLabel.accessibilityLabel = @"词库状态";
    _statusLabel.textColor = [NSColor secondaryLabelColor];
    _statusLabel.maximumNumberOfLines = 2;

    _resetLearningButton = [NSButton buttonWithTitle:@"清除学习数据…"
                                              target:self
                                              action:@selector(confirmResetLearningData:)];
    _resetLearningButton.bezelStyle = NSBezelStyleRounded;
    _resetLearningButton.contentTintColor = [NSColor systemRedColor];
    _resetLearningButton.accessibilityLabel = @"清除学习数据";

    NSView *helpcodePage = PreferencesPage(@"辅助码", @"为全拼与双拼分别选择辅助码方案。", @[
        CardWithViews(
            @[
                _shuangpinHelpcodeEnabledButton, PreferenceRow(@"双拼辅助码方案", _shuangpinHelpcodeSchemaButton),
                _shuangpinHelpcodeHintsButton
            ],
            12.0),
        CardWithViews(
            @[
                _helpcodeButton, PreferenceRow(@"全拼辅助码方案", _quanpinHelpcodeSchemaButton),
                _quanpinHelpcodeHintsButton
            ],
            12.0)
    ]);
    helpcodePage.accessibilityLabel = @"辅助码设置页";
    NSBox *learningCard = CardWithViews(
        @[
            _candidateLearningButton, PreferenceRow(@"调频方式", _frequencyModeButton),
            PreferenceRow(@"触发频次", _frequencyTriggerCountButton),
            PreferenceRow(@"线性调频步长", _frequencyLinearStepButton), _localInputModesButton
        ],
        9.0);
    NSBox *dictionaryCard = CardWithViews(@[ _statusLabel ], 0.0);
    NSBox *resetCard =
        CardWithViews(@[ PreferenceRow(@"候选词频、用户词典与拼音学习记录", _resetLearningButton) ], 0.0);
    learningCard.accessibilityLabel = @"候选与学习卡片";
    NSView *generalPage = PreferencesPage(@"键盘输入", @"选择中文或日语输入模式，并调整日常输入行为。", @[
        languageCard, SectionLabel(@"中文输入方案"), schemeCard, SectionLabel(@"翻页键 · 可同时启用多组"), pagingCard,
        SectionLabel(@"以词定字"), edgeCard, SectionLabel(@"中英混输"), mixedCard, SectionLabel(@"默认状态与简繁输出"),
        modeCard, SectionLabel(@"候选词翻译与云候选"), translationCard, SectionLabel(@"标点与输入行为"),
        punctuationCard, behaviorCard, SectionLabel(@"调频与候选学习"), learningCard
    ]);
    generalPage.accessibilityLabel = @"键盘输入设置页";
    resetCard.accessibilityLabel = @"数据与隐私卡片";
    NSView *dataPage =
        PreferencesPage(@"词库与数据", @"管理候选学习、辅助码与本机词库状态。",
                        @[ SectionLabel(@"词库状态"), dictionaryCard, SectionLabel(@"数据与隐私"), resetCard ]);
    dataPage.accessibilityLabel = @"词库与数据设置页";

    _versionLabel = [NSTextField labelWithString:@"开发构建"];
    _versionLabel.textColor = [NSColor secondaryLabelColor];
    _versionLabel.alignment = NSTextAlignmentRight;
    _versionLabel.accessibilityLabel = @"当前版本";

    _automaticUpdateLabel = [NSTextField labelWithString:@"检查自动更新状态…"];
    _automaticUpdateLabel.textColor = [NSColor secondaryLabelColor];
    _automaticUpdateLabel.alignment = NSTextAlignmentRight;
    _automaticUpdateLabel.accessibilityLabel = @"自动更新状态";

    _updatePageButton = [NSButton buttonWithTitle:@"检查更新…" target:self action:@selector(checkForUpdates:)];
    _updatePageButton.bezelStyle = NSBezelStyleRounded;
    _updatePageButton.accessibilityLabel = @"立即检查更新";

    NSButton *feedbackButton = [NSButton buttonWithTitle:@"提交反馈…" target:self action:@selector(openFeedback:)];
    feedbackButton.bezelStyle = NSBezelStyleInline;
    feedbackButton.accessibilityLabel = @"提交反馈";
    feedbackButton.contentTintColor = [NSColor linkColor];
    feedbackButton.attributedTitle = [[NSAttributedString alloc]
        initWithString:feedbackButton.title
            attributes:@{
                NSFontAttributeName : [NSFont systemFontOfSize:13.0 weight:NSFontWeightMedium],
                NSForegroundColorAttributeName : [NSColor linkColor],
            }];

    NSButton *productWebsiteButton = [NSButton buttonWithTitle:@"访问 msime.app"
                                                        target:self
                                                        action:@selector(openWebsite:)];
    productWebsiteButton.bezelStyle = NSBezelStyleInline;
    productWebsiteButton.accessibilityLabel = @"访问水杉官网";
    productWebsiteButton.contentTintColor = [NSColor linkColor];
    productWebsiteButton.attributedTitle = [[NSAttributedString alloc]
        initWithString:productWebsiteButton.title
            attributes:@{
                NSFontAttributeName : [NSFont systemFontOfSize:13.0 weight:NSFontWeightMedium],
                NSForegroundColorAttributeName : [NSColor linkColor],
            }];

    NSButton *accountButton = [NSButton buttonWithTitle:@"管理水杉账号…"
                                                 target:self
                                                 action:@selector(showBackendAccount:)];
    accountButton.bezelStyle = NSBezelStyleRounded;
    accountButton.accessibilityIdentifier = @"MetasequoiaBackendAccount";
    NSBox *accountCard = CardWithViews(@[ PreferenceRow(@"登录与账号管理", accountButton) ], 4.0);

    NSBox *updateCard = CardWithViews(
        @[
            PreferenceRow(@"当前版本", _versionLabel),
            PreferenceRow(@"自动更新", _automaticUpdateLabel),
            PreferenceRow(@"立即检查", _updatePageButton),
        ],
        4.0);
    updateCard.accessibilityLabel = @"软件更新卡片";
    NSBox *feedbackCard = CardWithViews(
        @[
            PreferenceRow(@"问题反馈与功能建议", feedbackButton),
            PreferenceRow(@"产品主页与使用帮助", productWebsiteButton),
        ],
        4.0);
    feedbackCard.accessibilityLabel = @"反馈与帮助卡片";
    NSView *updatesPage = PreferencesPage(@"更新与反馈", @"保持水杉输入法为最新版本，并告诉我们哪里还可以做得更好。", @[
        SectionLabel(@"水杉账号"), accountCard, SectionLabel(@"软件更新"), updateCard, SectionLabel(@"反馈与帮助"),
        feedbackCard
    ]);
    updatesPage.accessibilityLabel = @"更新与反馈设置页";

    _preferencePages = @[
        generalPage, appearancePage, _skinSettings, dataPage, updatesPage, wubiPage, helpcodePage, shortcutsPage,
        floatingPage
    ];

    NSButton *restoreButton = [NSButton buttonWithTitle:@"恢复默认设置" target:self action:@selector(restoreDefaults:)];
    restoreButton.bezelStyle = NSBezelStyleRounded;
    restoreButton.translatesAutoresizingMaskIntoConstraints = NO;

    NSButton *closeButton = [NSButton buttonWithTitle:@"关闭" target:self action:@selector(close:)];
    closeButton.bezelStyle = NSBezelStyleRounded;
    closeButton.keyEquivalent = @"\r";
    closeButton.translatesAutoresizingMaskIntoConstraints = NO;

    [contentView addSubview:settingsPanel];
    [settingsPanel addSubview:pageContainer];
    for (NSView *page in _preferencePages)
    {
        [pageContainer addSubview:page];
        [NSLayoutConstraint activateConstraints:@[
            [page.leadingAnchor constraintEqualToAnchor:pageContainer.leadingAnchor],
            [page.trailingAnchor constraintEqualToAnchor:pageContainer.trailingAnchor],
            [page.topAnchor constraintEqualToAnchor:pageContainer.topAnchor],
            [page.bottomAnchor constraintEqualToAnchor:pageContainer.bottomAnchor],
        ]];
    }
    [settingsPanel addSubview:restoreButton];
    [settingsPanel addSubview:closeButton];

    [NSLayoutConstraint activateConstraints:@[
        [settingsPanel.leadingAnchor constraintEqualToAnchor:sidebar.trailingAnchor],
        [settingsPanel.trailingAnchor constraintEqualToAnchor:contentView.trailingAnchor],
        [settingsPanel.topAnchor constraintEqualToAnchor:contentView.topAnchor],
        [settingsPanel.bottomAnchor constraintEqualToAnchor:contentView.bottomAnchor],
        [pageContainer.leadingAnchor constraintEqualToAnchor:settingsPanel.leadingAnchor],
        [pageContainer.trailingAnchor constraintEqualToAnchor:settingsPanel.trailingAnchor],
        [pageContainer.topAnchor constraintEqualToAnchor:settingsPanel.topAnchor],
        [pageContainer.bottomAnchor constraintEqualToAnchor:restoreButton.topAnchor constant:-16.0],
        [restoreButton.leadingAnchor constraintEqualToAnchor:settingsPanel.leadingAnchor constant:30.0],
        [restoreButton.bottomAnchor constraintEqualToAnchor:settingsPanel.bottomAnchor constant:-20.0],
        [closeButton.trailingAnchor constraintEqualToAnchor:settingsPanel.trailingAnchor constant:-30.0],
        [closeButton.centerYAnchor constraintEqualToAnchor:restoreButton.centerYAnchor],
        [closeButton.widthAnchor constraintGreaterThanOrEqualToConstant:80.0],
    ]];
    [self showPreferencesPageAtIndex:1 navigationIndex:1];
    [self refreshUpdateControls];
    return self;
}

- (void)showBackendAccount:(id)sender
{
    (void)sender;
    MSIMEShowBackendAccount();
}

- (void)refreshUpdateControls
{
    NSString *version = [NSBundle.mainBundle objectForInfoDictionaryKey:@"CFBundleShortVersionString"];
    _versionLabel.stringValue = version.length == 0 ? @"开发构建" : [NSString stringWithFormat:@"v%@", version];
    _automaticUpdateLabel.stringValue =
        _updateController.automaticallyChecksForUpdates ? @"已开启自动检查" : @"自动检查已关闭";
    _updatePageButton.toolTip = @"通过 msime.app 检查水杉输入法的最新正式版本";
    _updatePageButton.accessibilityHelp =
        version.length == 0 ? @"通过 msime.app 检查最新正式版本"
                            : [NSString stringWithFormat:@"当前版本 v%@，通过 msime.app 检查最新正式版本", version];
    _updatePageButton.enabled = YES;
}

- (void)checkForUpdates:(id)sender
{
    [_updateController checkForUpdates:sender];
}

- (void)selectPreferencesPage:(NSButton *)sender
{
    const NSInteger selectedIndex = sender.tag;
    if (selectedIndex >= 9)
    {
        sender.state = NSControlStateValueOff;
        if (selectedIndex == 9)
            [[MetasequoiaVoiceSettingsWindow sharedController] showAndActivate];
        else if (selectedIndex == 10)
            [self openWebsite:nil];
        else if (selectedIndex == 11)
            [self openFeedback:nil];
        return;
    }
    [self showPreferencesPageAtIndex:selectedIndex navigationIndex:selectedIndex];
}

- (void)showPreferencesPageAtIndex:(NSInteger)pageIndex navigationIndex:(NSInteger)navigationIndex
{
    for (NSInteger index = 0; index < static_cast<NSInteger>(_preferencePages.count); ++index)
    {
        const BOOL selected = index == pageIndex;
        _preferencePages[index].hidden = !selected;
    }
    for (NSButton *button in _navigationButtons)
    {
        button.state = button.tag == navigationIndex ? NSControlStateValueOn : NSControlStateValueOff;
        button.needsDisplay = YES;
    }
}

- (void)showWubiSettings:(id)sender
{
    (void)sender;
    [self refreshControls];
    [self showPreferencesPageAtIndex:5 navigationIndex:0];
}

- (void)backToKeyboardInput:(id)sender
{
    (void)sender;
    [self showPreferencesPageAtIndex:0 navigationIndex:0];
}

- (void)openWebsite:(id)sender
{
    (void)sender;
    NSURL *website = [NSURL URLWithString:@"https://msime.app/"];
    if (website != nil)
    {
        [[NSWorkspace sharedWorkspace] openURL:website];
    }
}

- (void)openFeedback:(id)sender
{
    (void)sender;
    NSURL *feedback = [NSURL URLWithString:@"https://github.com/metasequoiaime/MSIME-Apple/issues/new"];
    if (feedback != nil)
    {
        [[NSWorkspace sharedWorkspace] openURL:feedback];
    }
}

- (void)dealloc
{
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    [NSDistributedNotificationCenter.defaultCenter removeObserver:self];
}

- (void)appearancePreferencesChanged:(NSNotification *)notification
{
    (void)notification;
    [NSUserDefaults.standardUserDefaults synchronize];
    self.window.appearance = MetasequoiaForcedAppearance();
    [self refreshAdvancedAppearanceControls];
    [_candidatePreview updatePanelStyle:[MetasequoiaPreferencesWindowController storedCandidatePanelStyle]
                               pageSize:[MetasequoiaPreferencesWindowController storedCandidatePageSize]
                               fontSize:[MetasequoiaPreferencesWindowController storedCandidateFontSize]];
    [_skinSettings refreshSelection];
}

- (void)refreshAdvancedAppearanceControls
{
    if (_candidateFontButton == nil)
        return;
    NSDictionary *values = MetasequoiaAppearancePreferences();
    for (NSPopUpButton *button in @[ _candidateFontButton, _candidateFallbackFontButton ])
    {
        NSString *key = button == _candidateFontButton ? @"font" : @"fallbackFont";
        NSInteger index = [button indexOfItemWithRepresentedObject:values[key] ? values[key] : @""];
        [button selectItemAtIndex:index == -1 ? 0 : index];
    }
    _followCaretSwitch.state = MetasequoiaCandidateFollowsCaret() ? NSControlStateValueOn : NSControlStateValueOff;
    [_preeditFontSizeButton selectItemAtIndex:MetasequoiaAppearanceInteger(@"preeditSize", 15, 10, 36) - 10];
    [_themeButton selectItemAtIndex:MetasequoiaAppearanceInteger(@"theme", 0, 0, 2)];
    NSColor *color = MetasequoiaCandidateTextColor();
    _candidateColorWell.color = color ? color : [_candidatePreview previewTextColor];
}

- (void)advancedAppearanceChanged:(id)sender
{
    if (sender == _candidateFontButton || sender == _candidateFallbackFontButton)
        MetasequoiaSetAppearancePreference(sender == _candidateFontButton ? @"font" : @"fallbackFont",
                                           [(NSPopUpButton *)sender selectedItem].representedObject);
    else if (sender == _preeditFontSizeButton)
        MetasequoiaSetAppearancePreference(@"preeditSize", @(_preeditFontSizeButton.indexOfSelectedItem + 10));
    else if (sender == _themeButton)
        MetasequoiaSetAppearancePreference(@"theme", @(_themeButton.indexOfSelectedItem));
    else if (sender == _followCaretSwitch)
        MetasequoiaSetAppearancePreference(@"followCaret", @(_followCaretSwitch.state == NSControlStateValueOn));
    else if (sender == _candidateColorWell)
    {
        NSColor *color = [_candidateColorWell.color colorUsingColorSpace:NSColorSpace.sRGBColorSpace];
        if (color)
            MetasequoiaSetAppearancePreference(
                @"textColor", @[ @(color.redComponent), @(color.greenComponent), @(color.blueComponent) ]);
    }
}

- (void)resetCandidateColor:(id)sender
{
    (void)sender;
    MetasequoiaSetAppearancePreference(@"textColor", nil);
}

- (void)floatingToolbarPreferenceDidChange:(NSNotification *)notification
{
    (void)notification;
    _floatingToolbarButton.state = [MetasequoiaPreferencesWindowController storedFloatingToolbarEnabled]
                                       ? NSControlStateValueOn
                                       : NSControlStateValueOff;
}

- (void)chinesePunctuationPreferenceDidChange:(NSNotification *)notification
{
    (void)notification;
    _chinesePunctuationButton.state = [MetasequoiaPreferencesWindowController storedChinesePunctuationEnabled]
                                          ? NSControlStateValueOn
                                          : NSControlStateValueOff;
}

- (void)fullWidthInputPreferenceDidChange:(NSNotification *)notification
{
    (void)notification;
    _fullWidthInputButton.state = [MetasequoiaPreferencesWindowController storedFullWidthInputEnabled]
                                      ? NSControlStateValueOn
                                      : NSControlStateValueOff;
}

- (void)refreshControls
{
    [self refreshAdvancedAppearanceControls];
    const NSInteger storedScheme = [MetasequoiaPreferencesWindowController storedScheme];
    for (NSInteger index = 0; index < static_cast<NSInteger>(_schemeButtons.count); ++index)
    {
        _schemeButtons[index].state = index == storedScheme ? NSControlStateValueOn : NSControlStateValueOff;
    }
    _shuangpinSchemeButton.enabled = storedScheme == 1;
    NSString *storedShuangpinSchema = [MetasequoiaPreferencesWindowController storedShuangpinSchema];
    for (NSMenuItem *item in _shuangpinSchemeButton.itemArray)
    {
        if ([item.representedObject isEqualToString:storedShuangpinSchema])
        {
            [_shuangpinSchemeButton selectItem:item];
            break;
        }
    }
    _wubiSchemeButton.enabled = storedScheme == 2;
    _shuangpinKeymapRow.hidden = storedScheme != 1;
    _shuangpinKeymapSeparator.hidden = storedScheme != 1;
    _wubiSettingsRow.hidden = storedScheme != 2;
    _shuangpinKeymapButton.state = [MetasequoiaPreferencesWindowController storedShuangpinKeymapEnabled]
                                       ? NSControlStateValueOn
                                       : NSControlStateValueOff;
    _autocorrectButton.state = [MetasequoiaPreferencesWindowController storedAutocorrectEnabled]
                                   ? NSControlStateValueOn
                                   : NSControlStateValueOff;
    const BOOL legacyHelpcode = [MetasequoiaPreferencesWindowController storedHelpcodeEnabled];
    _helpcodeButton.state = MetasequoiaInputFlag(@"quanpinHelpcodeEnabled", legacyHelpcode);
    _shuangpinHelpcodeEnabledButton.state = MetasequoiaInputFlag(@"shuangpinHelpcodeEnabled", legacyHelpcode);
    _quanpinHelpcodeHintsButton.state = MetasequoiaInputFlag(@"quanpinHelpcodeHints", YES);
    _shuangpinHelpcodeHintsButton.state = MetasequoiaInputFlag(@"shuangpinHelpcodeHints", YES);
    _quanpinHelpcodeHintsButton.enabled = _helpcodeButton.state == NSControlStateValueOn;
    _shuangpinHelpcodeHintsButton.enabled = _shuangpinHelpcodeEnabledButton.state == NSControlStateValueOn;
    _localInputModesButton.state = [MetasequoiaPreferencesWindowController storedLocalInputModesEnabled]
                                       ? NSControlStateValueOn
                                       : NSControlStateValueOff;
    [_quanpinHelpcodeSchemaButton
        selectItemAtIndex:[MetasequoiaPreferencesWindowController storedQuanpinHelpcodeSchema]];
    [_shuangpinHelpcodeSchemaButton
        selectItemAtIndex:[MetasequoiaPreferencesWindowController storedShuangpinHelpcodeSchema]];
    _quanpinHelpcodeSchemaButton.enabled = _helpcodeButton.state == NSControlStateValueOn;
    _shuangpinHelpcodeSchemaButton.enabled = _shuangpinHelpcodeEnabledButton.state == NSControlStateValueOn;
    _chinesePunctuationButton.state = [MetasequoiaPreferencesWindowController storedChinesePunctuationEnabled]
                                          ? NSControlStateValueOn
                                          : NSControlStateValueOff;
    [_candidatePanelStyleButton selectItemAtIndex:[MetasequoiaPreferencesWindowController storedCandidatePanelStyle]];
    [_candidatePageSizeButton
        selectItemAtIndex:static_cast<NSInteger>(metasequoia::mac::CandidatePageSizeOptionIndex(
                              static_cast<size_t>([MetasequoiaPreferencesWindowController storedCandidatePageSize])))];
    [_candidateFontSizeButton
        selectItemAtIndex:static_cast<NSInteger>(metasequoia::mac::CandidateFontSizeOptionIndex(
                              static_cast<size_t>([MetasequoiaPreferencesWindowController storedCandidateFontSize])))];
    [_candidatePageShortcutButton
        selectItemAtIndex:[MetasequoiaPreferencesWindowController storedCandidatePageShortcut]];
    [self refreshInputBehaviorControls];
    [self refreshSkinControl];
    [self refreshCandidatePreview];
    _candidateTranslationsButton.state = [MetasequoiaPreferencesWindowController storedCandidateTranslationsEnabled]
                                             ? NSControlStateValueOn
                                             : NSControlStateValueOff;
    _candidateLearningButton.state = [MetasequoiaPreferencesWindowController storedCandidateLearningEnabled]
                                         ? NSControlStateValueOn
                                         : NSControlStateValueOff;
    [_frequencyModeButton
        selectItemAtIndex:metasequoia::mac::FrequencyAdjustmentModeOptionIndex(
                              [MetasequoiaPreferencesWindowController storedFrequencyAdjustmentMode].UTF8String)];
    [_frequencyTriggerCountButton
        selectItemAtIndex:[MetasequoiaPreferencesWindowController storedFrequencyTriggerCount] - 1];
    [_frequencyLinearStepButton
        selectItemAtIndex:[MetasequoiaPreferencesWindowController storedFrequencyLinearStep] - 1];
    [self updateFrequencyControlEnabled];
    _inputModeHUDButton.state = [MetasequoiaPreferencesWindowController storedInputModeHUDEnabled]
                                    ? NSControlStateValueOn
                                    : NSControlStateValueOff;
    _inputModeShortcutButton.state = [MetasequoiaPreferencesWindowController storedInputModeShortcutEnabled]
                                         ? NSControlStateValueOn
                                         : NSControlStateValueOff;
    _fullWidthInputButton.state = [MetasequoiaPreferencesWindowController storedFullWidthInputEnabled]
                                      ? NSControlStateValueOn
                                      : NSControlStateValueOff;
    _floatingToolbarButton.state = [MetasequoiaPreferencesWindowController storedFloatingToolbarEnabled]
                                       ? NSControlStateValueOn
                                       : NSControlStateValueOff;
    _wubiMixedPinyinButton.state = [MetasequoiaPreferencesWindowController storedWubiMixedPinyinEnabled]
                                       ? NSControlStateValueOn
                                       : NSControlStateValueOff;
    _wubiAutoCommitButton.state = [MetasequoiaPreferencesWindowController storedWubiAutoCommitUniqueEnabled]
                                      ? NSControlStateValueOn
                                      : NSControlStateValueOff;
    _wubiCodeHintButton.state = [MetasequoiaPreferencesWindowController storedWubiCodeHintEnabled]
                                    ? NSControlStateValueOn
                                    : NSControlStateValueOff;
}

- (void)refreshDictionaryStatus
{
    NSError *error = nil;
    if (EnsureMetasequoiaDictionary(&error))
    {
        _statusLabel.stringValue = @"词库已就绪；设置将在当前输入结束后的下一次按键生效。";
        _statusLabel.textColor = [NSColor secondaryLabelColor];
        _statusLabel.toolTip = nil;
        return;
    }

    _statusLabel.stringValue = @"词库不可用，请重新安装水杉输入法。";
    _statusLabel.textColor = [NSColor systemRedColor];
    _statusLabel.toolTip = error.localizedDescription;
}

- (void)presentAndActivate
{
    [self refreshControls];
    [self refreshDictionaryStatus];
    [self refreshUpdateControls];
    if (_standaloneLaunch)
    {
        _resetLearningButton.enabled = NO;
        _resetLearningButton.toolTip = @"请从水杉输入菜单打开设置后再清除学习数据。";
        _resetLearningButton.accessibilityHelp = @"独立设置不能安全清除学习数据；请从水杉输入菜单打开设置。";
    }
    else
    {
        _resetLearningButton.enabled = YES;
        _resetLearningButton.toolTip = nil;
        _resetLearningButton.accessibilityHelp = nil;
    }
    [self showWindow:nil];
    [self.window center];
    [self.window makeKeyAndOrderFront:nil];
    [NSApp activateIgnoringOtherApps:YES];
}

- (void)showAndActivate
{
    _standaloneLaunch = NO;
    [self presentAndActivate];
}

- (void)showAndActivateForStandaloneLaunch
{
    _standaloneLaunch = YES;
    [self presentAndActivate];
}

- (void)windowWillClose:(NSNotification *)notification
{
    (void)notification;
    if (_standaloneLaunch)
    {
        _standaloneLaunch = NO;
        dispatch_async(dispatch_get_main_queue(), ^{
          [[NSNotificationCenter defaultCenter]
              postNotificationName:MetasequoiaStandalonePreferencesDidCloseNotification
                            object:self];
        });
    }
}

- (void)autocorrectChanged:(id)sender
{
    NSButton *button = (NSButton *)sender;
    [MetasequoiaPreferencesWindowController setAutocorrectEnabled:button.state == NSControlStateValueOn];
}

- (void)localInputModesChanged:(id)sender
{
    NSButton *button = (NSButton *)sender;
    [MetasequoiaPreferencesWindowController setLocalInputModesEnabled:button.state == NSControlStateValueOn];
    [self refreshControls];
}

- (void)schemeHelpcodeChanged:(NSButton *)sender
{
    MetasequoiaSetInputBehavior(sender.identifier, sender.state == NSControlStateValueOn);
    [[NSNotificationCenter defaultCenter] postNotificationName:@"MetasequoiaHelpcodeDidChangeNotification" object:nil];
    [self refreshControls];
}

- (void)helpcodeChanged:(id)sender
{
    NSButton *button = (NSButton *)sender;
    [MetasequoiaPreferencesWindowController setHelpcodeEnabled:button.state == NSControlStateValueOn];
    [self refreshControls];
}

- (void)quanpinHelpcodeSchemaChanged:(id)sender
{
    NSPopUpButton *schemaButton = (NSPopUpButton *)sender;
    [MetasequoiaPreferencesWindowController setQuanpinHelpcodeSchema:schemaButton.indexOfSelectedItem];
}

- (void)shuangpinHelpcodeSchemaChanged:(id)sender
{
    NSPopUpButton *schemaButton = (NSPopUpButton *)sender;
    [MetasequoiaPreferencesWindowController setShuangpinHelpcodeSchema:schemaButton.indexOfSelectedItem];
}

- (void)chinesePunctuationChanged:(id)sender
{
    NSButton *button = (NSButton *)sender;
    [MetasequoiaPreferencesWindowController setChinesePunctuationEnabled:button.state == NSControlStateValueOn];
}

- (void)schemeChanged:(id)sender
{
    NSButton *schemeButton = (NSButton *)sender;
    [MetasequoiaPreferencesWindowController setStoredScheme:schemeButton.tag];
    [self refreshControls];
}

- (void)refreshCandidatePreview
{
    [_candidatePreview updatePanelStyle:[MetasequoiaPreferencesWindowController storedCandidatePanelStyle]
                               pageSize:[MetasequoiaPreferencesWindowController storedCandidatePageSize]
                               fontSize:[MetasequoiaPreferencesWindowController storedCandidateFontSize]];
    [_candidatePreview
        setTranslationsEnabled:[MetasequoiaPreferencesWindowController storedCandidateTranslationsEnabled]];
}

- (void)shuangpinSchemaChanged:(id)sender
{
    NSPopUpButton *schemaButton = (NSPopUpButton *)sender;
    [MetasequoiaPreferencesWindowController setShuangpinSchema:schemaButton.selectedItem.representedObject];
}

- (void)candidatePanelStyleChanged:(id)sender
{
    NSPopUpButton *styleButton = (NSPopUpButton *)sender;
    [MetasequoiaPreferencesWindowController setCandidatePanelStyle:styleButton.indexOfSelectedItem];
    [self refreshCandidatePreview];
}

- (void)candidatePageSizeChanged:(id)sender
{
    NSPopUpButton *pageSizeButton = (NSPopUpButton *)sender;
    const size_t pageSize =
        metasequoia::mac::CandidatePageSizeForOptionIndex(static_cast<size_t>(pageSizeButton.indexOfSelectedItem));
    [MetasequoiaPreferencesWindowController setCandidatePageSize:static_cast<NSInteger>(pageSize)];
    [self refreshCandidatePreview];
}

- (void)candidateFontSizeChanged:(id)sender
{
    NSPopUpButton *fontSizeButton = (NSPopUpButton *)sender;
    const size_t fontSize =
        metasequoia::mac::CandidateFontSizeForOptionIndex(static_cast<size_t>(fontSizeButton.indexOfSelectedItem));
    [MetasequoiaPreferencesWindowController setCandidateFontSize:static_cast<NSInteger>(fontSize)];
    [self refreshCandidatePreview];
}

- (void)candidateTranslationsChanged:(id)sender
{
    NSButton *button = (NSButton *)sender;
    [MetasequoiaPreferencesWindowController setCandidateTranslationsEnabled:button.state == NSControlStateValueOn];
    [self refreshCandidatePreview];
}

- (void)refreshSkinControl
{
    [_candidatePreview reloadPreview];
    [_skinSettings refreshSelection];
}

- (void)candidateSkinPreferenceDidChange:(NSNotification *)notification
{
    (void)notification;
    [self refreshSkinControl];
}

- (void)candidateLearningChanged:(id)sender
{
    NSButton *button = (NSButton *)sender;
    [MetasequoiaPreferencesWindowController setCandidateLearningEnabled:button.state == NSControlStateValueOn];
    [self updateFrequencyControlEnabled];
}

- (void)updateFrequencyControlEnabled
{
    const BOOL learning = _candidateLearningButton.state == NSControlStateValueOn;
    _frequencyModeButton.enabled = learning;
    _frequencyTriggerCountButton.enabled = learning;
    _frequencyLinearStepButton.enabled = learning && _frequencyModeButton.indexOfSelectedItem == 2;
}

- (void)frequencyModeChanged:(id)sender
{
    NSPopUpButton *modeButton = (NSPopUpButton *)sender;
    [MetasequoiaPreferencesWindowController
        setFrequencyAdjustmentMode:@(metasequoia::mac::FrequencyAdjustmentModeForOptionIndex(
                                       static_cast<int>(modeButton.indexOfSelectedItem)))];
    [self updateFrequencyControlEnabled];
}

- (void)frequencyTriggerCountChanged:(id)sender
{
    NSPopUpButton *countButton = (NSPopUpButton *)sender;
    [MetasequoiaPreferencesWindowController setFrequencyTriggerCount:countButton.indexOfSelectedItem + 1];
}

- (void)frequencyLinearStepChanged:(id)sender
{
    NSPopUpButton *stepButton = (NSPopUpButton *)sender;
    [MetasequoiaPreferencesWindowController setFrequencyLinearStep:stepButton.indexOfSelectedItem + 1];
}

- (void)candidatePageShortcutChanged:(id)sender
{
    NSPopUpButton *shortcutButton = (NSPopUpButton *)sender;
    [MetasequoiaPreferencesWindowController setCandidatePageShortcut:shortcutButton.indexOfSelectedItem];
    MetasequoiaSetInputBehavior(@"pageMinus", shortcutButton.indexOfSelectedItem == 0);
    MetasequoiaSetInputBehavior(@"pageBrackets", shortcutButton.indexOfSelectedItem == 1);
    MetasequoiaSetInputBehavior(@"pageKeys", 1);
    [self refreshInputBehaviorControls];
}

- (void)refreshInputBehaviorControls
{
    const auto keys =
        MetasequoiaCandidateKeyOptions([MetasequoiaPreferencesWindowController storedCandidatePageShortcut]);
    NSDictionary *states = @{
        @"pageMinus" : @(keys.minusEqual),
        @"pageComma" : @(keys.commaPeriod),
        @"pageBrackets" : @(keys.brackets),
        @"pageKeys" : @(keys.pageKeys),
        @"verticalNavigation" : @(keys.verticalNavigation),
        @"edgeSelection" : @(keys.edgeSelection),
        @"mixedEnglish" : @(MetasequoiaInputInteger(@"mixedEnglish", 0, 0, 1))
    };
    for (NSButton *button in _inputBehaviorButtons)
        button.state = [states[button.identifier] boolValue] ? NSControlStateValueOn : NSControlStateValueOff;
    [_englishMinimumPrefixButton selectItemAtIndex:MetasequoiaInputInteger(@"englishMinimumPrefix", 2, 1, 10) - 1];
    _englishMinimumPrefixButton.enabled = [states[@"mixedEnglish"] boolValue];
    [_defaultInputModeButton selectItemAtIndex:MetasequoiaInputInteger(@"defaultEnglish", 0, 0, 1)];
    [_inputModeScopeButton selectItemAtIndex:MetasequoiaInputInteger(@"perApplicationMode", 0, 0, 1)];
    [_outputScriptButton
        selectItemAtIndex:[MetasequoiaPreferencesWindowController storedTraditionalChineseOutputEnabled] ? 1 : 0];
    [_languageModeButton selectItemAtIndex:MetasequoiaInputInteger(@"japaneseMode", 0, 0, 1)];
    _alwaysChinesePunctuationButton.state =
        MetasequoiaInputFlag(@"alwaysChinesePunctuation") ? NSControlStateValueOn : NSControlStateValueOff;
    _alwaysEnglishPunctuationButton.state =
        MetasequoiaInputFlag(@"alwaysEnglishPunctuation") ? NSControlStateValueOn : NSControlStateValueOff;
    _smartPunctuationButton.state =
        MetasequoiaInputFlag(@"smartPunctuation") ? NSControlStateValueOn : NSControlStateValueOff;
    _pairedPunctuationButton.state =
        MetasequoiaInputFlag(@"pairedPunctuation") ? NSControlStateValueOn : NSControlStateValueOff;
    _repeatPunctuationButton.state =
        MetasequoiaInputFlag(@"repeatPunctuation") ? NSControlStateValueOn : NSControlStateValueOff;
    _candidateTranslationButton.state =
        MetasequoiaInputFlag(@"candidateTranslation") ? NSControlStateValueOn : NSControlStateValueOff;
    _cloudCandidatesButton.state =
        MetasequoiaInputFlag(@"cloudCandidates") ? NSControlStateValueOn : NSControlStateValueOff;
    [_translationProviderButton
        selectItemAtIndex:MetasequoiaInputInteger(@"translationProvider", 0, 0,
                                                  _translationProviderButton.numberOfItems - 1)];
    [_translationLanguageButton
        selectItemAtIndex:MetasequoiaInputInteger(@"translationLanguage", 0, 0,
                                                  _translationLanguageButton.numberOfItems - 1)];
    const BOOL translating = _candidateTranslationButton.state == NSControlStateValueOn;
    _translationProviderButton.enabled = translating;
    _translationLanguageButton.enabled = translating;
    // Each provider shows only what it needs: the account model asks for nothing, and leaving a
    // vendor's key fields under it reads as though it wanted them.
    const auto provider = metasequoia::mac::CandidateTranslationProviderAt(
        static_cast<std::size_t>(_translationProviderButton.indexOfSelectedItem));
    const BOOL tencent = provider == metasequoia::mac::CandidateTranslationProvider::TencentMachineTranslation;
    const BOOL deeplx = provider == metasequoia::mac::CandidateTranslationProvider::DeepLX;
    const BOOL accountModel = provider == metasequoia::mac::CandidateTranslationProvider::AccountModel;
    _translationSecretIdField.enabled = translating && tencent;
    _translationSecretKeyField.enabled = translating && tencent;
    _translationEndpointField.enabled = translating && deeplx;
    _translationTencentIdRow.hidden = !tencent;
    _translationTencentKeyRow.hidden = !tencent;
    _translationEndpointRow.hidden = !deeplx;
    _translationAccountRow.hidden = !accountModel;
    // Signed out is the one thing that stops this provider, and it stops it silently, so the card
    // says so rather than leaving someone to wonder why nothing appears beside their candidates.
    const BOOL signedIn = MSIMEBackendAccountSignedIn();
    _translationAccountLabel.stringValue =
        signedIn ? @"使用已登录的水杉账号，无需填写密钥。" : @"需要先登录水杉账号，否则候选旁不会出现译文。";
    _translationAccountButton.hidden = signedIn;
    _translationSecretIdField.placeholderString = @"SecretId（腾讯云）";
    _translationSecretKeyField.placeholderString = @"SecretKey（腾讯云）";
}

- (void)translationCredentialChanged:(NSTextField *)sender
{
    [NSUserDefaults.standardUserDefaults setObject:sender.stringValue forKey:sender.identifier];
}

- (void)translationProviderChanged:(NSPopUpButton *)sender
{
    MetasequoiaSetInputBehavior(@"translationProvider", sender.indexOfSelectedItem);
    [self refreshInputBehaviorControls];
}

- (void)inputModePreferenceChanged:(NSPopUpButton *)sender
{
    if ([sender.identifier isEqualToString:@"outputScript"])
        [MetasequoiaPreferencesWindowController setTraditionalChineseOutputEnabled:sender.indexOfSelectedItem == 1];
    else
        MetasequoiaSetInputBehavior(sender.identifier, sender.indexOfSelectedItem);
}

- (void)inputBehaviorChanged:(NSButton *)sender
{
    MetasequoiaSetInputBehavior(sender.identifier, sender.state == NSControlStateValueOn);
    [self refreshInputBehaviorControls];
}

- (void)englishMinimumPrefixChanged:(NSPopUpButton *)sender
{
    MetasequoiaSetInputBehavior(@"englishMinimumPrefix", sender.indexOfSelectedItem + 1);
}

- (void)inputModeShortcutChanged:(id)sender
{
    NSButton *button = (NSButton *)sender;
    [MetasequoiaPreferencesWindowController setInputModeShortcutEnabled:button.state == NSControlStateValueOn];
}

- (void)inputModeHUDChanged:(id)sender
{
    NSButton *button = (NSButton *)sender;
    [MetasequoiaPreferencesWindowController setInputModeHUDEnabled:button.state == NSControlStateValueOn];
}

- (void)fullWidthInputChanged:(id)sender
{
    NSButton *button = (NSButton *)sender;
    [MetasequoiaPreferencesWindowController setFullWidthInputEnabled:button.state == NSControlStateValueOn];
}

- (void)floatingToolbarChanged:(id)sender
{
    NSButton *button = (NSButton *)sender;
    [MetasequoiaPreferencesWindowController setFloatingToolbarEnabled:button.state == NSControlStateValueOn];
}

- (void)wubiMixedPinyinChanged:(id)sender
{
    NSButton *button = sender;
    [MetasequoiaPreferencesWindowController setWubiMixedPinyinEnabled:button.state == NSControlStateValueOn];
}

- (void)wubiCodeHintChanged:(id)sender
{
    NSButton *button = sender;
    [MetasequoiaPreferencesWindowController setWubiCodeHintEnabled:button.state == NSControlStateValueOn];
}

- (void)wubiAutoCommitUniqueChanged:(id)sender
{
    NSButton *button = (NSButton *)sender;
    [MetasequoiaPreferencesWindowController setWubiAutoCommitUniqueEnabled:button.state == NSControlStateValueOn];
}

- (void)shuangpinKeymapChanged:(id)sender
{
    NSButton *button = (NSButton *)sender;
    [MetasequoiaPreferencesWindowController setShuangpinKeymapEnabled:button.state == NSControlStateValueOn];
}

- (void)confirmResetLearningData:(id)sender
{
    (void)sender;
    NSAlert *alert = [[NSAlert alloc] init];
    alert.alertStyle = NSAlertStyleWarning;
    alert.messageText = @"清除所有学习数据？";
    alert.informativeText = @"候选词频、用户词典和拼音学习记录将永久删除。此操作无法撤销，输入方案等设置不会改变。";
    [alert addButtonWithTitle:@"取消"];
    [alert addButtonWithTitle:@"清除"];
    alert.buttons[0].keyEquivalent = @"\r";
    alert.buttons[1].keyEquivalent = @"";
    alert.buttons[1].hasDestructiveAction = YES;
    alert.buttons[1].accessibilityLabel = @"确认清除学习数据";
    alert.window.defaultButtonCell = (NSButtonCell *)alert.buttons[0].cell;

    [alert beginSheetModalForWindow:self.window
                  completionHandler:^(NSModalResponse response) {
                    if (response != NSAlertSecondButtonReturn)
                    {
                        return;
                    }

                    self->_resetLearningButton.enabled = NO;
                    self->_statusLabel.stringValue = @"正在清除学习数据…";
                    self->_statusLabel.textColor = [NSColor secondaryLabelColor];
                    self->_statusLabel.toolTip = nil;
                    [MetasequoiaPreferencesWindowController prepareInputSessionsForLearnedDataReset];

                    NSError *error = nil;
                    if (ResetMetasequoiaLearnedDataForCurrentUser(&error))
                    {
                        self->_statusLabel.stringValue = @"学习数据已清除；新的输入将从默认词频开始。";
                        self->_statusLabel.textColor = [NSColor systemGreenColor];
                        self->_statusLabel.toolTip = nil;
                    }
                    else
                    {
                        self->_statusLabel.stringValue = @"学习数据未能清除，请稍后重试。";
                        self->_statusLabel.textColor = [NSColor systemRedColor];
                        self->_statusLabel.toolTip = error.localizedDescription;
                    }
                    self->_resetLearningButton.enabled = YES;
                  }];
}

- (void)restoreDefaults:(id)sender
{
    (void)sender;
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    for (NSString *key in @[
             kSchemePreferenceKey,
             kShuangpinSchemaPreferenceKey,
             kAutocorrectPreferenceKey,
             kHelpcodePreferenceKey,
             kQuanpinHelpcodeSchemaPreferenceKey,
             kShuangpinHelpcodeSchemaPreferenceKey,
             kChinesePunctuationPreferenceKey,
             kCandidatePanelStylePreferenceKey,
             @"MetasequoiaImeCandidateSkin",
             kCandidatePageSizePreferenceKey,
             kCandidateFontSizePreferenceKey,
             kCandidateTranslationsPreferenceKey,
             kCandidatePageShortcutPreferenceKey,
             kCandidateLearningPreferenceKey,
             kFrequencyAdjustmentModePreferenceKey,
             kFrequencyTriggerCountPreferenceKey,
             kFrequencyLinearStepPreferenceKey,
             kInputModeShortcutPreferenceKey,
             kInputModeHUDPreferenceKey,
             kWubiAutoCommitUniquePreferenceKey,
             kWubiMixedPinyinPreferenceKey,
             kWubiCodeHintPreferenceKey,
             kShuangpinKeymapPreferenceKey,
             kLocalInputModesPreferenceKey,
             MetasequoiaAppearancePreferencesKey,
             MetasequoiaInputBehaviorKey,
             kFullWidthInputPreferenceKey,
             kFloatingToolbarPreferenceKey,
             kTraditionalChineseOutputPreferenceKey,
         ])
    {
        [defaults removeObjectForKey:key];
    }

    NSNotificationCenter *notifications = [NSNotificationCenter defaultCenter];
    MetasequoiaSetAppearancePreference(@"theme", nil);
    [notifications postNotificationName:@"MetasequoiaInputSchemeDidChangeNotification"
                                 object:@([MetasequoiaPreferencesWindowController storedScheme])];
    [notifications postNotificationName:@"MetasequoiaShuangpinSchemaDidChangeNotification"
                                 object:[MetasequoiaPreferencesWindowController storedShuangpinSchema]];
    [notifications postNotificationName:@"MetasequoiaQuanpinAutocorrectDidChangeNotification"
                                 object:@([MetasequoiaPreferencesWindowController storedAutocorrectEnabled])];
    [notifications postNotificationName:@"MetasequoiaHelpcodeDidChangeNotification"
                                 object:@([MetasequoiaPreferencesWindowController storedHelpcodeEnabled])];
    [notifications postNotificationName:@"MetasequoiaQuanpinHelpcodeSchemaDidChangeNotification"
                                 object:@([MetasequoiaPreferencesWindowController storedQuanpinHelpcodeSchema])];
    [notifications postNotificationName:@"MetasequoiaShuangpinHelpcodeSchemaDidChangeNotification"
                                 object:@([MetasequoiaPreferencesWindowController storedShuangpinHelpcodeSchema])];
    [notifications postNotificationName:@"MetasequoiaChinesePunctuationDidChangeNotification"
                                 object:@([MetasequoiaPreferencesWindowController storedChinesePunctuationEnabled])];
    [notifications postNotificationName:MetasequoiaCandidateSkinDidChangeNotification
                                 object:[MetasequoiaPreferencesWindowController storedCandidateSkin]];
    [notifications postNotificationName:@"MetasequoiaCandidatePanelStyleDidChangeNotification"
                                 object:@([MetasequoiaPreferencesWindowController storedCandidatePanelStyle])];
    [notifications postNotificationName:@"MetasequoiaCandidatePageSizeDidChangeNotification"
                                 object:@([MetasequoiaPreferencesWindowController storedCandidatePageSize])];
    [notifications postNotificationName:@"MetasequoiaCandidateFontSizeDidChangeNotification"
                                 object:@([MetasequoiaPreferencesWindowController storedCandidateFontSize])];
    [notifications postNotificationName:@"MetasequoiaCandidateTranslationsDidChangeNotification"
                                 object:@([MetasequoiaPreferencesWindowController storedCandidateTranslationsEnabled])];
    [notifications postNotificationName:@"MetasequoiaCandidatePageShortcutDidChangeNotification"
                                 object:@([MetasequoiaPreferencesWindowController storedCandidatePageShortcut])];
    [notifications postNotificationName:@"MetasequoiaCandidateLearningDidChangeNotification"
                                 object:@([MetasequoiaPreferencesWindowController storedCandidateLearningEnabled])];
    [notifications postNotificationName:@"MetasequoiaFrequencyAdjustmentDidChangeNotification"
                                 object:[MetasequoiaPreferencesWindowController storedFrequencyAdjustmentMode]];
    [notifications postNotificationName:@"MetasequoiaInputModeShortcutDidChangeNotification"
                                 object:@([MetasequoiaPreferencesWindowController storedInputModeShortcutEnabled])];
    [notifications postNotificationName:@"MetasequoiaInputModeHUDDidChangeNotification"
                                 object:@([MetasequoiaPreferencesWindowController storedInputModeHUDEnabled])];
    [notifications postNotificationName:@"MetasequoiaWubiMixedPinyinDidChangeNotification"
                                 object:@([MetasequoiaPreferencesWindowController storedWubiMixedPinyinEnabled])];
    [notifications postNotificationName:@"MetasequoiaWubiAutoCommitUniqueDidChangeNotification"
                                 object:@([MetasequoiaPreferencesWindowController storedWubiAutoCommitUniqueEnabled])];
    [notifications postNotificationName:@"MetasequoiaWubiCodeHintDidChangeNotification"
                                 object:@([MetasequoiaPreferencesWindowController storedWubiCodeHintEnabled])];
    [notifications postNotificationName:@"MetasequoiaShuangpinKeymapDidChangeNotification"
                                 object:@([MetasequoiaPreferencesWindowController storedShuangpinKeymapEnabled])];
    [notifications postNotificationName:@"MetasequoiaFullWidthInputDidChangeNotification"
                                 object:@([MetasequoiaPreferencesWindowController storedFullWidthInputEnabled])];
    [notifications postNotificationName:MetasequoiaFloatingToolbarDidChangeNotification
                                 object:@([MetasequoiaPreferencesWindowController storedFloatingToolbarEnabled])];
    [notifications
        postNotificationName:MetasequoiaTraditionalChineseOutputDidChangeNotification
                      object:@([MetasequoiaPreferencesWindowController storedTraditionalChineseOutputEnabled])];
    [self refreshControls];
}

- (void)close:(id)sender
{
    [self.window performClose:sender];
}

@end
