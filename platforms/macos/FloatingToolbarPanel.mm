#import "FloatingToolbarPanel.h"
#import "AppearancePreferences.h"

#include <algorithm>

namespace {
constexpr CGFloat kToolbarWidth = 272.0;
constexpr CGFloat kToolbarHeight = 44.0;
NSString *const kToolbarFrameAutosaveName = @"MSIMEFloatingToolbarFrame";

NSColor *SkinColor(msime::mac::Rgba color) {
    return [NSColor colorWithSRGBRed:color.r green:color.g blue:color.b alpha:color.a];
}

BOOL IsDarkAppearance(NSAppearance *appearance) {
    NSAppearanceName match = [appearance bestMatchFromAppearancesWithNames:@[NSAppearanceNameAqua, NSAppearanceNameDarkAqua]];
    return [match isEqualToString:NSAppearanceNameDarkAqua];
}

NSButton *ToolbarButton(NSString *title, NSString *identifier, id target, SEL action) {
    NSButton *button = [NSButton buttonWithTitle:title target:target action:action];
    button.translatesAutoresizingMaskIntoConstraints = NO;
    button.bordered = NO;
    button.font = [NSFont systemFontOfSize:15.0 weight:NSFontWeightMedium];
    button.accessibilityIdentifier = identifier;
    [button.widthAnchor constraintEqualToConstant:42.0].active = YES;
    [button.heightAnchor constraintEqualToConstant:32.0].active = YES;
    return button;
}

NSScreen *ScreenContainingFrame(NSRect frame) {
    NSScreen *bestScreen = nil;
    CGFloat bestArea = 0.0;
    for (NSScreen *screen in NSScreen.screens) {
        NSRect intersection = NSIntersectionRect(frame, screen.frame);
        CGFloat area = intersection.size.width * intersection.size.height;
        if (area > bestArea) {
            bestArea = area;
            bestScreen = screen;
        }
    }
    return bestScreen;
}

NSScreen *ScreenContainingMouse() {
    NSPoint mouseLocation = NSEvent.mouseLocation;
    for (NSScreen *screen in NSScreen.screens) {
        if (NSPointInRect(mouseLocation, screen.frame)) return screen;
    }
    return NSScreen.mainScreen;
}
} // namespace

NSRect MSIMEFloatingToolbarFrame(NSRect proposedFrame, NSRect visibleFrame, BOOL hasSavedFrame) {
    constexpr CGFloat kDefaultMargin = 20.0;
    constexpr CGFloat kRestoredMargin = 12.0;
    proposedFrame.size = NSMakeSize(kToolbarWidth, kToolbarHeight);
    if (!hasSavedFrame) {
        proposedFrame.origin.x = NSMaxX(visibleFrame) - proposedFrame.size.width - kDefaultMargin;
        proposedFrame.origin.y = NSMinY(visibleFrame) + kDefaultMargin;
        return proposedFrame;
    }
    const CGFloat minimumX = NSMinX(visibleFrame) + kRestoredMargin;
    const CGFloat maximumX = NSMaxX(visibleFrame) - proposedFrame.size.width - kRestoredMargin;
    const CGFloat minimumY = NSMinY(visibleFrame) + kRestoredMargin;
    const CGFloat maximumY = NSMaxY(visibleFrame) - proposedFrame.size.height - kRestoredMargin;
    proposedFrame.origin.x = std::clamp(proposedFrame.origin.x, minimumX, maximumX);
    proposedFrame.origin.y = std::clamp(proposedFrame.origin.y, minimumY, maximumY);
    return proposedFrame;
}

NSMenu *CreateMSIMEFloatingToolbarUtilityMenu(id target) {
    NSMenu *menu = [[NSMenu alloc] initWithTitle:@"水杉输入法"];
    menu.autoenablesItems = NO;
    for (NSMenuItem *item in @[
        [[NSMenuItem alloc] initWithTitle:@"表情与符号…" action:@selector(openCharacterPalette:) keyEquivalent:@""],
        [[NSMenuItem alloc] initWithTitle:@"打开设置…" action:@selector(openSettings:) keyEquivalent:@""],
        [[NSMenuItem alloc] initWithTitle:@"检查更新…" action:@selector(checkForUpdates:) keyEquivalent:@""],
    ]) {
        item.target = target;
        item.enabled = YES;
        [menu addItem:item];
    }
    [menu addItem:[NSMenuItem separatorItem]];
    NSMenuItem *website = [[NSMenuItem alloc] initWithTitle:@"访问 msime.app" action:@selector(openWebsite:) keyEquivalent:@""];
    website.target = target;
    website.enabled = YES;
    [menu addItem:website];
    [menu addItem:[NSMenuItem separatorItem]];
    NSMenuItem *hide = [[NSMenuItem alloc] initWithTitle:@"隐藏悬浮工具栏" action:@selector(dismissFloatingToolbar:) keyEquivalent:@""];
    hide.target = target;
    hide.enabled = YES;
    [menu addItem:hide];
    return menu;
}

