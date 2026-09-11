#import "FloatingToolbarPanel.h"
#import "CandidateSkinAppearance.h"

#include <algorithm>

namespace
{
constexpr CGFloat kToolbarWidth = 272.0;
constexpr CGFloat kToolbarHeight = 44.0;
NSString *const kToolbarFrameAutosaveName = @"MetasequoiaFloatingToolbarFrame";

NSButton *ToolbarButton(NSString *title, NSString *identifier, id target, SEL action)
{
    NSButton *button = [NSButton buttonWithTitle:title target:target action:action];
    button.translatesAutoresizingMaskIntoConstraints = NO;
    button.bordered = NO;
    button.font = [NSFont systemFontOfSize:15.0 weight:NSFontWeightMedium];
    button.accessibilityIdentifier = identifier;
    [button.widthAnchor constraintEqualToConstant:42.0].active = YES;
    [button.heightAnchor constraintEqualToConstant:32.0].active = YES;
    return button;
}

NSScreen *ScreenContainingFrame(NSRect frame)
{
    NSScreen *bestScreen = nil;
    CGFloat bestArea = 0.0;
    for (NSScreen *screen in NSScreen.screens)
    {
        NSRect intersection = NSIntersectionRect(frame, screen.frame);
        CGFloat area = intersection.size.width * intersection.size.height;
        if (area > bestArea)
        {
            bestArea = area;
            bestScreen = screen;
        }
    }
    return bestScreen;
}

NSScreen *ScreenContainingMouse()
{
    NSPoint mouseLocation = NSEvent.mouseLocation;
    for (NSScreen *screen in NSScreen.screens)
    {
        if (NSPointInRect(mouseLocation, screen.frame))
        {
            return screen;
        }
    }
    return NSScreen.mainScreen;
}
} // namespace

NSRect MetasequoiaFloatingToolbarFrame(NSRect proposedFrame, NSRect visibleFrame, BOOL hasSavedFrame)
{
    constexpr CGFloat kDefaultMargin = 20.0;
    constexpr CGFloat kRestoredMargin = 12.0;
    proposedFrame.size = NSMakeSize(kToolbarWidth, kToolbarHeight);
    if (!hasSavedFrame)
    {
        proposedFrame.origin.x = NSMaxX(visibleFrame) - proposedFrame.size.width - kDefaultMargin;
        proposedFrame.origin.y = NSMinY(visibleFrame) + kDefaultMargin;
        return proposedFrame;
    }

    CGFloat minimumX = NSMinX(visibleFrame) + kRestoredMargin;
    CGFloat maximumX = NSMaxX(visibleFrame) - proposedFrame.size.width - kRestoredMargin;
    CGFloat minimumY = NSMinY(visibleFrame) + kRestoredMargin;
    CGFloat maximumY = NSMaxY(visibleFrame) - proposedFrame.size.height - kRestoredMargin;
    proposedFrame.origin.x = std::clamp(proposedFrame.origin.x, minimumX, maximumX);
    proposedFrame.origin.y = std::clamp(proposedFrame.origin.y, minimumY, maximumY);
    return proposedFrame;
}

NSMenu *CreateMetasequoiaFloatingToolbarUtilityMenu(id target)
{
    NSMenu *menu = [[NSMenu alloc] initWithTitle:@"水杉输入法"];
    // Every item targets the panel, an NSWindow subclass, and NSMenu's automatic enabling asks
    // NSWindow's own -validateMenuItem: about each one. NSWindow implements -hideToolbar: for real
    // toolbars and answers NO when the window has none, which greyed out 隐藏悬浮状态栏 and swallowed
    // the click. The input menu already opts out of automatic enabling for the same reason.
    menu.autoenablesItems = NO;
    for (NSMenuItem *item in @[
             [[NSMenuItem alloc] initWithTitle:@"表情与符号…"
                                        action:@selector(openCharacterPalette:)
                                 keyEquivalent:@""],
             [[NSMenuItem alloc] initWithTitle:@"打开设置…" action:@selector(openSettings:) keyEquivalent:@""],
             [[NSMenuItem alloc] initWithTitle:@"检查更新…" action:@selector(checkForUpdates:) keyEquivalent:@""],
         ])
    {
        item.target = target;
        item.enabled = YES;
        [menu addItem:item];
    }
    [menu addItem:[NSMenuItem separatorItem]];
    NSMenuItem *website = [[NSMenuItem alloc] initWithTitle:@"访问 msime.app"
                                                     action:@selector(openWebsite:)
                                              keyEquivalent:@""];
    website.target = target;
    website.enabled = YES;
    [menu addItem:website];
    [menu addItem:[NSMenuItem separatorItem]];
    NSMenuItem *hide = [[NSMenuItem alloc] initWithTitle:@"隐藏悬浮状态栏"
                                                  action:@selector(dismissFloatingToolbar:)
                                           keyEquivalent:@""];
    hide.target = target;
    hide.enabled = YES;
    [menu addItem:hide];
    return menu;
}

