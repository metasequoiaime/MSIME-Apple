extern "C" void MSIMEShowBackendAccount(void);

#import "PreferencesWindowController.h"

#include "CandidateFontSize.h"
#include "CandidatePageSize.h"
#include "CandidatePanelStyle.h"
#include "CandidateSkin.h"
#include "HelpcodeSchemaPreference.h"
#include "InputControllerKeyRouting.h"
#include "InputSchemePreference.h"
#import "CandidateSkinAppearance.h"
#import "CandidateSkinPreviewView.h"
#import "DictionaryInstaller.h"
#import "SkinSettingsView.h"
#import "UpdateController.h"

#include <cstring>

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
constexpr CGFloat kWindowWidth = 680.0;
constexpr CGFloat kWindowHeight = 800.0;
NSToolbarIdentifier const kPreferencesToolbarIdentifier = @"MetasequoiaPreferencesToolbar";
NSToolbarItemIdentifier const kKeyboardToolbarItemIdentifier = @"MetasequoiaPreferencesKeyboard";
NSToolbarItemIdentifier const kAppearanceToolbarItemIdentifier = @"MetasequoiaPreferencesAppearance";
NSToolbarItemIdentifier const kSkinToolbarItemIdentifier = @"MetasequoiaPreferencesSkin";
NSToolbarItemIdentifier const kDataToolbarItemIdentifier = @"MetasequoiaPreferencesData";
NSToolbarItemIdentifier const kUpdatesToolbarItemIdentifier = @"MetasequoiaPreferencesUpdates";
NSString *const kSchemePreferenceKey = @"MetasequoiaImeInputScheme";
NSString *const kAutocorrectPreferenceKey = @"MetasequoiaImeQuanpinAutocorrect";
NSString *const kHelpcodePreferenceKey = @"MetasequoiaImeHelpcodeEnabled";
NSString *const kQuanpinHelpcodeSchemaPreferenceKey = @"MetasequoiaImeQuanpinHelpcodeSchema";
NSString *const kShuangpinHelpcodeSchemaPreferenceKey = @"MetasequoiaImeShuangpinHelpcodeSchema";
NSString *const kChinesePunctuationPreferenceKey = @"MetasequoiaImeChinesePunctuation";
NSString *const kCandidatePanelStylePreferenceKey = @"MetasequoiaImeCandidatePanelStyle";
NSString *const kCandidatePageSizePreferenceKey = @"MetasequoiaImeCandidatePageSize";
NSString *const kCandidateFontSizePreferenceKey = @"MetasequoiaImeCandidateFontSize";
NSString *const kCandidatePageShortcutPreferenceKey = @"MetasequoiaImeCandidatePageShortcut";
NSString *const kCandidateLearningPreferenceKey = @"MetasequoiaImeCandidateLearning";
NSString *const kEnglishInputModePreferenceKey = @"MetasequoiaImeEnglishInputMode";
NSString *const kInputModeShortcutPreferenceKey = @"MetasequoiaImeInputModeShortcutEnabled";
NSString *const kFullWidthInputPreferenceKey = @"MetasequoiaImeFullWidthInputEnabled";
NSString *const kFloatingToolbarPreferenceKey = @"MetasequoiaImeFloatingToolbarEnabled";
NSString *const kTraditionalChineseOutputPreferenceKey = @"MetasequoiaImeTraditionalChineseOutput";
NSString *const kWubiAutoCommitUniquePreferenceKey = @"MetasequoiaImeWubiAutoCommitUnique";
NSString *const kShuangpinKeymapPreferenceKey = @"MetasequoiaImeShuangpinKeymapEnabled";
NSString *const kLocalInputModesPreferenceKey = @"MetasequoiaImeLocalInputModesEnabled";

