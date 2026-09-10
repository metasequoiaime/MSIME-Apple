#import "AppearancePreferences.h"

NSNotificationName const MSIMEAppearanceDidChangeNotification = @"MSIMEClientAppearanceDidChange";
static NSString *const LayoutKey = @"MSIMEClientCandidatePanelStyle";
static NSString *const FontKey = @"MSIMEClientCandidateFontSize";
static NSString *const PageShortcutKey = @"MSIMEClientCandidatePageShortcut";
static NSString *const PageSizeKey = @"MSIMEClientCandidatePageSize";
static NSString *const SkinKey = @"MSIMEClientCandidateSkin";

@implementation MSIMEAppearancePreferences {
    NSUserDefaults *_defaults;
    NSPopUpButton *_layoutButton;
    NSPopUpButton *_fontButton;
    NSPopUpButton *_pageShortcutButton;
    NSPopUpButton *_pageSizeButton;
    NSPopUpButton *_skinButton;
    NSURL *_skinsRoot;
    NSImage *_decorationImage;
    msime::mac::ResolvedSkin _lightSkin;
    msime::mac::ResolvedSkin _darkSkin;
    std::vector<msime::mac::SkinListEntry> _skins;
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
    [_layoutButton selectItemAtIndex:self.vertical ? 1 : 0];
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
    NSWindow *window = [[NSWindow alloc] initWithContentRect:NSMakeRect(0, 0, 460, 320) styleMask:NSWindowStyleMaskTitled | NSWindowStyleMaskClosable backing:NSBackingStoreBuffered defer:NO];
    window.title = @"候选设置";
    window.releasedWhenClosed = NO;
    _layoutButton = [[NSPopUpButton alloc] initWithFrame:NSZeroRect pullsDown:NO];
    [_layoutButton addItemsWithTitles:@[@"横向排列", @"纵向列表"]];
    _layoutButton.accessibilityLabel = @"候选排列";
    _layoutButton.target = self;
    _layoutButton.action = @selector(layoutChanged:);
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
    NSGridView *grid = [NSGridView gridViewWithViews:@[
        @[[NSTextField labelWithString:@"候选排列"], _layoutButton],
        @[[NSTextField labelWithString:@"候选字号"], _fontButton],
        @[[NSTextField labelWithString:@"候选翻页快捷键"], _pageShortcutButton],
        @[[NSTextField labelWithString:@"每页候选"], _pageSizeButton],
        @[[NSTextField labelWithString:@"候选皮肤"], _skinButton],
        @[[NSTextField labelWithString:@"外部皮肤"], reload]
    ]];
    grid.rowSpacing = 16;
    grid.columnSpacing = 20;
    grid.translatesAutoresizingMaskIntoConstraints = NO;
    [window.contentView addSubview:grid];
    [NSLayoutConstraint activateConstraints:@[
        [grid.centerXAnchor constraintEqualToAnchor:window.contentView.centerXAnchor],
        [grid.centerYAnchor constraintEqualToAnchor:window.contentView.centerYAnchor]
    ]];
    self.window = window;
    [self refreshControls];
    [window center];
}
- (void)layoutChanged:(NSPopUpButton *)sender { self.vertical = sender.indexOfSelectedItem == 1; }
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