@interface MSIMEFloatingToolbarChromeView : NSView
@property(nonatomic, weak) id appearanceTarget;
@property(nonatomic) SEL appearanceAction;
@property(nonatomic, copy) NSColor *fillColor;
@property(nonatomic, copy) NSColor *strokeColor;
@end

@implementation MSIMEFloatingToolbarChromeView
- (void)viewDidChangeEffectiveAppearance {
    [super viewDidChangeEffectiveAppearance];
    if (self.appearanceTarget != nil && self.appearanceAction != nullptr) {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Warc-performSelector-leaks"
        [self.appearanceTarget performSelector:self.appearanceAction];
#pragma clang diagnostic pop
    }
}
- (void)drawRect:(NSRect)dirtyRect {
    (void)dirtyRect;
    NSBezierPath *path = [NSBezierPath bezierPathWithRoundedRect:self.bounds xRadius:10.0 yRadius:10.0];
    [(self.fillColor ?: NSColor.windowBackgroundColor) setFill];
    [path fill];
    if (self.strokeColor.alphaComponent > 0.01) {
        path.lineWidth = 1.0;
        [self.strokeColor setStroke];
        [path stroke];
    }
}
@end

@implementation MSIMEFloatingToolbarPanel {
    MSIMEFloatingToolbarChromeView *_chrome;
    NSButton *_inputModeButton;
    NSButton *_punctuationButton;
    NSButton *_fullWidthButton;
    NSButton *_traditionalOutputButton;
    NSButton *_settingsButton;
}

+ (instancetype)sharedPanel {
    static MSIMEFloatingToolbarPanel *panel;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ panel = [[self alloc] init]; });
    return panel;
}

- (instancetype)init {
    self = [super initWithContentRect:NSMakeRect(0.0, 0.0, kToolbarWidth, kToolbarHeight)
                             styleMask:NSWindowStyleMaskBorderless | NSWindowStyleMaskNonactivatingPanel
                               backing:NSBackingStoreBuffered defer:NO];
    if (!self) return nil;
    self.level = NSStatusWindowLevel;
    self.opaque = NO;
    self.backgroundColor = NSColor.clearColor;
    self.hasShadow = YES;
    self.hidesOnDeactivate = NO;
    self.becomesKeyOnlyIfNeeded = YES;
    self.movableByWindowBackground = YES;
    self.collectionBehavior = NSWindowCollectionBehaviorCanJoinAllSpaces | NSWindowCollectionBehaviorFullScreenAuxiliary;
    [self setFrameAutosaveName:kToolbarFrameAutosaveName];
    [self setFrameUsingName:kToolbarFrameAutosaveName force:YES];

    _chrome = [[MSIMEFloatingToolbarChromeView alloc] initWithFrame:self.contentView.bounds];
    _chrome.appearanceTarget = self;
    _chrome.appearanceAction = @selector(applySkin);
    _chrome.wantsLayer = YES;
    _chrome.layer.cornerRadius = 10.0;
    _chrome.layer.masksToBounds = YES;
    self.contentView = _chrome;
    _inputModeButton = ToolbarButton(@"中", @"MSIMEFloatingToolbarInputMode", self, @selector(toggleInputMode:));
    _punctuationButton = ToolbarButton(@"。", @"MSIMEFloatingToolbarPunctuation", self, @selector(togglePunctuation:));
    _fullWidthButton = ToolbarButton(@"半", @"MSIMEFloatingToolbarFullWidth", self, @selector(toggleFullWidth:));
    _traditionalOutputButton = ToolbarButton(@"简", @"MSIMEFloatingToolbarTraditionalOutput", self, @selector(toggleTraditionalOutput:));
    _settingsButton = ToolbarButton(@"", @"MSIMEFloatingToolbarSettings", self, @selector(showUtilityMenu:));
    _settingsButton.image = [NSImage imageWithSystemSymbolName:@"gearshape" accessibilityDescription:@"设置"];
    _settingsButton.accessibilityLabel = @"打开水杉输入法工具菜单";
    _settingsButton.toolTip = _settingsButton.accessibilityLabel;
    NSStackView *actions = [NSStackView stackViewWithViews:@[_inputModeButton, _punctuationButton, _fullWidthButton, _traditionalOutputButton, _settingsButton]];
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
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(applySkin)
                                                 name:MSIMEAppearanceDidChangeNotification object:nil];
    [self applySkin];
    [self updateEnglishInputMode:NO chinesePunctuationEnabled:YES fullWidthEnabled:NO traditionalChineseOutputEnabled:NO];
    return self;
}

- (void)dealloc { [[NSNotificationCenter defaultCenter] removeObserver:self]; }
- (BOOL)canBecomeKeyWindow { return NO; }