@interface MetasequoiaFloatingToolbarChromeView : NSView
@property(nonatomic, weak) id appearanceTarget;
@property(nonatomic) SEL appearanceAction;
@property(nonatomic, copy) NSColor *fillColor;
@property(nonatomic, copy) NSColor *strokeColor;
@end
@implementation MetasequoiaFloatingToolbarChromeView
- (void)viewDidChangeEffectiveAppearance
{
    [super viewDidChangeEffectiveAppearance];
    if (self.appearanceTarget != nil && self.appearanceAction != nullptr)
    {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Warc-performSelector-leaks"
        [self.appearanceTarget performSelector:self.appearanceAction];
#pragma clang diagnostic pop
    }
}
- (void)drawRect:(NSRect)dirtyRect
{
    (void)dirtyRect;
    NSBezierPath *path = [NSBezierPath bezierPathWithRoundedRect:self.bounds xRadius:10.0 yRadius:10.0];
    [(self.fillColor != nil ? self.fillColor : NSColor.windowBackgroundColor) setFill];
    [path fill];
    if (self.strokeColor.alphaComponent > 0.01)
    {
        path.lineWidth = 1.0;
        [self.strokeColor setStroke];
        [path stroke];
    }
}
@end

@implementation MetasequoiaFloatingToolbarPanel
{
    MetasequoiaFloatingToolbarChromeView *_chrome;
    NSButton *_inputModeButton;
    NSButton *_punctuationButton;
    NSButton *_fullWidthButton;
    NSButton *_traditionalOutputButton;
    NSButton *_settingsButton;
}

+ (instancetype)sharedPanel
{
    static MetasequoiaFloatingToolbarPanel *panel = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
      panel = [[MetasequoiaFloatingToolbarPanel alloc] init];
    });
    return panel;
}

