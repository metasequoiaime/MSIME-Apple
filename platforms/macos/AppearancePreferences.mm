#import "AppearancePreferences.h"
#import "CandidateSkinPreviewView.h"
#import "SkinSettingsView.h"
#import "CloudAppearanceSettings.h"
#include "ShuangpinProfileNames.h"

NSNotificationName const MSIMEAppearanceDidChangeNotification = @"MSIMEClientAppearanceDidChange";
static NSString *const LayoutKey = @"MSIMEClientCandidatePanelStyle";
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
static NSString *const FontKey = @"MSIMEClientCandidateFontSize";
static NSString *const FontFamilyKey = @"MSIMEClientCandidateFontFamily";
static NSString *const TextColorKey = @"MSIMEClientCandidateTextColor";
static BOOL ValidTextColor(id value) {
    if (![value isKindOfClass:NSString.class] || [value length] != 7 || ![value hasPrefix:@"#"]) return NO;
    return [[value substringFromIndex:1] rangeOfCharacterFromSet:[[NSCharacterSet characterSetWithCharactersInString:@"0123456789abcdefABCDEF"] invertedSet]].location == NSNotFound;
}
static NSString *const FallbackFontsKey = @"MSIMEClientCandidateFallbackFonts";
static BOOL ValidFontFamily(id value) {
    return [value isKindOfClass:NSString.class] && [value length] > 0 &&
           [value lengthOfBytesUsingEncoding:NSUTF8StringEncoding] <= 128;
}
static BOOL ValidFallbackFonts(id value) {
    if (![value isKindOfClass:NSArray.class] || [value count] > 32) return NO;
    for (id family in value) if (!ValidFontFamily(family)) return NO;
    return YES;
}
static NSString *const PreeditFontKey = @"MSIMEClientCandidatePreeditFontSize";
static NSString *const CandidatePreeditKey = @"MSIMEClientCandidatePreeditStyle";
static NSString *const PageShortcutKey = @"MSIMEClientCandidatePageShortcut";
static NSString *const PageSizeKey = @"MSIMEClientCandidatePageSize";
static NSString *const SkinKey = @"MSIMEClientCandidateSkin";
static NSString *const EnglishKey = @"MSIMEClientEnglishInputMode";
static NSString *const TraditionalKey = @"MSIMEClientTraditionalOutput";
static NSString *const FullWidthKey = @"MSIMEClientFullWidthInput";
static NSString *const ChinesePunctuationKey = @"MSIMEClientChinesePunctuation";
static NSString *const AutocorrectKey = @"MSIMEClientAutocorrect";
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
static NSString *const FloatingToolbarKey = @"MSIMEClientFloatingToolbarEnabled";

