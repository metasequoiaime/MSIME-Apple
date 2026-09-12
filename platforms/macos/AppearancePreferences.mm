#import "AppearancePreferences.h"
#import "CandidateSkinPreviewView.h"
#import "SkinSettingsView.h"

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
static NSString *const PageShortcutKey = @"MSIMEClientCandidatePageShortcut";
static NSString *const PageSizeKey = @"MSIMEClientCandidatePageSize";
static NSString *const SkinKey = @"MSIMEClientCandidateSkin";
static NSString *const EnglishKey = @"MSIMEClientEnglishInputMode";
static NSString *const TraditionalKey = @"MSIMEClientTraditionalOutput";
static NSString *const FullWidthKey = @"MSIMEClientFullWidthInput";
static NSString *const ChinesePunctuationKey = @"MSIMEClientChinesePunctuation";
static NSString *const AutocorrectKey = @"MSIMEClientAutocorrect";
static NSString *const HelpcodeKey = @"MSIMEClientHelpcodeEnabled";
static NSString *const KeymapKey = @"MSIMEClientShuangpinKeymap";
static NSString *const WubiKey = @"MSIMEClientWubiAutoCommitUnique";
static NSString *const InputModeShortcutKey = @"MSIMEClientInputModeShortcut";
static NSString *const FloatingToolbarKey = @"MSIMEClientFloatingToolbarEnabled";

