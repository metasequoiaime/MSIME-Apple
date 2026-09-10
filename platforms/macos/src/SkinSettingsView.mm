extern "C" void MSIMEShowSkinEditor(void);
extern "C" void MSIMEEditSavedSkin(const char *skinId);
#import "SkinSettingsView.h"
#import "CandidateSkinAppearance.h"
#import "CandidateSkinPreviewView.h"
#import "PreferencesWindowController.h"

#include "CandidateSkin.h"
#include "SkinLibrary.h"

namespace
{
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

NSTextField *Label(NSString *text, CGFloat size, NSFontWeight weight, NSColor *color)
{
    NSTextField *label = [NSTextField labelWithString:text];
    label.font = [NSFont systemFontOfSize:size weight:weight];
    label.textColor = color;
    label.translatesAutoresizingMaskIntoConstraints = NO;
    return label;
}

NSString *BuiltinDescription(const std::string &id)
{
    if (id == "wechat")
    {
        return @"微信绿候选窗与悬浮工具栏";
    }
    if (id == "graphite")
    {
        return @"克制、平直的候选窗与悬浮工具栏";
    }
    if (id == "willow_green")
    {
        return @"柔和圆角与柳绿色整行高亮";
    }
    return @"默认候选窗与悬浮状态栏";
}
} // namespace

@interface MetasequoiaSkinSwitch : NSSwitch
@end
@implementation MetasequoiaSkinSwitch
- (void)mouseDown:(NSEvent *)event
{
    if (self.state == NSControlStateValueOn)
    {
        [self sendAction:self.action to:self.target];
        return;
    }
    [super mouseDown:event];
}
- (void)performClick:(id)sender
{
    if (self.state == NSControlStateValueOn)
    {
        [self sendAction:self.action to:self.target];
        return;
    }
    [super performClick:sender];
}
@end

@implementation MetasequoiaSkinSettingsView
{
    NSStackView *_document;
    NSView *_externalCards;
    NSTextField *_directoryLabel;
    NSTextField *_emptyLabel;
    NSTextField *_diagnosticsLabel;
    NSMutableArray<NSSwitch *> *_switches;
    NSMutableArray<MetasequoiaCandidatePreviewView *> *_previews;
    NSMutableArray<NSButton *> *_themeButtons;
    NSMutableArray<NSTextField *> *_titles;
    NSMutableArray<NSString *> *_skinIds;
    NSMutableArray<NSString *> *_skinNames;
}