void ConfigureCard(NSBox *card)
{
    card.boxType = NSBoxCustom;
    card.titlePosition = NSNoTitle;
    card.borderWidth = 1.0;
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
    label.font = [NSFont systemFontOfSize:13.0 weight:NSFontWeightMedium];
    label.translatesAutoresizingMaskIntoConstraints = NO;
    control.translatesAutoresizingMaskIntoConstraints = NO;
    [row addSubview:label];
    [row addSubview:control];
    [NSLayoutConstraint activateConstraints:@[
        [row.heightAnchor constraintEqualToConstant:34.0],
        [label.leadingAnchor constraintEqualToAnchor:row.leadingAnchor],
        [label.centerYAnchor constraintEqualToAnchor:row.centerYAnchor],
        [label.trailingAnchor constraintLessThanOrEqualToAnchor:control.leadingAnchor constant:-12.0],
        [control.trailingAnchor constraintEqualToAnchor:row.trailingAnchor],
        [control.centerYAnchor constraintEqualToAnchor:row.centerYAnchor],
        [control.widthAnchor constraintEqualToConstant:188.0],
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
    NSView *page = [[NSView alloc] initWithFrame:NSZeroRect];
    page.translatesAutoresizingMaskIntoConstraints = NO;
    NSTextField *titleLabel = [NSTextField labelWithString:title];
    titleLabel.font = [NSFont systemFontOfSize:24.0 weight:NSFontWeightSemibold];
    NSTextField *descriptionLabel = [NSTextField labelWithString:summary];
    descriptionLabel.textColor = [NSColor secondaryLabelColor];
    descriptionLabel.maximumNumberOfLines = 2;
    NSStackView *stack = [NSStackView stackViewWithViews:@[ titleLabel, descriptionLabel ]];
    stack.orientation = NSUserInterfaceLayoutOrientationVertical;
    stack.alignment = NSLayoutAttributeLeading;
    stack.distribution = NSStackViewDistributionFill;
    stack.spacing = 7.0;
    for (NSView *view in content)
    {
        [stack addArrangedSubview:view];
        [view.widthAnchor constraintEqualToAnchor:stack.widthAnchor].active = YES;
    }
    [stack setCustomSpacing:22.0 afterView:descriptionLabel];
    stack.translatesAutoresizingMaskIntoConstraints = NO;
    [page addSubview:stack];
    [NSLayoutConstraint activateConstraints:@[
        [stack.leadingAnchor constraintEqualToAnchor:page.leadingAnchor constant:30.0],
        [stack.trailingAnchor constraintEqualToAnchor:page.trailingAnchor constant:-30.0],
        [stack.topAnchor constraintEqualToAnchor:page.topAnchor constant:28.0],
    ]];
    return page;
}
} // namespace

@interface MetasequoiaPreferencesWindowController () <NSToolbarDelegate>
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
    NSButton *_localInputModesButton;
    NSPopUpButton *_quanpinHelpcodeSchemaButton;
    NSPopUpButton *_shuangpinHelpcodeSchemaButton;
    NSButton *_chinesePunctuationButton;
    NSPopUpButton *_candidatePanelStyleButton;
    NSPopUpButton *_candidatePageSizeButton;
    NSPopUpButton *_candidateFontSizeButton;
    NSPopUpButton *_candidatePageShortcutButton;
    MetasequoiaCandidatePreviewView *_candidatePreview;
    MetasequoiaSkinSettingsView *_skinSettings;
    NSButton *_candidateLearningButton;
    NSButton *_inputModeShortcutButton;
    NSButton *_fullWidthInputButton;
    NSButton *_floatingToolbarButton;
    NSButton *_wubiAutoCommitButton;
    NSButton *_resetLearningButton;
    NSTextField *_statusLabel;
    NSTextField *_versionLabel;
    NSTextField *_automaticUpdateLabel;
    NSButton *_updatePageButton;
    NSArray<NSView *> *_preferencePages;
    NSArray<NSToolbarItemIdentifier> *_preferenceToolbarItemIdentifiers;
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
        @"platform.macos.candidate_page_size" : @([self storedCandidatePageSize]),
        @"platform.macos.candidate_font_size" : @([self storedCandidateFontSize]),
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
    return static_cast<NSInteger>(metasequoia::mac::NormalizeCandidatePageSize(static_cast<size_t>(value)));
}