@implementation MSIMEAppearancePreferences {
    NSUserDefaults *_defaults;
    NSNumber *_sharedToolbarEnabled;
    NSMutableDictionary *_sharedLocalModes;
    NSMutableArray<NSButton *> *_localModeButtons;
    NSPopUpButton *_layoutButton;
    NSPopUpButton *_schemeButton;
    NSPopUpButton *_profileButton;
    NSPopUpButton *_preeditButton;
    NSPopUpButton *_fontButton;
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
    NSButton *_autocorrectButton;
    NSButton *_helpcodeButton;
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
    qh[@"enabled"] = @(self.helpcodeEnabled);
    merged[@"quanpin_helpcode"] = qh;
    NSMutableDictionary *sh = [merged[@"shuangpin_helpcode"] mutableCopy] ?: [NSMutableDictionary dictionary];
    sh[@"enabled"] = @(self.helpcodeEnabled);
    merged[@"shuangpin_helpcode"] = sh;
    merged[@"candidate_page_size"] = @(self.pageSize);
    merged[@"candidate_font_size"] = @(self.fontSize);
    merged[@"chinese_punctuation"] = @(self.chinesePunctuation);
    merged[@"autocorrect"] = @(self.autocorrect);
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
- (void)resolveSelectedSkin {
    const std::filesystem::path root = _skinsRoot.fileSystemRepresentation ?: "";
    _lightSkin = msime::mac::ResolveSkin(self.skinID.UTF8String, false, root);
    _darkSkin = msime::mac::ResolveSkin(self.skinID.UTF8String, true, root);
    _decorationImage = nil;
    if (_lightSkin.decorationTopDip > 0 && !_lightSkin.decorationPath.empty()) {
        _decorationImage = [[NSImage alloc] initWithContentsOfFile:@(_lightSkin.decorationPath.c_str())];
    }
}
- (BOOL)vertical { return [_defaults integerForKey:LayoutKey] == 1; }
- (BOOL)autocorrect { return [_defaults objectForKey:AutocorrectKey] == nil ? YES : [_defaults boolForKey:AutocorrectKey]; }
- (void)setAutocorrect:(BOOL)value { [_defaults setBool:value forKey:AutocorrectKey]; [self preferencesChanged]; }
- (BOOL)helpcodeEnabled { return [_defaults objectForKey:HelpcodeKey] == nil ? YES : [_defaults boolForKey:HelpcodeKey]; }
- (void)setHelpcodeEnabled:(BOOL)value { [_defaults setBool:value forKey:HelpcodeKey]; [self preferencesChanged]; }
- (NSString *)inputScheme { NSString *value = [_defaults stringForKey:SchemeKey]; return [@[@"quanpin", @"shuangpin", @"wubi"] containsObject:value] ? value : @"quanpin"; }
- (void)setInputScheme:(NSString *)value { if (![@[@"quanpin", @"shuangpin", @"wubi"] containsObject:value]) value = @"quanpin"; [_defaults setObject:value forKey:SchemeKey]; [self preferencesChanged]; }
- (NSString *)shuangpinProfile { NSString *value = [_defaults stringForKey:ShuangpinProfileKey]; return [@[@"xiaohe", @"ziranma", @"shoudao", @"microsoft"] containsObject:value] ? value : @"xiaohe"; }
- (void)setShuangpinProfile:(NSString *)value { if (![@[@"xiaohe", @"ziranma", @"shoudao", @"microsoft"] containsObject:value]) value = @"xiaohe"; [_defaults setObject:value forKey:ShuangpinProfileKey]; [self preferencesChanged]; }
- (BOOL)shuangpinPreeditUsesRaw { return [_defaults objectForKey:ShuangpinPreeditKey] == nil ? YES : [_defaults boolForKey:ShuangpinPreeditKey]; }
- (void)setShuangpinPreeditUsesRaw:(BOOL)value { [_defaults setBool:value forKey:ShuangpinPreeditKey]; [self preferencesChanged]; }
- (BOOL)englishMode { return [_defaults boolForKey:EnglishKey]; }
- (BOOL)traditionalOutput { return [_defaults boolForKey:TraditionalKey]; }
- (BOOL)fullWidthInput { return [_defaults boolForKey:FullWidthKey]; }
- (BOOL)chinesePunctuation { return [_defaults objectForKey:ChinesePunctuationKey] == nil ? YES : [_defaults boolForKey:ChinesePunctuationKey]; }
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
    [_defaults setInteger:value ? 1 : 0 forKey:LayoutKey];
    [self preferencesChanged];
}
- (NSUInteger)fontSize {
    NSInteger size = [_defaults integerForKey:FontKey];
    return size == 16 || size == 20 ? size : 18;
}
- (void)setFontSize:(NSUInteger)value {
    [_defaults setInteger:value == 16 || value == 20 ? value : 18 forKey:FontKey];
    [self preferencesChanged];
}
- (void)preferencesChanged {
    [self refreshControls];
    [[NSNotificationCenter defaultCenter] postNotificationName:MSIMEAppearanceDidChangeNotification object:self];
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
    NSInteger value = [_defaults integerForKey:PageSizeKey];
    return value == 5 || value == 7 ? value : 9;
}
- (void)setPageSize:(NSUInteger)value {
    [_defaults setInteger:value == 5 || value == 7 ? value : 9 forKey:PageSizeKey];
    [self preferencesChanged];
}
- (void)setPageShortcut:(NSInteger)value {
    [_defaults setInteger:value == 1 || value == 2 ? value : 0 forKey:PageShortcutKey];
    [self preferencesChanged];
}
- (void)refreshControls {
    _fullWidthButton.state = self.fullWidthInput ? NSControlStateValueOn : NSControlStateValueOff;
    _keymapButton.state = self.shuangpinKeymap ? NSControlStateValueOn : NSControlStateValueOff;
    _wubiButton.state = self.wubiAutoCommitUnique ? NSControlStateValueOn : NSControlStateValueOff;
    _punctuationButton.state = self.chinesePunctuation ? NSControlStateValueOn : NSControlStateValueOff;
    _toolbarButton.state = self.floatingToolbarEnabled ? NSControlStateValueOn : NSControlStateValueOff;
    _autocorrectButton.state = self.autocorrect ? NSControlStateValueOn : NSControlStateValueOff;
    _helpcodeButton.state = self.helpcodeEnabled ? NSControlStateValueOn : NSControlStateValueOff;
    for (NSButton *button in _localModeButtons)
        button.state = [self localModeEnabled:button.identifier] ? NSControlStateValueOn : NSControlStateValueOff;
    _inputModeShortcutButton.state = self.inputModeShortcut ? NSControlStateValueOn : NSControlStateValueOff;
    [_layoutButton selectItemAtIndex:self.vertical ? 1 : 0];
    NSDictionary *schemeIndexes = @{@"quanpin": @0, @"shuangpin": @1, @"wubi": @2};
    [_schemeButton selectItemAtIndex:[schemeIndexes[self.inputScheme] integerValue]];
    NSDictionary *profileIndexes = @{@"xiaohe": @0, @"ziranma": @1, @"shoudao": @2, @"microsoft": @3};
    [_profileButton selectItemAtIndex:[profileIndexes[self.shuangpinProfile] integerValue]];
    [_preeditButton selectItemAtIndex:self.shuangpinPreeditUsesRaw ? 1 : 0];
    [_fontButton selectItemAtIndex:self.fontSize == 16 ? 0 : self.fontSize == 20 ? 2 : 1];
    [_pageShortcutButton selectItemAtIndex:self.pageShortcut];
    [_pageSizeButton selectItemAtIndex:self.pageSize == 5 ? 0 : self.pageSize == 7 ? 1 : 2];
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
    [_profileButton addItemsWithTitles:@[@"小鹤", @"自然码", @"搜狗", @"微软"]];
    _profileButton.target = self;
    _profileButton.action = @selector(profileChanged:);
    _preeditButton = [[NSPopUpButton alloc] initWithFrame:NSZeroRect pullsDown:NO];
    [_preeditButton addItemsWithTitles:@[@"全拼显示", @"原始双拼显示"]];
    _preeditButton.target = self;
    _preeditButton.action = @selector(preeditChanged:);
    _fontButton = [[NSPopUpButton alloc] initWithFrame:NSZeroRect pullsDown:NO];
    [_fontButton addItemsWithTitles:@[@"小（16 pt）", @"标准（18 pt）", @"大（20 pt）"]];
    _fontButton.accessibilityLabel = @"候选字号";
    _fontButton.target = self;
    _fontButton.action = @selector(fontChanged:);
    _pageShortcutButton = [[NSPopUpButton alloc] initWithFrame:NSZeroRect pullsDown:NO];
    [_pageShortcutButton addItemsWithTitles:@[@"- / =", @"[ / ]", @"Page Up / Page Down"]];
    _pageShortcutButton.accessibilityLabel = @"候选翻页快捷键";
    _pageShortcutButton.target = self;
    _pageShortcutButton.action = @selector(pageShortcutChanged:);
    _pageSizeButton = [[NSPopUpButton alloc] initWithFrame:NSZeroRect pullsDown:NO];
    [_pageSizeButton addItemsWithTitles:@[@"5 个", @"7 个", @"9 个"]];
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
    _autocorrectButton = [NSButton checkboxWithTitle:@"自动纠错" target:self action:@selector(autocorrectChanged:)];
    _helpcodeButton = [NSButton checkboxWithTitle:@"启用辅助码" target:self action:@selector(helpcodeChanged:)];
    NSGridView *grid = [NSGridView gridViewWithViews:@[
        @[[NSTextField labelWithString:@"输入方案"], _schemeButton],
        @[[NSTextField labelWithString:@"双拼键盘"], _profileButton],
        @[[NSTextField labelWithString:@"双拼预编辑"], _preeditButton],
        @[[NSTextField labelWithString:@"候选排列"], _layoutButton],
        @[[NSTextField labelWithString:@"候选字号"], _fontButton],
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
        @[[NSTextField labelWithString:@"输入辅助"], _autocorrectButton],
        @[[NSTextField labelWithString:@"辅助码"], _helpcodeButton]
    ]];
    grid.rowSpacing = 16;
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
- (void)autocorrectChanged:(NSButton *)sender { self.autocorrect = sender.state == NSControlStateValueOn; }
- (void)helpcodeChanged:(NSButton *)sender { self.helpcodeEnabled = sender.state == NSControlStateValueOn; }
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
    self.pageSize = sender.indexOfSelectedItem == 0 ? 5 : sender.indexOfSelectedItem == 1 ? 7 : 9;
}
- (void)fontChanged:(NSPopUpButton *)sender {
    const NSUInteger sizes[] = {16, 18, 20};
    NSInteger index = sender.indexOfSelectedItem;
    self.fontSize = index >= 0 && index < 3 ? sizes[index] : 18;
}
@end