- (instancetype)initWithFrame:(NSRect)frameRect
{
    self = [super initWithFrame:frameRect];
    if (self == nil)
    {
        return nil;
    }
    self.translatesAutoresizingMaskIntoConstraints = NO;
    self.accessibilityLabel = @"皮肤设置页";
    _switches = [NSMutableArray array];
    _previews = [NSMutableArray array];
    _themeButtons = [NSMutableArray array];
    _titles = [NSMutableArray array];
    _skinIds = [NSMutableArray array];
    _skinNames = [NSMutableArray array];

    NSTextField *title = Label(@"皮肤", 24.0, NSFontWeightSemibold, [NSColor labelColor]);
    NSTextField *summary =
        Label(@"选择内置皮肤，或从本机目录加载自定义皮肤。", 13.0, NSFontWeightRegular, [NSColor secondaryLabelColor]);
    summary.maximumNumberOfLines = 2;

    NSScrollView *scroll = [[NSScrollView alloc] initWithFrame:NSZeroRect];
    scroll.translatesAutoresizingMaskIntoConstraints = NO;
    scroll.hasVerticalScroller = YES;
    scroll.hasHorizontalScroller = NO;
    scroll.drawsBackground = NO;
    scroll.borderType = NSNoBorder;
    scroll.autohidesScrollers = YES;

    _document = [NSStackView stackViewWithViews:@[]];
    _document.orientation = NSUserInterfaceLayoutOrientationVertical;
    _document.alignment = NSLayoutAttributeLeading;
    _document.spacing = 16.0;
    _document.edgeInsets = NSEdgeInsetsMake(0.0, 30.0, 20.0, 30.0);
    _document.translatesAutoresizingMaskIntoConstraints = NO;
    scroll.documentView = _document;
    [NSLayoutConstraint activateConstraints:@[
        [_document.topAnchor constraintEqualToAnchor:scroll.contentView.topAnchor],
        [_document.leadingAnchor constraintEqualToAnchor:scroll.contentView.leadingAnchor],
        [_document.widthAnchor constraintEqualToAnchor:scroll.contentView.widthAnchor],
    ]];

    [self addSubview:title];
    [self addSubview:summary];
    [self addSubview:scroll];
    [NSLayoutConstraint activateConstraints:@[
        [title.leadingAnchor constraintEqualToAnchor:self.leadingAnchor constant:30.0],
        [title.trailingAnchor constraintEqualToAnchor:self.trailingAnchor constant:-30.0],
        [title.topAnchor constraintEqualToAnchor:self.topAnchor constant:28.0],
        [summary.leadingAnchor constraintEqualToAnchor:title.leadingAnchor],
        [summary.trailingAnchor constraintEqualToAnchor:title.trailingAnchor],
        [summary.topAnchor constraintEqualToAnchor:title.bottomAnchor constant:7.0],
        [scroll.leadingAnchor constraintEqualToAnchor:self.leadingAnchor],
        [scroll.trailingAnchor constraintEqualToAnchor:self.trailingAnchor],
        [scroll.topAnchor constraintEqualToAnchor:summary.bottomAnchor constant:16.0],
        [scroll.bottomAnchor constraintEqualToAnchor:self.bottomAnchor],
    ]];

    for (const metasequoia::mac::SkinListEntry &entry : metasequoia::mac::BuiltInSkinEntries())
    {
        [self addSection:[self makeCardForId:@(entry.id.c_str())
                                        name:@(entry.name.c_str())
                                 description:BuiltinDescription(entry.id)]];
    }

    NSTextField *externalTitle = Label(@"外部皮肤", 13.0, NSFontWeightSemibold, [NSColor secondaryLabelColor]);
    NSTextField *externalHelp = Label(@"把包含 skin.toml 的皮肤文件夹复制到下面的目录，然后刷新。", 13.0,
                                      NSFontWeightRegular, [NSColor secondaryLabelColor]);
    externalHelp.maximumNumberOfLines = 2;
    _directoryLabel = Label(@"", 12.0, NSFontWeightRegular, [NSColor secondaryLabelColor]);
    _directoryLabel.accessibilityLabel = @"外部皮肤目录";
    _directoryLabel.selectable = YES;
    NSButton *open = [NSButton buttonWithTitle:@"打开目录" target:self action:@selector(openDirectory:)];
    open.bezelStyle = NSBezelStyleRounded;
    open.accessibilityLabel = @"打开皮肤目录";
    NSButton *refresh = [NSButton buttonWithTitle:@"刷新皮肤" target:self action:@selector(reload)];
    refresh.bezelStyle = NSBezelStyleRounded;
    refresh.accessibilityLabel = @"刷新皮肤";
    NSButton *edit = [NSButton buttonWithTitle:@"设计配色…" target:self action:@selector(showSkinEditor:)];
    NSStackView *actions = [NSStackView stackViewWithViews:@[ open, refresh, edit ]];
    actions.orientation = NSUserInterfaceLayoutOrientationHorizontal;
    actions.spacing = 8.0;
    NSBox *externalHeader = [[NSBox alloc] initWithFrame:NSZeroRect];
    ConfigureCard(externalHeader);
    externalHeader.accessibilityLabel = @"外部皮肤卡片";
    NSStackView *headerStack =
        [NSStackView stackViewWithViews:@[ externalTitle, externalHelp, _directoryLabel, actions ]];
    headerStack.orientation = NSUserInterfaceLayoutOrientationVertical;
    headerStack.alignment = NSLayoutAttributeLeading;
    headerStack.spacing = 6.0;
    headerStack.translatesAutoresizingMaskIntoConstraints = NO;
    [externalHeader addSubview:headerStack];
    [NSLayoutConstraint activateConstraints:@[
        [headerStack.leadingAnchor constraintEqualToAnchor:externalHeader.leadingAnchor constant:16.0],
        [headerStack.trailingAnchor constraintEqualToAnchor:externalHeader.trailingAnchor constant:-16.0],
        [headerStack.topAnchor constraintEqualToAnchor:externalHeader.topAnchor constant:12.0],
        [headerStack.bottomAnchor constraintEqualToAnchor:externalHeader.bottomAnchor constant:-12.0],
        [actions.trailingAnchor constraintLessThanOrEqualToAnchor:headerStack.trailingAnchor],
    ]];
    [self addSection:externalHeader];

    _externalCards = [[NSView alloc] initWithFrame:NSZeroRect];
    _externalCards.translatesAutoresizingMaskIntoConstraints = NO;
    [self addSection:_externalCards];

    _emptyLabel =
        Label(@"尚未扫描。点击“刷新皮肤”读取皮肤目录。", 13.0, NSFontWeightRegular, [NSColor secondaryLabelColor]);
    _emptyLabel.accessibilityLabel = @"外部皮肤空状态";
    [self addSection:_emptyLabel];

    _diagnosticsLabel = Label(@"", 12.0, NSFontWeightRegular, [NSColor systemOrangeColor]);
    _diagnosticsLabel.accessibilityLabel = @"皮肤扫描诊断";
    _diagnosticsLabel.maximumNumberOfLines = 8;
    [self addSection:_diagnosticsLabel];

    [self reload];
    return self;
}

