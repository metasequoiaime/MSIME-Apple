#import "AppearancePreferences.h"

NSNotificationName const MSIMEAppearanceDidChangeNotification = @"MSIMEClientAppearanceDidChange";
static NSString *const LayoutKey = @"MSIMEClientCandidatePanelStyle";
static NSString *const FontKey = @"MSIMEClientCandidateFontSize";
static NSString *const PageShortcutKey = @"MSIMEClientCandidatePageShortcut";
static NSString *const PageSizeKey = @"MSIMEClientCandidatePageSize";
static NSString *const SkinKey = @"MSIMEClientCandidateSkin";
static NSArray<NSString *> *SkinIDs() { return @[@"fluent", @"wechat", @"graphite", @"willow_green"]; }

@implementation MSIMEAppearancePreferences {
    NSUserDefaults *_defaults;
    NSPopUpButton *_layoutButton;
    NSPopUpButton *_fontButton;
    NSPopUpButton *_pageShortcutButton;
    NSPopUpButton *_pageSizeButton;
    NSPopUpButton *_skinButton;
}
+ (instancetype)sharedPreferences {
    static MSIMEAppearancePreferences *preferences;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ preferences = [[self alloc] initWithDefaults:NSUserDefaults.standardUserDefaults]; });
    return preferences;
}
- (instancetype)initWithDefaults:(NSUserDefaults *)defaults {
    self = [super initWithWindow:nil];
    if (self) _defaults = defaults;
    return self;
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
    return value && [SkinIDs() containsObject:value] ? value : @"fluent";
}
- (void)setSkinID:(NSString *)value {
    [_defaults setObject:value && [SkinIDs() containsObject:value] ? value : @"fluent" forKey:SkinKey];
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
    [_skinButton selectItemAtIndex:[SkinIDs() indexOfObject:self.skinID]];
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
    NSWindow *window = [[NSWindow alloc] initWithContentRect:NSMakeRect(0, 0, 440, 280) styleMask:NSWindowStyleMaskTitled | NSWindowStyleMaskClosable backing:NSBackingStoreBuffered defer:NO];
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
    [_skinButton addItemsWithTitles:@[@"Fluent", @"微信绿", @"石墨 Graphite", @"杨柳青"]];
    _skinButton.accessibilityLabel = @"候选皮肤";
    _skinButton.target = self;
    _skinButton.action = @selector(skinChanged:);
    NSGridView *grid = [NSGridView gridViewWithViews:@[
        @[[NSTextField labelWithString:@"候选排列"], _layoutButton],
        @[[NSTextField labelWithString:@"候选字号"], _fontButton],
        @[[NSTextField labelWithString:@"候选翻页快捷键"], _pageShortcutButton],
        @[[NSTextField labelWithString:@"每页候选"], _pageSizeButton],
        @[[NSTextField labelWithString:@"候选皮肤"], _skinButton]
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
    NSInteger index = sender.indexOfSelectedItem;
    self.skinID = index >= 0 && index < (NSInteger)SkinIDs().count ? SkinIDs()[index] : @"fluent";
}
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