- (instancetype)init
{
    self = [super initWithContentRect:NSMakeRect(0.0, 0.0, kToolbarWidth, kToolbarHeight)
                            styleMask:NSWindowStyleMaskBorderless | NSWindowStyleMaskNonactivatingPanel
                              backing:NSBackingStoreBuffered
                                defer:NO];
    if (self == nil)
    {
        return nil;
    }

    self.level = NSStatusWindowLevel;
    self.opaque = NO;
    self.backgroundColor = [NSColor clearColor];
    self.hasShadow = YES;
    self.hidesOnDeactivate = NO;
    self.becomesKeyOnlyIfNeeded = YES;
    self.movableByWindowBackground = YES;
    self.collectionBehavior =
        NSWindowCollectionBehaviorCanJoinAllSpaces | NSWindowCollectionBehaviorFullScreenAuxiliary;
    [self setFrameAutosaveName:kToolbarFrameAutosaveName];
    // The autosave name only writes the frame out; a programmatically created window has to read it back itself, and
    // force: is required because this panel is borderless and therefore not resizable.
    [self setFrameUsingName:kToolbarFrameAutosaveName force:YES];

    _chrome = [[MetasequoiaFloatingToolbarChromeView alloc] initWithFrame:self.contentView.bounds];
    _chrome.appearanceTarget = self;
    _chrome.appearanceAction = @selector(applySkin);
    _chrome.wantsLayer = YES;
    _chrome.layer.cornerRadius = 10.0;
    _chrome.layer.masksToBounds = YES;
    self.contentView = _chrome;

    _inputModeButton = ToolbarButton(@"中", @"MetasequoiaFloatingToolbarInputMode", self, @selector(toggleInputMode:));
    _punctuationButton =
        ToolbarButton(@"。", @"MetasequoiaFloatingToolbarPunctuation", self, @selector(togglePunctuation:));
    _fullWidthButton = ToolbarButton(@"半", @"MetasequoiaFloatingToolbarFullWidth", self, @selector(toggleFullWidth:));
    _traditionalOutputButton =
        ToolbarButton(@"简", @"MetasequoiaFloatingToolbarTraditionalOutput", self, @selector(toggleTraditionalOutput:));
    _settingsButton = ToolbarButton(@"", @"MetasequoiaFloatingToolbarSettings", self, @selector(showUtilityMenu:));
    _settingsButton.image = [NSImage imageWithSystemSymbolName:@"gearshape" accessibilityDescription:@"设置"];
    _settingsButton.accessibilityLabel = @"打开水杉输入法工具菜单";
    _settingsButton.toolTip = _settingsButton.accessibilityLabel;

    NSStackView *actions = [NSStackView stackViewWithViews:@[
        _inputModeButton, _punctuationButton, _fullWidthButton, _traditionalOutputButton, _settingsButton
    ]];
    actions.translatesAutoresizingMaskIntoConstraints = NO;
    actions.orientation = NSUserInterfaceLayoutOrientationHorizontal;
    actions.alignment = NSLayoutAttributeCenterY;
    actions.distribution = NSStackViewDistributionEqualSpacing;
    actions.spacing = 8.0;
    [_chrome addSubview:actions];

    [NSLayoutConstraint activateConstraints:@[
        [actions.leadingAnchor constraintEqualToAnchor:_chrome.leadingAnchor constant:10.0],
        [actions.trailingAnchor constraintEqualToAnchor:_chrome.trailingAnchor constant:-10.0],
        [actions.centerYAnchor constraintEqualToAnchor:_chrome.centerYAnchor],
    ]];
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(applySkin)
                                                 name:MetasequoiaCandidateSkinDidChangeNotification
                                               object:nil];
    [self applySkin];
    [self updateEnglishInputMode:NO
              chinesePunctuationEnabled:YES
                       fullWidthEnabled:NO
        traditionalChineseOutputEnabled:NO];
    return self;
}