- (void)addSection:(NSView *)view
{
    view.translatesAutoresizingMaskIntoConstraints = NO;
    [_document addArrangedSubview:view];
    [view.widthAnchor constraintEqualToAnchor:_document.widthAnchor constant:-60.0].active = YES;
}

- (NSView *)makeCardForId:(NSString *)skinId name:(NSString *)name description:(NSString *)description
{
    NSBox *card = [[NSBox alloc] initWithFrame:NSZeroRect];
    ConfigureCard(card);
    card.accessibilityLabel = [name stringByAppendingString:@"皮肤卡片"];
    NSTextField *title = Label(name, 15.0, NSFontWeightSemibold, [NSColor labelColor]);
    title.accessibilityLabel = [name stringByAppendingString:@"标题"];
    NSTextField *summary = Label(description, 13.0, NSFontWeightRegular, [NSColor secondaryLabelColor]);
    summary.maximumNumberOfLines = 2;
    NSSwitch *enable = [[MetasequoiaSkinSwitch alloc] initWithFrame:NSZeroRect];
    enable.identifier = skinId;
    enable.target = self;
    enable.action = @selector(enableSkin:);
    enable.accessibilityLabel = [@"启用" stringByAppendingString:name];
    NSButton *theme = [NSButton buttonWithTitle:@"预览浅色" target:self action:@selector(toggleCardTheme:)];
    theme.bezelStyle = NSBezelStyleRounded;
    theme.identifier = skinId;
    theme.accessibilityLabel = [name stringByAppendingString:@"预览明暗"];
    MetasequoiaCandidatePreviewView *preview = [[MetasequoiaCandidatePreviewView alloc] initWithFrame:NSZeroRect];
    [preview setShowsLayoutShowcase:YES];
    [preview setPreviewSkinId:skinId];
    preview.accessibilityLabel = [name stringByAppendingString:@"预览"];
    NSStackView *text = [NSStackView stackViewWithViews:@[ title, summary ]];
    text.orientation = NSUserInterfaceLayoutOrientationVertical;
    text.alignment = NSLayoutAttributeLeading;
    text.spacing = 4.0;
    NSStackView *actions = [NSStackView stackViewWithViews:@[ enable, theme ]];
    actions.orientation = NSUserInterfaceLayoutOrientationHorizontal;
    actions.spacing = 8.0;
    NSStackView *header = [NSStackView stackViewWithViews:@[ text, actions ]];
    header.orientation = NSUserInterfaceLayoutOrientationHorizontal;
    header.alignment = NSLayoutAttributeTop;
    header.distribution = NSStackViewDistributionFill;
    NSMutableArray<NSView *> *contents = [NSMutableArray arrayWithArray:@[ header, preview ]];
    if (!metasequoia::mac::IsBuiltInSkinId(skinId.UTF8String)) {
        NSButton *edit = [NSButton buttonWithTitle:@"编辑配色、插画与分享…" target:self action:@selector(editSavedSkin:)];
        edit.identifier = skinId;
        edit.accessibilityLabel = [name stringByAppendingString:@"编辑与分享"];
        NSButton *remove = [NSButton buttonWithTitle:@"移到废纸篓…" target:self action:@selector(trashSavedSkin:)];
        remove.identifier = skinId;
        remove.accessibilityLabel = [name stringByAppendingString:@"移到废纸篓"];
        NSButton *rename = [NSButton buttonWithTitle:@"重命名…" target:self action:@selector(renameSavedSkin:)];
        rename.identifier = skinId;
        rename.accessibilityLabel = [name stringByAppendingString:@"重命名"];
        NSStackView *management = [NSStackView stackViewWithViews:@[ edit, rename, remove ]];
        management.orientation = NSUserInterfaceLayoutOrientationHorizontal;
        management.spacing = 8;
        [contents addObject:management];
    }
    NSStackView *stack = [NSStackView stackViewWithViews:contents];
    stack.orientation = NSUserInterfaceLayoutOrientationVertical;
    stack.alignment = NSLayoutAttributeLeading;
    stack.spacing = 10.0;
    stack.translatesAutoresizingMaskIntoConstraints = NO;
    [card addSubview:stack];
    [NSLayoutConstraint activateConstraints:@[
        [stack.leadingAnchor constraintEqualToAnchor:card.leadingAnchor constant:16.0],
        [stack.trailingAnchor constraintEqualToAnchor:card.trailingAnchor constant:-16.0],
        [stack.topAnchor constraintEqualToAnchor:card.topAnchor constant:12.0],
        [stack.bottomAnchor constraintEqualToAnchor:card.bottomAnchor constant:-12.0],
        [preview.widthAnchor constraintEqualToAnchor:stack.widthAnchor],
        [header.widthAnchor constraintEqualToAnchor:stack.widthAnchor],
        [text.trailingAnchor constraintLessThanOrEqualToAnchor:actions.leadingAnchor constant:-12.0],
    ]];
    [_skinIds addObject:skinId];
    [_skinNames addObject:name];
    [_switches addObject:enable];
    [_previews addObject:preview];
    [_themeButtons addObject:theme];
    [_titles addObject:title];
    return card;
}