@implementation MSIMEAppearancePreferences {
    NSUserDefaults *_defaults;
    NSNumber *_sharedToolbarEnabled;
    NSMutableDictionary *_sharedHelpcodeOptions;
    NSMutableDictionary<NSString *, NSPopUpButton *> *_helpcodeSchemaButtons;
    NSMutableDictionary<NSString *, NSButton *> *_helpcodeDisplayButtons;
    NSNumber *_sharedChinesePunctuation;
    NSNumber *_sharedAutocorrect;
    id _sharedTransposition;
    id _sharedNeighbor;
    NSNumber *_sharedQuanpinHelpcode;
    NSNumber *_sharedShuangpinHelpcode;
    NSNumber *_sharedVertical;
    NSNumber *_sharedFontSize;
    NSString *_sharedFontFamily;
    NSArray<NSString *> *_sharedFallbackFonts;
    id _sharedTextColor;
    NSTextField *_textColorField;
    NSColorWell *_textColorWell;
    NSNumber *_sharedPreeditFontSize;
    NSString *_sharedCandidatePreedit;
    NSNumber *_sharedPageSize;
    NSString *_sharedInputScheme;
    NSString *_sharedShuangpinProfile;
    NSNumber *_sharedShuangpinPreeditUsesRaw;
    NSMutableDictionary *_sharedLocalModes;
    NSMutableArray<NSButton *> *_localModeButtons;
    NSPopUpButton *_layoutButton;
    NSPopUpButton *_schemeButton;
    NSPopUpButton *_profileButton;
    NSPopUpButton *_preeditButton;
    NSPopUpButton *_fontButton;
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
    NSButton *_inputModeShortcutButton;
    NSButton *_fullWidthButton;
    NSButton *_keymapButton;
    NSButton *_wubiButton;
    NSButton *_punctuationButton;
    NSButton *_toolbarButton;
    NSButton *_transpositionButton;
    NSButton *_neighborButton;
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
- (NSDictionary<NSString *, id> *)sharedPreferencesByMerging:(NSDictionary<NSString *, id> *)snapshot {
    if (![snapshot isKindOfClass:NSDictionary.class]) return nil;
    NSMutableDictionary *merged = [snapshot mutableCopy];
    merged[@"candidate_layout"] = self.vertical ? @"vertical" : @"horizontal";
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
    merged[@"candidate_font_size"] = @(self.fontSize);
    if (_sharedFontFamily || [_defaults objectForKey:FontFamilyKey]) merged[@"candidate_font_family"] = self.fontFamily;
    if (_sharedTextColor || [_defaults objectForKey:TextColorKey]) merged[@"candidate_text_color"] = self.candidateTextColor ?: (id)NSNull.null;
    if (_sharedFallbackFonts || [_defaults objectForKey:FallbackFontsKey]) merged[@"candidate_fallback_fonts"] = self.fallbackFonts;
    if (_sharedPreeditFontSize || [_defaults objectForKey:PreeditFontKey]) merged[@"candidate_preedit_font_size"] = @(self.preeditFontSize);
    if (_sharedCandidatePreedit || [_defaults objectForKey:CandidatePreeditKey]) merged[@"candidate_preedit_style"] = self.showsCandidatePreedit ? @"pinyin" : @"empty";
    merged[@"chinese_punctuation"] = @(self.chinesePunctuation);
    merged[@"autocorrect"] = @(self.autocorrect);
    NSMutableDictionary *quanpin = [merged[@"quanpin"] mutableCopy] ?: [NSMutableDictionary dictionary];
    if (LocalModeBoolean([_defaults objectForKey:TranspositionKey]))
        quanpin[@"autocorrect_transposition"] = _sharedTransposition ?: @(self.autocorrectTransposition);
    if (LocalModeBoolean([_defaults objectForKey:NeighborKey]))
        quanpin[@"autocorrect_neighbor"] = _sharedNeighbor ?: @(self.autocorrectNeighbor);
    if (quanpin.count) merged[@"quanpin"] = quanpin;
    NSMutableDictionary *voice = [merged[@"voice_input"] mutableCopy] ?: [NSMutableDictionary dictionary];
    NSString *language = [[NSUserDefaults standardUserDefaults] stringForKey:@"MSIMEClientVoiceLanguage"];
    if ([language isEqualToString:@"zh-CN"] || [language isEqualToString:@"en-US"]) voice[@"language"] = language;
    merged[@"voice_input"] = voice;
    NSMutableDictionary *toolbar = [merged[@"floating_toolbar"] mutableCopy];
    if (!toolbar) toolbar = [NSMutableDictionary dictionary];
    toolbar[@"enabled"] = @(self.floatingToolbarEnabled);
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
    if (!MSIMEApplyCloudAppearance(values, _defaults)) return NO;
    // Invalidate only fields represented by the legacy platform cloud snapshot.
    // Newer family, color, preedit-size and per-scheme assistance choices survive.
    _sharedFontSize = nil;
    _sharedPageSize = nil;
    _sharedVertical = nil;
    _sharedInputScheme = nil;
    _sharedShuangpinPreeditUsesRaw = nil;
    _sharedChinesePunctuation = nil;
    _sharedAutocorrect = nil;
    _sharedToolbarEnabled = nil;
    [self reloadSkins]; // Resolve the imported skin and publish one complete update.
    return YES;
}
- (void)resolveSelectedSkin {
    const std::filesystem::path root = _skinsRoot.fileSystemRepresentation ?: "";
    _lightSkin = msime::mac::ResolveSkin(self.skinID.UTF8String, false, root);
    _darkSkin = msime::mac::ResolveSkin(self.skinID.UTF8String, true, root);
    _decorationImage = nil;
    if (_lightSkin.decorationTopDip > 0 && !_lightSkin.decorationPath.empty()) {
        _decorationImage = [[NSImage alloc] initWithContentsOfFile:@(_lightSkin.decorationPath.c_str())];
    }
}
- (BOOL)vertical { return _sharedVertical ? _sharedVertical.boolValue : [_defaults integerForKey:LayoutKey] == 1; }
- (BOOL)autocorrect { if (_sharedAutocorrect) return _sharedAutocorrect.boolValue; return [_defaults objectForKey:AutocorrectKey] == nil ? YES : [_defaults boolForKey:AutocorrectKey]; }
- (void)setAutocorrect:(BOOL)value { _sharedAutocorrect = nil; [_defaults setBool:value forKey:AutocorrectKey]; [self preferencesChanged]; }
- (BOOL)autocorrectTransposition { id value = _sharedTransposition ?: [_defaults objectForKey:TranspositionKey]; return LocalModeBoolean(value) ? [value boolValue] : self.autocorrect; }
- (BOOL)autocorrectNeighbor { id value = _sharedNeighbor ?: [_defaults objectForKey:NeighborKey]; return LocalModeBoolean(value) ? [value boolValue] : self.autocorrect; }
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
    id quanpin = preferences[@"quanpin_helpcode"];
    id shuangpin = preferences[@"shuangpin_helpcode"];
    if (LocalModeBoolean(autocorrect)) _sharedAutocorrect = autocorrect;
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
    NSMutableDictionary *values = [@{@"schema": @"ziranma", @"show_in_candidate_window": @YES} mutableCopy];
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
- (NSString *)inputScheme { NSString *value = _sharedInputScheme ?: [_defaults stringForKey:SchemeKey]; return [@[@"quanpin", @"shuangpin", @"wubi"] containsObject:value] ? value : @"quanpin"; }
- (void)setInputScheme:(NSString *)value { if (![@[@"quanpin", @"shuangpin", @"wubi"] containsObject:value]) value = @"quanpin"; _sharedInputScheme = nil; [_defaults setObject:value forKey:SchemeKey]; [self preferencesChanged]; }
- (NSString *)shuangpinProfile { NSString *value = _sharedShuangpinProfile ?: [_defaults stringForKey:ShuangpinProfileKey]; return [@[@"xiaohe", @"ziranma", @"shoudao", @"microsoft"] containsObject:value] ? value : @"xiaohe"; }
- (void)setShuangpinProfile:(NSString *)value { if (![@[@"xiaohe", @"ziranma", @"shoudao", @"microsoft"] containsObject:value]) value = @"xiaohe"; _sharedShuangpinProfile = nil; [_defaults setObject:value forKey:ShuangpinProfileKey]; [self preferencesChanged]; }
- (BOOL)shuangpinPreeditUsesRaw { if (_sharedShuangpinPreeditUsesRaw) return _sharedShuangpinPreeditUsesRaw.boolValue; return [_defaults objectForKey:ShuangpinPreeditKey] == nil ? YES : [_defaults boolForKey:ShuangpinPreeditKey]; }
- (void)setShuangpinPreeditUsesRaw:(BOOL)value { _sharedShuangpinPreeditUsesRaw = nil; [_defaults setBool:value forKey:ShuangpinPreeditKey]; [self preferencesChanged]; }
- (void)applySharedInputPreferences:(NSDictionary *)preferences {
    if (![preferences isKindOfClass:NSDictionary.class]) return;
    id punctuation = preferences[@"chinese_punctuation"];
    if (LocalModeBoolean(punctuation)) _sharedChinesePunctuation = punctuation;
    id scheme = preferences[@"scheme"];
    id profile = preferences[@"shuangpin_profile"];
    id raw = preferences[@"shuangpin_preedit_uses_raw"];
    if ([@[@"quanpin", @"shuangpin", @"wubi"] containsObject:scheme]) _sharedInputScheme = [scheme copy];
    if ([@[@"xiaohe", @"ziranma", @"shoudao", @"microsoft"] containsObject:profile]) _sharedShuangpinProfile = [profile copy];
    if (LocalModeBoolean(raw)) _sharedShuangpinPreeditUsesRaw = raw;
    [self refreshControls];
}
- (BOOL)englishMode { return [_defaults boolForKey:EnglishKey]; }
- (BOOL)traditionalOutput { return [_defaults boolForKey:TraditionalKey]; }
- (BOOL)fullWidthInput { return [_defaults boolForKey:FullWidthKey]; }
- (BOOL)chinesePunctuation { if (_sharedChinesePunctuation) return _sharedChinesePunctuation.boolValue; return [_defaults objectForKey:ChinesePunctuationKey] == nil ? YES : [_defaults boolForKey:ChinesePunctuationKey]; }
- (BOOL)shuangpinKeymap { return [_defaults boolForKey:KeymapKey]; }
- (BOOL)wubiAutoCommitUnique { return [_defaults boolForKey:WubiKey]; }
- (BOOL)floatingToolbarEnabled { return _sharedToolbarEnabled ? _sharedToolbarEnabled.boolValue : ([_defaults objectForKey:FloatingToolbarKey] == nil ? YES : [_defaults boolForKey:FloatingToolbarKey]); }
- (void)setFloatingToolbarEnabled:(BOOL)value { _sharedToolbarEnabled = nil; [_defaults setBool:value forKey:FloatingToolbarKey]; [self preferencesChanged]; }
- (void)applySharedToolbarVisibility:(BOOL)enabled { _sharedToolbarEnabled = @(enabled); [self refreshControls]; }
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
- (void)setTraditionalOutput:(BOOL)value {
    [_defaults setBool:value forKey:TraditionalKey];
    [self preferencesChanged];
}
- (void)setEnglishMode:(BOOL)value {
    [_defaults setBool:value forKey:EnglishKey];
    [self preferencesChanged];
}
- (BOOL)inputModeShortcut {
    return [_defaults objectForKey:InputModeShortcutKey] == nil || [_defaults boolForKey:InputModeShortcutKey];
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
    NSString *value = self.candidateTextColor;
    if (!value) return color;
    unsigned int rgb = 0;
    [[NSScanner scannerWithString:[value substringFromIndex:1]] scanHexInt:&rgb];
    return [NSColor colorWithSRGBRed:((rgb >> 16) & 255) / 255.0 green:((rgb >> 8) & 255) / 255.0 blue:(rgb & 255) / 255.0 alpha:1];
}
- (void)setFontFamily:(NSString *)value {
    if (!ValidFontFamily(value)) { [self refreshControls]; return; }
    _sharedFontFamily = nil;
    [_defaults setObject:[value copy] forKey:FontFamilyKey];
    [self preferencesChanged];
}
- (NSFont *)candidateFontOfSize:(CGFloat)size {
    // Resolve a family without silently substituting a different installed family.
    // Preserve unavailable cross-platform names in preferences. Resolve installed
    // supplementary families in order, retaining system fallback at the end.
    NSMutableArray<NSFontDescriptor *> *resolved = [NSMutableArray array];
    for (NSString *family in [@[self.fontFamily] arrayByAddingObjectsFromArray:self.fallbackFonts]) {
        NSFontDescriptor *requested = [NSFontDescriptor fontDescriptorWithFontAttributes:@{NSFontFamilyAttribute:family}];
        NSFontDescriptor *matched = [requested matchingFontDescriptorWithMandatoryKeys:[NSSet setWithObject:NSFontFamilyAttribute]];
        if (matched) [resolved addObject:matched];
    }
    NSFont *system = [NSFont systemFontOfSize:size];
    if (!resolved.count) return system;
    NSFontDescriptor *primary = resolved.firstObject;
    [resolved removeObjectAtIndex:0];
    if (self.fallbackFonts.count) {
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
    return value >= 1 && value <= 9 ? value : 9;
}
- (void)setPageSize:(NSUInteger)value {
    _sharedPageSize = nil;
    [_defaults setInteger:value >= 1 && value <= 9 ? value : 9 forKey:PageSizeKey];
    [self preferencesChanged];
}
- (void)applySharedCandidatePreferences:(NSDictionary *)preferences {
    if (![preferences isKindOfClass:NSDictionary.class]) return;
    id layout = preferences[@"candidate_layout"];
    if ([@[@"horizontal", @"vertical"] containsObject:layout]) _sharedVertical = @([layout isEqual:@"vertical"]);
    id font = preferences[@"candidate_font_size"];
    id textColor = preferences[@"candidate_text_color"];
    // This optional shared field is omitted when None; omission also clears a
    // previously loaded explicit color, without persisting a local override.
    if (!textColor || textColor == NSNull.null) _sharedTextColor = NSNull.null;
    else if (ValidTextColor(textColor)) _sharedTextColor = [textColor copy];
    id family = preferences[@"candidate_font_family"];
    if (ValidFontFamily(family)) _sharedFontFamily = [family copy];
    id fallbacks = preferences[@"candidate_fallback_fonts"];
    if (ValidFallbackFonts(fallbacks)) _sharedFallbackFonts = [[NSArray alloc] initWithArray:fallbacks copyItems:YES];
    id preeditFont = preferences[@"candidate_preedit_font_size"];
    id preeditStyle = preferences[@"candidate_preedit_style"];
    if ([preeditFont isKindOfClass:NSNumber.class] && !LocalModeBoolean(preeditFont) && [preeditFont doubleValue] == [preeditFont integerValue] && [preeditFont integerValue] >= 12 && [preeditFont integerValue] <= 32) _sharedPreeditFontSize = preeditFont;
    if ([@[@"pinyin", @"empty"] containsObject:preeditStyle]) _sharedCandidatePreedit = preeditStyle;
    id page = preferences[@"candidate_page_size"];
    // Match the shared integer ranges; booleans and fractions are not sizes.
    if ([font isKindOfClass:NSNumber.class] && !LocalModeBoolean(font) && [font doubleValue] == [font integerValue] && [font integerValue] >= 12 && [font integerValue] <= 32) _sharedFontSize = font;
    if ([page isKindOfClass:NSNumber.class] && !LocalModeBoolean(page) && [page doubleValue] == [page integerValue] && [page integerValue] >= 1 && [page integerValue] <= 9) _sharedPageSize = page;
    [self refreshControls];
}
- (void)setPageShortcut:(NSInteger)value {
    [_defaults setInteger:value == 1 || value == 2 ? value : 0 forKey:PageShortcutKey];
    [self preferencesChanged];
}
- (void)refreshControls {
    for (NSString *scheme in _helpcodeSchemaButtons) {
        NSDictionary *values = [self helpcodeOptionsForScheme:scheme];
        [_helpcodeSchemaButtons[scheme] selectItemAtIndex:[HelpcodeSchemas() indexOfObject:values[@"schema"]]];
        _helpcodeDisplayButtons[scheme].state = [values[@"show_in_candidate_window"] boolValue] ? NSControlStateValueOn : NSControlStateValueOff;
    }
    _fullWidthButton.state = self.fullWidthInput ? NSControlStateValueOn : NSControlStateValueOff;
    _keymapButton.state = self.shuangpinKeymap ? NSControlStateValueOn : NSControlStateValueOff;
    _wubiButton.state = self.wubiAutoCommitUnique ? NSControlStateValueOn : NSControlStateValueOff;
    _punctuationButton.state = self.chinesePunctuation ? NSControlStateValueOn : NSControlStateValueOff;
    _toolbarButton.state = self.floatingToolbarEnabled ? NSControlStateValueOn : NSControlStateValueOff;
    _transpositionButton.state = self.autocorrectTransposition ? NSControlStateValueOn : NSControlStateValueOff;
    _neighborButton.state = self.autocorrectNeighbor ? NSControlStateValueOn : NSControlStateValueOff;
    _quanpinHelpcodeButton.state = self.quanpinHelpcodeEnabled ? NSControlStateValueOn : NSControlStateValueOff;
    _shuangpinHelpcodeButton.state = self.shuangpinHelpcodeEnabled ? NSControlStateValueOn : NSControlStateValueOff;
    for (NSButton *button in _localModeButtons)
        button.state = [self localModeEnabled:button.identifier] ? NSControlStateValueOn : NSControlStateValueOff;
    _inputModeShortcutButton.state = self.inputModeShortcut ? NSControlStateValueOn : NSControlStateValueOff;
    [_layoutButton selectItemAtIndex:self.vertical ? 1 : 0];
    NSDictionary *schemeIndexes = @{@"quanpin": @0, @"shuangpin": @1, @"wubi": @2};
    [_schemeButton selectItemAtIndex:[schemeIndexes[self.inputScheme] integerValue]];
    NSDictionary *profileIndexes = @{@"xiaohe": @0, @"ziranma": @1, @"shoudao": @2, @"microsoft": @3};
    [_profileButton selectItemAtIndex:[profileIndexes[self.shuangpinProfile] integerValue]];
    [_preeditButton selectItemAtIndex:self.shuangpinPreeditUsesRaw ? 1 : 0];
    [_fontButton selectItemAtIndex:self.fontSize - 12];
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
    [_pageSizeButton selectItemAtIndex:self.pageSize - 1];
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
    NSWindow *window = [[NSWindow alloc] initWithContentRect:NSMakeRect(0, 0, 640, 760) styleMask:NSWindowStyleMaskTitled | NSWindowStyleMaskClosable backing:NSBackingStoreBuffered defer:NO];
    window.title = @"候选设置";
    window.releasedWhenClosed = NO;
    _layoutButton = [[NSPopUpButton alloc] initWithFrame:NSZeroRect pullsDown:NO];
    [_layoutButton addItemsWithTitles:@[@"横向排列", @"纵向列表"]];
    _layoutButton.accessibilityLabel = @"候选排列";
    _layoutButton.target = self;
    _layoutButton.action = @selector(layoutChanged:);
    _schemeButton = [[NSPopUpButton alloc] initWithFrame:NSZeroRect pullsDown:NO];
    [_schemeButton addItemsWithTitles:@[@"全拼", @"双拼", @"五笔"]];
    _schemeButton.target = self;
    _schemeButton.action = @selector(schemeChanged:);
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
    _pageSizeButton = [[NSPopUpButton alloc] initWithFrame:NSZeroRect pullsDown:NO];
    for (NSUInteger size = 1; size <= 9; ++size)
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
    _fullWidthButton = [NSButton checkboxWithTitle:@"全角输入（Option + Shift + H）" target:self action:@selector(fullWidthChanged:)];
    _keymapButton = [NSButton checkboxWithTitle:@"输入时显示双拼键位提示" target:self action:@selector(keymapChanged:)];
    _wubiButton = [NSButton checkboxWithTitle:@"五笔四码唯一候选自动上屏" target:self action:@selector(wubiChanged:)];
    _punctuationButton = [NSButton checkboxWithTitle:@"中文标点" target:self action:@selector(punctuationChanged:)];
    _toolbarButton = [NSButton checkboxWithTitle:@"显示浮动工具栏" target:self action:@selector(toolbarChanged:)];
    _transpositionButton = [NSButton checkboxWithTitle:@"全拼乱序纠错（sahng → shang）" target:self action:@selector(transpositionChanged:)];
    _neighborButton = [NSButton checkboxWithTitle:@"全拼邻键纠错（shabg → shang）" target:self action:@selector(neighborChanged:)];
    _quanpinHelpcodeButton = [NSButton checkboxWithTitle:@"启用全拼辅助码" target:self action:@selector(quanpinHelpcodeChanged:)];
    _shuangpinHelpcodeButton = [NSButton checkboxWithTitle:@"启用双拼辅助码" target:self action:@selector(shuangpinHelpcodeChanged:)];
    NSGridView *grid = [NSGridView gridViewWithViews:@[
        @[[NSTextField labelWithString:@"输入方案"], _schemeButton],
        @[[NSTextField labelWithString:@"双拼键盘"], _profileButton],
        @[[NSTextField labelWithString:@"双拼预编辑"], _preeditButton],
        @[[NSTextField labelWithString:@"候选排列"], _layoutButton],
        @[[NSTextField labelWithString:@"候选字号"], _fontButton],
        @[[NSTextField labelWithString:@"候选字体"], _fontFamilyControl],
        @[[NSTextField labelWithString:@"候选文字颜色"], textColorControls],
        @[[NSTextField labelWithString:@"补充字体（最多 32 项）"], fallbackAdd],
        @[[NSTextField labelWithString:@"补充字体优先顺序"], fallbackOrder],
        @[[NSTextField labelWithString:@"候选窗拼音字号"], _preeditFontButton],
        @[[NSTextField labelWithString:@"候选窗预编辑"], _candidatePreeditButton],
        @[[NSTextField labelWithString:@"候选翻页快捷键"], _pageShortcutButton],
        @[[NSTextField labelWithString:@"每页候选"], _pageSizeButton],
        @[[NSTextField labelWithString:@"候选皮肤"], _skinButton],
        @[[NSTextField labelWithString:@"外部皮肤"], reload],
        @[[NSTextField labelWithString:@"皮肤卡片"], browse],
        @[[NSTextField labelWithString:@"输入切换"], _inputModeShortcutButton],
        @[[NSTextField labelWithString:@"字符宽度"], _fullWidthButton],
        @[[NSTextField labelWithString:@"双拼提示"], _keymapButton],
        @[[NSTextField labelWithString:@"五笔输入"], _wubiButton],
        @[[NSTextField labelWithString:@"标点输入"], _punctuationButton],
        @[[NSTextField labelWithString:@"工具栏"], _toolbarButton],
        @[[NSTextField labelWithString:@"乱序纠错"], _transpositionButton],
        @[[NSTextField labelWithString:@"邻键纠错"], _neighborButton],
        @[[NSTextField labelWithString:@"全拼辅助码"], _quanpinHelpcodeButton],
        @[[NSTextField labelWithString:@"双拼辅助码"], _shuangpinHelpcodeButton]
    ]];
    grid.rowSpacing = 16;
    _helpcodeSchemaButtons = [NSMutableDictionary dictionary];
    _helpcodeDisplayButtons = [NSMutableDictionary dictionary];
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
        [grid addRowWithViews:@[[NSTextField labelWithString:schemas.accessibilityLabel], schemas]];
        [grid addRowWithViews:@[[NSTextField labelWithString:[name stringByAppendingString:@"辅助码显示"]], display]];
    }
    _localModeButtons = [NSMutableArray array];
    for (NSArray<NSString *> *entry in LocalModeControls()) {
        NSButton *button = [NSButton checkboxWithTitle:entry[1] target:self action:@selector(localModeChanged:)];
        button.identifier = entry[0];
        [_localModeButtons addObject:button];
        [grid addRowWithViews:@[[NSTextField labelWithString:@"扩展输入"], button]];
    }
    grid.columnSpacing = 20;
    grid.translatesAutoresizingMaskIntoConstraints = NO;
    NSScrollView *settingsScroll = [[NSScrollView alloc] initWithFrame:NSZeroRect];
    settingsScroll.translatesAutoresizingMaskIntoConstraints = NO;
    settingsScroll.hasVerticalScroller = YES;
    settingsScroll.drawsBackground = NO;
    settingsScroll.documentView = grid;
    [window.contentView addSubview:settingsScroll];
    _preview = [[MSIMECandidatePreviewView alloc] initWithFrame:NSMakeRect(0, 0, 580, 190)];
    _preview.preferences = self;
    NSScrollView *scroll = [[NSScrollView alloc] initWithFrame:NSZeroRect];
    scroll.translatesAutoresizingMaskIntoConstraints = NO;
    scroll.hasVerticalScroller = YES;
    scroll.drawsBackground = NO;
    scroll.documentView = _preview;
    [window.contentView addSubview:scroll];
    _themeButton = [NSButton buttonWithTitle:[_preview forcedThemeButtonTitle] target:self action:@selector(togglePreviewTheme:)];
    _themeButton.translatesAutoresizingMaskIntoConstraints = NO;
    _preview.themeButton = _themeButton;
    [window.contentView addSubview:_themeButton];
    NSButton *showcase = [NSButton checkboxWithTitle:@"同时预览横排、竖排与状态栏" target:self action:@selector(togglePreviewShowcase:)];
    showcase.translatesAutoresizingMaskIntoConstraints = NO;
    [window.contentView addSubview:showcase];
    [NSLayoutConstraint activateConstraints:@[
        [settingsScroll.leadingAnchor constraintEqualToAnchor:window.contentView.leadingAnchor constant:20],
        [settingsScroll.trailingAnchor constraintEqualToAnchor:window.contentView.trailingAnchor constant:-20],
        [settingsScroll.topAnchor constraintEqualToAnchor:window.contentView.topAnchor constant:20],
        [settingsScroll.heightAnchor constraintEqualToConstant:400],
        [grid.centerXAnchor constraintEqualToAnchor:settingsScroll.contentView.centerXAnchor],
        [grid.topAnchor constraintEqualToAnchor:settingsScroll.contentView.topAnchor],
        [scroll.topAnchor constraintEqualToAnchor:settingsScroll.bottomAnchor constant:20],
        [scroll.leadingAnchor constraintEqualToAnchor:window.contentView.leadingAnchor constant:20],
        [scroll.trailingAnchor constraintEqualToAnchor:window.contentView.trailingAnchor constant:-20],
        [scroll.bottomAnchor constraintEqualToAnchor:_themeButton.topAnchor constant:-12],
        [_preview.widthAnchor constraintEqualToAnchor:scroll.contentView.widthAnchor],
        [_preview.leadingAnchor constraintEqualToAnchor:scroll.contentView.leadingAnchor],
        [_preview.topAnchor constraintEqualToAnchor:scroll.contentView.topAnchor],
        [_themeButton.bottomAnchor constraintEqualToAnchor:window.contentView.bottomAnchor constant:-20],
        [_themeButton.trailingAnchor constraintEqualToAnchor:window.contentView.trailingAnchor constant:-20],
        [showcase.leadingAnchor constraintEqualToAnchor:scroll.leadingAnchor],
        [showcase.centerYAnchor constraintEqualToAnchor:_themeButton.centerYAnchor]
    ]];
    self.window = window;
    [self refreshControls];
    [window center];
}
- (void)layoutChanged:(NSPopUpButton *)sender { self.vertical = sender.indexOfSelectedItem == 1; }
- (void)transpositionChanged:(NSButton *)sender { self.autocorrectTransposition = sender.state == NSControlStateValueOn; }
- (void)neighborChanged:(NSButton *)sender { self.autocorrectNeighbor = sender.state == NSControlStateValueOn; }
- (void)quanpinHelpcodeChanged:(NSButton *)sender { self.quanpinHelpcodeEnabled = sender.state == NSControlStateValueOn; }
- (void)shuangpinHelpcodeChanged:(NSButton *)sender { self.shuangpinHelpcodeEnabled = sender.state == NSControlStateValueOn; }
- (void)schemeChanged:(NSPopUpButton *)sender { self.inputScheme = @[@"quanpin", @"shuangpin", @"wubi"][sender.indexOfSelectedItem]; }
- (void)profileChanged:(NSPopUpButton *)sender { self.shuangpinProfile = @[@"xiaohe", @"ziranma", @"shoudao", @"microsoft"][sender.indexOfSelectedItem]; }
- (void)preeditChanged:(NSPopUpButton *)sender { self.shuangpinPreeditUsesRaw = sender.indexOfSelectedItem == 1; }
- (void)inputModeShortcutChanged:(NSButton *)sender { self.inputModeShortcut = sender.state == NSControlStateValueOn; }
- (void)fullWidthChanged:(NSButton *)sender { self.fullWidthInput = sender.state == NSControlStateValueOn; }
- (void)keymapChanged:(NSButton *)sender { self.shuangpinKeymap = sender.state == NSControlStateValueOn; }
- (void)wubiChanged:(NSButton *)sender { self.wubiAutoCommitUnique = sender.state == NSControlStateValueOn; }
- (void)punctuationChanged:(NSButton *)sender { self.chinesePunctuation = sender.state == NSControlStateValueOn; }
- (void)toolbarChanged:(NSButton *)sender { self.floatingToolbarEnabled = sender.state == NSControlStateValueOn; }
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
- (void)showSkinCatalog:(id)sender { [[self skinCatalogController] showWindow:sender]; }
- (void)togglePreviewTheme:(id)sender { (void)sender; [_preview toggleForcedTheme]; }
- (void)togglePreviewShowcase:(NSButton *)sender { [_preview setShowsLayoutShowcase:sender.state == NSControlStateValueOn]; }
- (void)skinChanged:(NSPopUpButton *)sender {
    self.skinID = sender.selectedItem.representedObject ?: @"fluent";
}
- (void)reloadSkinsFromButton:(id)sender { (void)sender; [self reloadSkins]; }
- (void)showWindow:(id)sender { [self reloadSkins]; [super showWindow:sender]; }
- (void)pageShortcutChanged:(NSPopUpButton *)sender { self.pageShortcut = sender.indexOfSelectedItem; }
- (void)pageSizeChanged:(NSPopUpButton *)sender {
    self.pageSize = sender.indexOfSelectedItem + 1;
}
- (void)fontChanged:(NSPopUpButton *)sender {
    NSInteger index = sender.indexOfSelectedItem;
    self.fontSize = index >= 0 && index <= 20 ? index + 12 : 18;
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