+ (void)setCandidatePageSize:(NSInteger)pageSize
{
    const NSInteger normalizedPageSize =
        static_cast<NSInteger>(metasequoia::mac::NormalizeCandidatePageSize(static_cast<size_t>(pageSize)));
    [[NSUserDefaults standardUserDefaults] setInteger:normalizedPageSize forKey:kCandidatePageSizePreferenceKey];
    [[NSNotificationCenter defaultCenter] postNotificationName:@"MetasequoiaCandidatePageSizeDidChangeNotification"
                                                        object:@(normalizedPageSize)];
}

+ (NSInteger)storedCandidateFontSize
{
    const NSInteger value = [[NSUserDefaults standardUserDefaults] integerForKey:kCandidateFontSizePreferenceKey];
    return static_cast<NSInteger>(metasequoia::mac::NormalizeCandidateFontSize(static_cast<size_t>(value)));
}

+ (void)setCandidateFontSize:(NSInteger)fontSize
{
    const NSInteger normalizedFontSize =
        static_cast<NSInteger>(metasequoia::mac::NormalizeCandidateFontSize(static_cast<size_t>(fontSize)));
    [[NSUserDefaults standardUserDefaults] setInteger:normalizedFontSize forKey:kCandidateFontSizePreferenceKey];
    [[NSNotificationCenter defaultCenter] postNotificationName:@"MetasequoiaCandidateFontSizeDidChangeNotification"
                                                        object:@(normalizedFontSize)];
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
    NSWindow *window = [[NSWindow alloc] initWithContentRect:frame
                                                   styleMask:(NSWindowStyleMaskTitled | NSWindowStyleMaskClosable)
                                                     backing:NSBackingStoreBuffered
                                                       defer:NO];
    window.title = @"水杉输入法设置";
    window.releasedWhenClosed = NO;
    window.restorable = NO;
    window.titleVisibility = NSWindowTitleVisible;
    window.titlebarAppearsTransparent = NO;
    window.movableByWindowBackground = NO;
    window.toolbarStyle = NSWindowToolbarStylePreference;

    self = [super initWithWindow:window];
    if (self == nil)
    {
        return nil;
    }
    window.delegate = self;
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
    _preferenceToolbarItemIdentifiers = @[
        kKeyboardToolbarItemIdentifier,
        kAppearanceToolbarItemIdentifier,
        kSkinToolbarItemIdentifier,
        kDataToolbarItemIdentifier,
        kUpdatesToolbarItemIdentifier,
    ];
    NSToolbar *toolbar = [[NSToolbar alloc] initWithIdentifier:kPreferencesToolbarIdentifier];
    toolbar.delegate = self;
    toolbar.displayMode = NSToolbarDisplayModeIconAndLabel;
    toolbar.sizeMode = NSToolbarSizeModeRegular;
    toolbar.allowsUserCustomization = NO;
    toolbar.autosavesConfiguration = NO;
    window.toolbar = toolbar;

    NSView *contentView = [[NSView alloc] initWithFrame:frame];
    window.contentView = contentView;

    NSView *settingsPanel = [[NSView alloc] initWithFrame:NSZeroRect];
    settingsPanel.translatesAutoresizingMaskIntoConstraints = NO;
    NSView *pageContainer = [[NSView alloc] initWithFrame:NSZeroRect];
    pageContainer.translatesAutoresizingMaskIntoConstraints = NO;

    NSArray<NSString *> *schemeTitles = @[ @"全拼输入", @"双拼输入", @"五笔输入" ];
    NSMutableArray<NSButton *> *schemeButtons = [NSMutableArray arrayWithCapacity:schemeTitles.count];
    NSMutableArray<NSView *> *schemeRows = [NSMutableArray arrayWithObject:CardHeader(@"输入方式")];
    [schemeRows addObject:CardSeparator()];
    _shuangpinSchemeButton = [[NSPopUpButton alloc] initWithFrame:NSZeroRect pullsDown:NO];
    [_shuangpinSchemeButton addItemWithTitle:@"小鹤双拼"];
    _shuangpinSchemeButton.accessibilityLabel = @"双拼方案";
    _wubiSchemeButton = [[NSPopUpButton alloc] initWithFrame:NSZeroRect pullsDown:NO];
    [_wubiSchemeButton addItemWithTitle:@"86 五笔"];
    _wubiSchemeButton.accessibilityLabel = @"五笔方案";
    _shuangpinKeymapButton = [NSButton checkboxWithTitle:@"显示小鹤双拼键位提示"
                                                  target:self
                                                  action:@selector(shuangpinKeymapChanged:)];
    _shuangpinKeymapButton.accessibilityLabel = @"显示小鹤双拼键位提示";
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
    _inputModeShortcutButton = [NSButton checkboxWithTitle:@"Shift+Space 切换中英文"
                                                    target:self
                                                    action:@selector(inputModeShortcutChanged:)];
    _inputModeShortcutButton.accessibilityLabel = @"Shift+Space 切换中英文";
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
    NSBox *behaviorCard = CardWithViews(
        @[ _autocorrectButton, _chinesePunctuationButton, _inputModeShortcutButton, _fullWidthInputButton ], 9.0);
    NSBox *shortcutCard = CardWithViews(@[ PreferenceRow(@"上翻 / 下翻", _candidatePageShortcutButton) ], 0.0);
    schemeCard.accessibilityLabel = @"输入方式卡片";
    behaviorCard.accessibilityLabel = @"中英文状态切换卡片";
    shortcutCard.accessibilityLabel = @"候选翻页快捷键卡片";
    NSView *generalPage = PreferencesPage(
        @"键盘输入", @"选择全拼、双拼或 86 五笔，并调整日常输入行为。",
        @[ schemeCard, SectionLabel(@"中英文状态切换"), behaviorCard, SectionLabel(@"候选翻页快捷键"), shortcutCard ]);
    generalPage.accessibilityLabel = @"键盘输入设置页";

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
    NSTextField *wubiSchemeLabel = [NSTextField labelWithString:@"86 五笔"];
    wubiSchemeLabel.textColor = [NSColor secondaryLabelColor];
    NSBox *wubiOptionsCard =
        CardWithViews(@[ PreferenceRow(@"编码方案", wubiSchemeLabel), _wubiAutoCommitButton ], 8.0);
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
    [_candidatePageSizeButton addItemsWithTitles:@[ @"5 个", @"7 个", @"9 个" ]];
    _candidatePageSizeButton.target = self;
    _candidatePageSizeButton.action = @selector(candidatePageSizeChanged:);
    _candidatePageSizeButton.accessibilityLabel = @"每页候选";

    _candidateFontSizeButton = [[NSPopUpButton alloc] initWithFrame:NSZeroRect pullsDown:NO];
    [_candidateFontSizeButton addItemsWithTitles:@[ @"小（16 pt）", @"标准（18 pt）", @"大（20 pt）" ]];
    _candidateFontSizeButton.target = self;
    _candidateFontSizeButton.action = @selector(candidateFontSizeChanged:);
    _candidateFontSizeButton.accessibilityLabel = @"候选字号";

    _candidatePreview = [[MetasequoiaCandidatePreviewView alloc] initWithFrame:NSZeroRect];
    NSBox *appearanceCard = CardWithViews(
        @[
            PreferenceRow(@"候选排列", _candidatePanelStyleButton),
            PreferenceRow(@"每页候选", _candidatePageSizeButton),
            PreferenceRow(@"候选字号", _candidateFontSizeButton),
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
        SectionLabel(@"效果预览"), _candidatePreview, SectionLabel(@"候选窗口"), appearanceCard,
        SectionLabel(@"悬浮状态栏"), floatingToolbarCard
    ]);
    appearancePage.accessibilityLabel = @"外观设置页";

    _skinSettings = [[MetasequoiaSkinSettingsView alloc] initWithFrame:NSZeroRect];

    _helpcodeButton = [NSButton checkboxWithTitle:@"启用辅助码" target:self action:@selector(helpcodeChanged:)];
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

    NSBox *learningCard = CardWithViews(
        @[
            _helpcodeButton, PreferenceRow(@"全拼辅助码方案", _quanpinHelpcodeSchemaButton),
            PreferenceRow(@"双拼辅助码方案", _shuangpinHelpcodeSchemaButton), _candidateLearningButton,
            _localInputModesButton
        ],
        9.0);
    NSBox *dictionaryCard = CardWithViews(@[ _statusLabel ], 0.0);
    NSBox *resetCard =
        CardWithViews(@[ PreferenceRow(@"候选词频、用户词典与拼音学习记录", _resetLearningButton) ], 0.0);
    learningCard.accessibilityLabel = @"候选与学习卡片";
    resetCard.accessibilityLabel = @"数据与隐私卡片";
    NSView *dataPage = PreferencesPage(@"词库与数据", @"管理候选学习、辅助码与本机词库状态。", @[
        SectionLabel(@"候选与学习"), learningCard, SectionLabel(@"词库状态"), dictionaryCard,
        SectionLabel(@"数据与隐私"), resetCard
    ]);
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

    _preferencePages = @[ generalPage, appearancePage, _skinSettings, dataPage, updatesPage, wubiPage ];

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
        [settingsPanel.leadingAnchor constraintEqualToAnchor:contentView.leadingAnchor],
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
    [self showPreferencesPageAtIndex:0 toolbarIndex:0];
    [self refreshUpdateControls];
    return self;
}