- (void)applySkin {
    if (!_inputModeButton) return;
    const msime::mac::ResolvedSkin skin = [[MSIMEAppearancePreferences sharedPreferences] resolvedSkinForDark:IsDarkAppearance(_chrome.effectiveAppearance)];
    _chrome.fillColor = SkinColor(skin.tokens.surface);
    _chrome.strokeColor = SkinColor(skin.tokens.border);
    NSColor *text = SkinColor(skin.tokens.text);
    for (NSButton *button in @[_inputModeButton, _punctuationButton, _fullWidthButton, _traditionalOutputButton, _settingsButton]) {
        button.contentTintColor = text;
        if (button.title.length) button.attributedTitle = [[NSAttributedString alloc] initWithString:button.title attributes:@{NSFontAttributeName: button.font, NSForegroundColorAttributeName: text}];
    }
    _chrome.needsDisplay = YES;
}

- (void)updateEnglishInputMode:(BOOL)englishInputMode
          chinesePunctuationEnabled:(BOOL)chinesePunctuationEnabled
                   fullWidthEnabled:(BOOL)fullWidthEnabled
    traditionalChineseOutputEnabled:(BOOL)traditionalChineseOutputEnabled {
    _inputModeButton.title = englishInputMode ? @"英" : @"中";
    _inputModeButton.accessibilityLabel = englishInputMode ? @"切换到中文输入" : @"切换到英文输入";
    _punctuationButton.title = chinesePunctuationEnabled ? @"。" : @".";
    _punctuationButton.accessibilityLabel = chinesePunctuationEnabled ? @"切换到西文标点" : @"切换到中文标点";
    _fullWidthButton.title = fullWidthEnabled ? @"全" : @"半";
    _fullWidthButton.accessibilityLabel = fullWidthEnabled ? @"切换到半角输入" : @"切换到全角输入";
    _traditionalOutputButton.title = traditionalChineseOutputEnabled ? @"繁" : @"简";
    _traditionalOutputButton.accessibilityLabel = traditionalChineseOutputEnabled ? @"切换到简体输出" : @"切换到繁体输出";
    for (NSButton *button in @[_inputModeButton, _punctuationButton, _fullWidthButton, _traditionalOutputButton]) button.toolTip = button.accessibilityLabel;
    [self applySkin];
}

- (void)activateForDelegate:(id<MSIMEFloatingToolbarDelegate>)delegate visible:(BOOL)visible {
    self.toolbarDelegate = delegate;
    [self setVisible:visible forDelegate:delegate];
}
- (void)setVisible:(BOOL)visible forDelegate:(id<MSIMEFloatingToolbarDelegate>)delegate {
    if (self.toolbarDelegate != delegate) return;
    if (!visible) { [self orderOut:nil]; return; }
    if (self.visible) { [self orderFrontRegardless]; return; }
    BOOL hasSavedFrame = [[NSUserDefaults standardUserDefaults] objectForKey:[@"NSWindow Frame " stringByAppendingString:kToolbarFrameAutosaveName]] != nil;
    NSScreen *screen = hasSavedFrame ? ScreenContainingFrame(self.frame) : ScreenContainingMouse();
    if (!screen) screen = NSScreen.mainScreen;
    if (screen) [self setFrame:MSIMEFloatingToolbarFrame(self.frame, screen.visibleFrame, hasSavedFrame) display:NO];
    [self orderFrontRegardless];
}
- (void)deactivateForDelegate:(id<MSIMEFloatingToolbarDelegate>)delegate {
    id owner = self.toolbarDelegate;
    if (owner && owner != delegate) return;
    [self orderOut:nil];
    self.toolbarDelegate = nil;
}
- (void)toggleInputMode:(id)sender { (void)sender; [self.toolbarDelegate floatingToolbarDidRequestToggleInputMode:self]; }
- (void)togglePunctuation:(id)sender { (void)sender; [self.toolbarDelegate floatingToolbarDidRequestTogglePunctuation:self]; }
- (void)toggleFullWidth:(id)sender { (void)sender; [self.toolbarDelegate floatingToolbarDidRequestToggleFullWidth:self]; }
- (void)toggleTraditionalOutput:(id)sender { (void)sender; [self.toolbarDelegate floatingToolbarDidRequestToggleTraditionalOutput:self]; }
- (void)openSettings:(id)sender { (void)sender; [self.toolbarDelegate floatingToolbarDidRequestOpenSettings:self]; }
- (void)openCharacterPalette:(id)sender { (void)sender; [self.toolbarDelegate floatingToolbarDidRequestOpenCharacterPalette:self]; }
- (void)checkForUpdates:(id)sender { (void)sender; [self.toolbarDelegate floatingToolbarDidRequestCheckForUpdates:self]; }
- (void)openWebsite:(id)sender { (void)sender; [self.toolbarDelegate floatingToolbarDidRequestOpenWebsite:self]; }
- (void)dismissFloatingToolbar:(id)sender { (void)sender; [self.toolbarDelegate floatingToolbarDidRequestHide:self]; }
- (void)showUtilityMenu:(NSButton *)sender {
    NSMenu *menu = CreateMSIMEFloatingToolbarUtilityMenu(self);
    [menu popUpMenuPositioningItem:nil atLocation:NSMakePoint(NSMinX(sender.bounds), NSMaxY(sender.bounds) + 4.0) inView:sender];
}
@end