- (void)refreshSelection
{
    [self refreshCardChrome];
}

- (void)enableSkin:(NSSwitch *)sender
{
    NSString *skinId = sender.identifier;
    if (skinId.length == 0)
    {
        return;
    }
    sender.state = NSControlStateValueOn;
    [MetasequoiaPreferencesWindowController setStoredCandidateSkin:skinId];
}

- (void)toggleCardTheme:(NSButton *)sender
{
    NSUInteger index = [_themeButtons indexOfObject:sender];
    if (index == NSNotFound)
    {
        return;
    }
    [_previews[index] toggleForcedTheme];
    [self refreshCardChrome];
}

- (void)openDirectory:(id)sender
{
    (void)sender;
    NSURL *directory = MetasequoiaCandidateSkinsDirectoryURL();
    if (directory == nil)
    {
        return;
    }
    [[NSFileManager defaultManager] createDirectoryAtURL:directory
                             withIntermediateDirectories:YES
                                              attributes:nil
                                                   error:nil];
    [[NSWorkspace sharedWorkspace] openURL:directory];
    [self reload];
}

- (void)refreshCardChrome
{
    NSString *active = [MetasequoiaPreferencesWindowController storedCandidateSkin];
    for (NSUInteger index = 0; index < _skinIds.count; ++index)
    {
        const BOOL selected = [_skinIds[index] isEqualToString:active];
        _switches[index].state = selected ? NSControlStateValueOn : NSControlStateValueOff;
        _themeButtons[index].title = [_previews[index] forcedThemeButtonTitle];
        _titles[index].stringValue = [NSString
            stringWithFormat:@"%@（%@）", _skinNames[index], [_previews[index] previewUsesDark] ? @"Dark" : @"Light"];
        _previews[index].needsDisplay = YES;
    }
}

- (void)clearExternalCards
{
    while (_skinIds.count > metasequoia::mac::BuiltInSkinEntries().size())
    {
        [_skinIds removeLastObject];
        [_skinNames removeLastObject];
        [_switches removeLastObject];
        [_previews removeLastObject];
        [_themeButtons removeLastObject];
        [_titles removeLastObject];
    }
    for (NSView *child in [_externalCards.subviews copy])
    {
        [child removeFromSuperview];
    }
}

- (void)renameSavedSkin:(NSButton *)sender
{
    NSError *error = nil;
    const auto reviewed = metasequoia::mac::ReviewSkinRemoval(MetasequoiaCandidateSkinsDirectoryURL(), sender.identifier, &error);
    if (!reviewed) { [NSApp presentError:error]; [self reload]; return; }
    NSAlert *dialog = [[NSAlert alloc] init];
    dialog.messageText = @"重命名皮肤";
    NSTextField *name = [[NSTextField alloc] initWithFrame:NSMakeRect(0, 0, 320, 24)];
    name.stringValue = reviewed->name;
    name.accessibilityLabel = @"新的皮肤名称";
    dialog.accessoryView = name;
    [dialog addButtonWithTitle:@"保存名称"];
    [dialog addButtonWithTitle:@"取消"];
    dialog.window.initialFirstResponder = name;
    if ([dialog runModal] != NSAlertFirstButtonReturn) return;
    if (!metasequoia::mac::RenameReviewedSkin(*reviewed, name.stringValue, &error)) [NSApp presentError:error];
    [self reload];
}