- (void)dealloc
{
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (void)applySkin
{
    if (_inputModeButton == nil || _settingsButton == nil)
    {
        return;
    }
    const metasequoia::mac::ResolvedSkin skin =
        MetasequoiaResolveStoredCandidateSkin(MetasequoiaAppearanceIsDark(_chrome.effectiveAppearance));
    _chrome.fillColor = MetasequoiaColorFromRgba(skin.tokens.surface);
    _chrome.strokeColor = MetasequoiaColorFromRgba(skin.tokens.border);
    NSColor *text = MetasequoiaColorFromRgba(skin.tokens.text);
    for (NSButton *button in
         @[ _inputModeButton, _punctuationButton, _fullWidthButton, _traditionalOutputButton, _settingsButton ])
    {
        button.contentTintColor = text;
        if (button.title.length > 0)
        {
            button.attributedTitle = [[NSAttributedString alloc] initWithString:button.title
                                                                     attributes:@{
                                                                         NSFontAttributeName : button.font,
                                                                         NSForegroundColorAttributeName : text,
                                                                     }];
        }
    }
    _chrome.needsDisplay = YES;
}

- (BOOL)canBecomeKeyWindow
{
    return NO;
}

- (void)updateEnglishInputMode:(BOOL)englishInputMode
          chinesePunctuationEnabled:(BOOL)chinesePunctuationEnabled
                   fullWidthEnabled:(BOOL)fullWidthEnabled
    traditionalChineseOutputEnabled:(BOOL)traditionalChineseOutputEnabled
{
    _inputModeButton.title = englishInputMode ? @"英" : @"中";
    _inputModeButton.accessibilityLabel = englishInputMode ? @"切换到中文输入" : @"切换到英文输入";
    _punctuationButton.title = chinesePunctuationEnabled ? @"。" : @".";
    _punctuationButton.accessibilityLabel = chinesePunctuationEnabled ? @"切换到西文标点" : @"切换到中文标点";
    _fullWidthButton.title = fullWidthEnabled ? @"全" : @"半";
    _fullWidthButton.accessibilityLabel = fullWidthEnabled ? @"切换到半角输入" : @"切换到全角输入";
    _traditionalOutputButton.title = traditionalChineseOutputEnabled ? @"繁" : @"简";
    _traditionalOutputButton.accessibilityLabel =
        traditionalChineseOutputEnabled ? @"切换到简体输出" : @"切换到繁体输出";
    _inputModeButton.toolTip = _inputModeButton.accessibilityLabel;
    _punctuationButton.toolTip = _punctuationButton.accessibilityLabel;
    _fullWidthButton.toolTip = _fullWidthButton.accessibilityLabel;
    _traditionalOutputButton.toolTip = _traditionalOutputButton.accessibilityLabel;
    [self applySkin];
}

- (void)activateForDelegate:(id<MetasequoiaFloatingToolbarDelegate>)delegate visible:(BOOL)visible
{
    self.toolbarDelegate = delegate;
    [self setVisible:visible forDelegate:delegate];
}

- (void)setVisible:(BOOL)visible forDelegate:(id<MetasequoiaFloatingToolbarDelegate>)delegate
{
    if (self.toolbarDelegate != delegate)
    {
        return;
    }
    if (!visible)
    {
        [self orderOut:nil];
        return;
    }
    if (self.visible)
    {
        // Only clamp the frame when the panel comes on screen; re-showing a visible panel must not move it away from
        // where the user dragged it.
        [self orderFrontRegardless];
        return;
    }

    BOOL hasSavedFrame =
        [[NSUserDefaults standardUserDefaults]
            objectForKey:[@"NSWindow Frame " stringByAppendingString:kToolbarFrameAutosaveName]] != nil;
    NSScreen *screen = hasSavedFrame ? ScreenContainingFrame(self.frame) : ScreenContainingMouse();
    if (screen == nil)
    {
        screen = NSScreen.mainScreen;
    }
    if (screen != nil)
    {
        [self setFrame:MetasequoiaFloatingToolbarFrame(self.frame, screen.visibleFrame, hasSavedFrame) display:NO];
    }
    [self orderFrontRegardless];
}

- (void)deactivateForDelegate:(id<MetasequoiaFloatingToolbarDelegate>)delegate
{
    // A deallocating owner reads back as nil through the weak property, so a nil owner is treated as released by the
    // caller rather than as a mismatch.
    id<MetasequoiaFloatingToolbarDelegate> owner = self.toolbarDelegate;
    if (owner != nil && owner != delegate)
    {
        return;
    }
    [self orderOut:nil];
    self.toolbarDelegate = nil;
}

- (void)toggleInputMode:(id)sender
{
    (void)sender;
    [self.toolbarDelegate floatingToolbarDidRequestToggleInputMode:self];
}

- (void)togglePunctuation:(id)sender
{
    (void)sender;
    [self.toolbarDelegate floatingToolbarDidRequestTogglePunctuation:self];
}

- (void)toggleFullWidth:(id)sender
{
    (void)sender;
    [self.toolbarDelegate floatingToolbarDidRequestToggleFullWidth:self];
}

- (void)toggleTraditionalOutput:(id)sender
{
    (void)sender;
    [self.toolbarDelegate floatingToolbarDidRequestToggleTraditionalOutput:self];
}

- (void)openSettings:(id)sender
{
    (void)sender;
    [self.toolbarDelegate floatingToolbarDidRequestOpenSettings:self];
}

- (void)openCharacterPalette:(id)sender
{
    (void)sender;
    [self.toolbarDelegate floatingToolbarDidRequestOpenCharacterPalette:self];
}

- (void)checkForUpdates:(id)sender
{
    (void)sender;
    [self.toolbarDelegate floatingToolbarDidRequestCheckForUpdates:self];
}

- (void)openWebsite:(id)sender
{
    (void)sender;
    [self.toolbarDelegate floatingToolbarDidRequestOpenWebsite:self];
}

- (void)dismissFloatingToolbar:(id)sender
{
    (void)sender;
    [self.toolbarDelegate floatingToolbarDidRequestHide:self];
}

- (void)showUtilityMenu:(NSButton *)sender
{
    NSMenu *menu = CreateMetasequoiaFloatingToolbarUtilityMenu(self);
    [menu popUpMenuPositioningItem:nil
                        atLocation:NSMakePoint(NSMinX(sender.bounds), NSMaxY(sender.bounds) + 4.0)
                            inView:sender];
}
@end