- (NSArray<NSToolbarItemIdentifier> *)toolbarAllowedItemIdentifiers:(NSToolbar *)toolbar
{
    (void)toolbar;
    return _preferenceToolbarItemIdentifiers;
}

- (NSArray<NSToolbarItemIdentifier> *)toolbarDefaultItemIdentifiers:(NSToolbar *)toolbar
{
    (void)toolbar;
    return _preferenceToolbarItemIdentifiers;
}

- (NSArray<NSToolbarItemIdentifier> *)toolbarSelectableItemIdentifiers:(NSToolbar *)toolbar
{
    (void)toolbar;
    return _preferenceToolbarItemIdentifiers;
}

- (NSToolbarItem *)toolbar:(NSToolbar *)toolbar
        itemForItemIdentifier:(NSToolbarItemIdentifier)itemIdentifier
    willBeInsertedIntoToolbar:(BOOL)flag
{
    (void)toolbar;
    (void)flag;
    const NSInteger index = [_preferenceToolbarItemIdentifiers indexOfObject:itemIdentifier];
    if (index == NSNotFound)
    {
        return nil;
    }
    NSArray<NSString *> *labels = @[ @"键盘输入", @"外观", @"皮肤", @"词库与数据", @"更新与反馈" ];
    NSArray<NSString *> *symbols =
        @[ @"keyboard", @"paintpalette", @"paintbrush", @"books.vertical", @"arrow.triangle.2.circlepath" ];
    NSToolbarItem *item = [[NSToolbarItem alloc] initWithItemIdentifier:itemIdentifier];
    item.label = labels[index];
    item.paletteLabel = labels[index];
    item.toolTip = labels[index];
    item.image = [NSImage imageWithSystemSymbolName:symbols[index] accessibilityDescription:labels[index]];
    item.target = self;
    item.action = @selector(selectPreferencesPageFromToolbar:);
    item.tag = index;
    return item;
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

- (void)selectPreferencesPageFromToolbar:(id)sender
{
    NSToolbarItem *selectedItem = [sender isKindOfClass:[NSToolbarItem class]] ? (NSToolbarItem *)sender : nil;
    const NSInteger selectedIndex = selectedItem == nil ? 0 : selectedItem.tag;
    [self showPreferencesPageAtIndex:selectedIndex toolbarIndex:selectedIndex];
}

- (void)showPreferencesPageAtIndex:(NSInteger)pageIndex toolbarIndex:(NSInteger)toolbarIndex
{
    for (NSInteger index = 0; index < static_cast<NSInteger>(_preferencePages.count); ++index)
    {
        const BOOL selected = index == pageIndex;
        _preferencePages[index].hidden = !selected;
    }
    if (toolbarIndex >= 0 && toolbarIndex < static_cast<NSInteger>(_preferenceToolbarItemIdentifiers.count))
    {
        self.window.toolbar.selectedItemIdentifier = _preferenceToolbarItemIdentifiers[toolbarIndex];
    }
}

- (void)showWubiSettings:(id)sender
{
    (void)sender;
    [self refreshControls];
    [self showPreferencesPageAtIndex:5 toolbarIndex:0];
}

- (void)backToKeyboardInput:(id)sender
{
    (void)sender;
    [self showPreferencesPageAtIndex:0 toolbarIndex:0];
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
    const NSInteger storedScheme = [MetasequoiaPreferencesWindowController storedScheme];
    for (NSInteger index = 0; index < static_cast<NSInteger>(_schemeButtons.count); ++index)
    {
        _schemeButtons[index].state = index == storedScheme ? NSControlStateValueOn : NSControlStateValueOff;
    }
    _shuangpinSchemeButton.enabled = storedScheme == 1;
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
    _helpcodeButton.state =
        [MetasequoiaPreferencesWindowController storedHelpcodeEnabled] ? NSControlStateValueOn : NSControlStateValueOff;
    _localInputModesButton.state = [MetasequoiaPreferencesWindowController storedLocalInputModesEnabled]
                                       ? NSControlStateValueOn
                                       : NSControlStateValueOff;
    [_quanpinHelpcodeSchemaButton
        selectItemAtIndex:[MetasequoiaPreferencesWindowController storedQuanpinHelpcodeSchema]];
    [_shuangpinHelpcodeSchemaButton
        selectItemAtIndex:[MetasequoiaPreferencesWindowController storedShuangpinHelpcodeSchema]];
    _quanpinHelpcodeSchemaButton.enabled = _helpcodeButton.state == NSControlStateValueOn;
    _shuangpinHelpcodeSchemaButton.enabled = _helpcodeButton.state == NSControlStateValueOn;
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
    [self refreshSkinControl];
    [_candidatePreview updatePanelStyle:[MetasequoiaPreferencesWindowController storedCandidatePanelStyle]
                               pageSize:[MetasequoiaPreferencesWindowController storedCandidatePageSize]
                               fontSize:[MetasequoiaPreferencesWindowController storedCandidateFontSize]];
    _candidateLearningButton.state = [MetasequoiaPreferencesWindowController storedCandidateLearningEnabled]
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
    _wubiAutoCommitButton.state = [MetasequoiaPreferencesWindowController storedWubiAutoCommitUniqueEnabled]
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

- (void)candidatePanelStyleChanged:(id)sender
{
    NSPopUpButton *styleButton = (NSPopUpButton *)sender;
    [MetasequoiaPreferencesWindowController setCandidatePanelStyle:styleButton.indexOfSelectedItem];
    [_candidatePreview updatePanelStyle:[MetasequoiaPreferencesWindowController storedCandidatePanelStyle]
                               pageSize:[MetasequoiaPreferencesWindowController storedCandidatePageSize]
                               fontSize:[MetasequoiaPreferencesWindowController storedCandidateFontSize]];
}

- (void)candidatePageSizeChanged:(id)sender
{
    NSPopUpButton *pageSizeButton = (NSPopUpButton *)sender;
    const size_t pageSize =
        metasequoia::mac::CandidatePageSizeForOptionIndex(static_cast<size_t>(pageSizeButton.indexOfSelectedItem));
    [MetasequoiaPreferencesWindowController setCandidatePageSize:static_cast<NSInteger>(pageSize)];
    [_candidatePreview updatePanelStyle:[MetasequoiaPreferencesWindowController storedCandidatePanelStyle]
                               pageSize:[MetasequoiaPreferencesWindowController storedCandidatePageSize]
                               fontSize:[MetasequoiaPreferencesWindowController storedCandidateFontSize]];
}

- (void)candidateFontSizeChanged:(id)sender
{
    NSPopUpButton *fontSizeButton = (NSPopUpButton *)sender;
    const size_t fontSize =
        metasequoia::mac::CandidateFontSizeForOptionIndex(static_cast<size_t>(fontSizeButton.indexOfSelectedItem));
    [MetasequoiaPreferencesWindowController setCandidateFontSize:static_cast<NSInteger>(fontSize)];
    [_candidatePreview updatePanelStyle:[MetasequoiaPreferencesWindowController storedCandidatePanelStyle]
                               pageSize:[MetasequoiaPreferencesWindowController storedCandidatePageSize]
                               fontSize:[MetasequoiaPreferencesWindowController storedCandidateFontSize]];
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
}

- (void)candidatePageShortcutChanged:(id)sender
{
    NSPopUpButton *shortcutButton = (NSPopUpButton *)sender;
    [MetasequoiaPreferencesWindowController setCandidatePageShortcut:shortcutButton.indexOfSelectedItem];
}

- (void)inputModeShortcutChanged:(id)sender
{
    NSButton *button = (NSButton *)sender;
    [MetasequoiaPreferencesWindowController setInputModeShortcutEnabled:button.state == NSControlStateValueOn];
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
             kAutocorrectPreferenceKey,
             kHelpcodePreferenceKey,
             kQuanpinHelpcodeSchemaPreferenceKey,
             kShuangpinHelpcodeSchemaPreferenceKey,
             kChinesePunctuationPreferenceKey,
             kCandidatePanelStylePreferenceKey,
             @"MetasequoiaImeCandidateSkin",
             kCandidatePageSizePreferenceKey,
             kCandidateFontSizePreferenceKey,
             kCandidatePageShortcutPreferenceKey,
             kCandidateLearningPreferenceKey,
             kInputModeShortcutPreferenceKey,
             kWubiAutoCommitUniquePreferenceKey,
             kShuangpinKeymapPreferenceKey,
             kLocalInputModesPreferenceKey,
             kFullWidthInputPreferenceKey,
             kFloatingToolbarPreferenceKey,
             kTraditionalChineseOutputPreferenceKey,
         ])
    {
        [defaults removeObjectForKey:key];
    }

    NSNotificationCenter *notifications = [NSNotificationCenter defaultCenter];
    [notifications postNotificationName:@"MetasequoiaInputSchemeDidChangeNotification"
                                 object:@([MetasequoiaPreferencesWindowController storedScheme])];
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
    [notifications postNotificationName:@"MetasequoiaCandidatePageShortcutDidChangeNotification"
                                 object:@([MetasequoiaPreferencesWindowController storedCandidatePageShortcut])];
    [notifications postNotificationName:@"MetasequoiaCandidateLearningDidChangeNotification"
                                 object:@([MetasequoiaPreferencesWindowController storedCandidateLearningEnabled])];
    [notifications postNotificationName:@"MetasequoiaInputModeShortcutDidChangeNotification"
                                 object:@([MetasequoiaPreferencesWindowController storedInputModeShortcutEnabled])];
    [notifications postNotificationName:@"MetasequoiaWubiAutoCommitUniqueDidChangeNotification"
                                 object:@([MetasequoiaPreferencesWindowController storedWubiAutoCommitUniqueEnabled])];
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