- (void)trashSavedSkin:(NSButton *)sender
{
    NSError *error = nil;
    const auto reviewed = metasequoia::mac::ReviewSkinRemoval(MetasequoiaCandidateSkinsDirectoryURL(), sender.identifier, &error);
    if (!reviewed) { [NSApp presentError:error]; [self reload]; return; }
    NSAlert *confirmation = [[NSAlert alloc] init];
    confirmation.messageText = [NSString stringWithFormat:@"将“%@”移到废纸篓？", reviewed->name];
    confirmation.informativeText = @"皮肤文件夹将移到 macOS 废纸篓，可在访达中恢复。如果它正在使用，将切换到默认皮肤。";
    [confirmation addButtonWithTitle:@"移到废纸篓"];
    [confirmation addButtonWithTitle:@"取消"];
    if ([confirmation runModal] != NSAlertFirstButtonReturn) return;
    const bool removed = metasequoia::mac::TrashReviewedSkin(*reviewed, ^BOOL(NSURL *directory, NSError **trashError) {
        return [[NSFileManager defaultManager] trashItemAtURL:directory resultingItemURL:nil error:trashError];
    }, &error);
    if (removed && [[MetasequoiaPreferencesWindowController storedCandidateSkin] isEqual:reviewed->skinId]) {
        [MetasequoiaPreferencesWindowController setStoredCandidateSkin:@"fluent"];
    }
    if (!removed && error) [NSApp presentError:error];
    [self reload];
}

- (void)editSavedSkin:(NSButton *)sender { MSIMEEditSavedSkin(sender.identifier.UTF8String); }

- (void)showSkinEditor:(id)sender { (void)sender; MSIMEShowSkinEditor(); }

- (void)reload
{
    [self clearExternalCards];
    const std::filesystem::path root = metasequoia::mac::DefaultSkinsRoot();
    NSString *path = @(root.string().c_str());
    if ([path hasPrefix:NSHomeDirectory()])
    {
        path = [@"~" stringByAppendingString:[path substringFromIndex:NSHomeDirectory().length]];
    }
    _directoryLabel.stringValue = path.length > 0 ? path : @"~/Library/Application Support/metasequoiaime/skins";

    const metasequoia::mac::SkinCatalog catalog = metasequoia::mac::ScanSkinCatalog(root);
    NSMutableArray<NSView *> *cards = [NSMutableArray array];
    for (const metasequoia::mac::SkinPackage &package : catalog.packages)
    {
        NSString *description = package.description.empty()
                                    ? [NSString stringWithFormat:@"基于 %s", package.base.c_str()]
                                    : @(package.description.c_str());
        [cards addObject:[self makeCardForId:@(package.id.c_str())
                                        name:@(package.name.c_str())
                                 description:description]];
    }
    if (cards.count > 0)
    {
        NSStackView *stack = [NSStackView stackViewWithViews:cards];
        stack.orientation = NSUserInterfaceLayoutOrientationVertical;
        stack.alignment = NSLayoutAttributeLeading;
        stack.spacing = 16.0;
        stack.translatesAutoresizingMaskIntoConstraints = NO;
        [_externalCards addSubview:stack];
        [NSLayoutConstraint activateConstraints:@[
            [stack.leadingAnchor constraintEqualToAnchor:_externalCards.leadingAnchor],
            [stack.trailingAnchor constraintEqualToAnchor:_externalCards.trailingAnchor],
            [stack.topAnchor constraintEqualToAnchor:_externalCards.topAnchor],
            [stack.bottomAnchor constraintEqualToAnchor:_externalCards.bottomAnchor],
            [stack.widthAnchor constraintEqualToAnchor:_externalCards.widthAnchor],
        ]];
        for (NSView *card in cards)
        {
            [card.widthAnchor constraintEqualToAnchor:stack.widthAnchor].active = YES;
        }
    }
    _emptyLabel.hidden = cards.count > 0;
    _emptyLabel.stringValue = cards.count > 0 ? @"" : @"没有发现外部皮肤。把皮肤文件夹放到目录中后点击“刷新皮肤”。";
    if (catalog.issues.empty())
    {
        _diagnosticsLabel.stringValue = @"";
        _diagnosticsLabel.hidden = YES;
    }
    else
    {
        NSMutableString *text = [NSMutableString stringWithFormat:@"已忽略 %zu 个无效皮肤目录", catalog.issues.size()];
        for (const metasequoia::mac::SkinIssue &issue : catalog.issues)
        {
            [text appendFormat:@"\n%s：%s", issue.folder.c_str(), issue.reason.c_str()];
        }
        _diagnosticsLabel.stringValue = text;
        _diagnosticsLabel.hidden = NO;
    }
    [self refreshCardChrome];
    [_document layoutSubtreeIfNeeded];
}

@end
