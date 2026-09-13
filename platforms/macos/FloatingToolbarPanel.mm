#import "FloatingToolbarPanel.h"
#import "CandidateSkinAppearance.h"

#include <algorithm>
#include <cmath>

namespace
{
constexpr CGFloat kToolbarWidth = 422.0;
constexpr CGFloat kToolbarHeight = 44.0;
NSString *const kToolbarFrameAutosaveName = @"MetasequoiaFloatingToolbarFrame";

NSButton *ToolbarButton(NSString *title, NSString *identifier, id target, SEL action)
{
    NSButton *button = [NSButton buttonWithTitle:title target:target action:action];
    button.translatesAutoresizingMaskIntoConstraints = NO;
    button.bordered = NO;
    button.font = [NSFont systemFontOfSize:15.0 weight:NSFontWeightMedium];
    button.accessibilityIdentifier = identifier;
    NSLayoutConstraint *width = [button.widthAnchor constraintEqualToConstant:42.0];
    width.identifier = @"ToolbarButtonWidth";
    width.active = YES;
    NSLayoutConstraint *height = [button.heightAnchor constraintEqualToConstant:32.0];
    height.identifier = @"ToolbarButtonHeight";
    height.active = YES;
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

static NSRect SizedToolbarFrame(NSRect proposedFrame, NSRect visibleFrame, BOOL hasSavedFrame, NSSize size)
{
    constexpr CGFloat kDefaultMargin = 20.0;
    constexpr CGFloat kRestoredMargin = 12.0;
    proposedFrame.size = size;
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
    proposedFrame.origin.x = std::clamp(proposedFrame.origin.x, minimumX, std::max(minimumX, maximumX));
    proposedFrame.origin.y = std::clamp(proposedFrame.origin.y, minimumY, std::max(minimumY, maximumY));
    return proposedFrame;
}

NSRect MetasequoiaFloatingToolbarFrame(NSRect proposedFrame, NSRect visibleFrame, BOOL hasSavedFrame)
{
    return SizedToolbarFrame(proposedFrame, visibleFrame, hasSavedFrame, NSMakeSize(kToolbarWidth, kToolbarHeight));
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
    const CGFloat radius = self.layer.cornerRadius;
    NSBezierPath *path = [NSBezierPath bezierPathWithRoundedRect:self.bounds xRadius:radius yRadius:radius];
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
    NSButton *_emojiButton;
    NSButton *_handwritingButton;
    NSButton *_keyboardButton;
    NSButton *_voiceButton;
    NSButton *_settingsButton;
    NSStackView *_actions;
    NSLayoutConstraint *_leadingInset;
    NSLayoutConstraint *_trailingInset;
    NSSize _preferredSize;
    CGFloat _appliedScale;
    CGFloat _appliedFontSize;
    NSUInteger _appliedComponentMask;
    BOOL _hasHostSkin;
    msime::mac::SkinTokens _lightSkin;
    msime::mac::SkinTokens _darkSkin;
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
    _preferredSize = NSMakeSize(kToolbarWidth, kToolbarHeight);
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
    _emojiButton = ToolbarButton(@"", @"MetasequoiaFloatingToolbarEmoji", self, @selector(openEmoji:));
    _emojiButton.image = [NSImage imageWithSystemSymbolName:@"face.smiling" accessibilityDescription:@"表情"];
    _emojiButton.accessibilityLabel = @"打开水杉表情面板";
    _emojiButton.toolTip = _emojiButton.accessibilityLabel;
    _handwritingButton = ToolbarButton(@"", @"MetasequoiaFloatingToolbarHandwriting", self, @selector(openHandwriting:));
    _handwritingButton.image = [NSImage imageWithSystemSymbolName:@"hand.draw" accessibilityDescription:@"手写"];
    _handwritingButton.accessibilityLabel = @"打开水杉手写识别板";
    _handwritingButton.toolTip = _handwritingButton.accessibilityLabel;
    _keyboardButton = ToolbarButton(@"", @"MetasequoiaFloatingToolbarScreenKeyboard", self, @selector(openScreenKeyboard:));
    _keyboardButton.image = [NSImage imageWithSystemSymbolName:@"keyboard" accessibilityDescription:@"屏幕键盘"];
    _keyboardButton.accessibilityLabel = @"打开水杉屏幕键盘";
    _keyboardButton.toolTip = _keyboardButton.accessibilityLabel;
    _voiceButton = ToolbarButton(@"", @"MetasequoiaFloatingToolbarVoice", self, @selector(toggleVoice:));
    _voiceButton.image = [NSImage imageWithSystemSymbolName:@"mic.fill" accessibilityDescription:@"语音输入"];
    _voiceButton.accessibilityLabel = @"开始或结束语音输入";
    _voiceButton.toolTip = _voiceButton.accessibilityLabel;
    _settingsButton = ToolbarButton(@"", @"MetasequoiaFloatingToolbarSettings", self, @selector(showUtilityMenu:));
    _settingsButton.image = [NSImage imageWithSystemSymbolName:@"gearshape" accessibilityDescription:@"设置"];
    _settingsButton.accessibilityLabel = @"打开水杉输入法工具菜单";
    _settingsButton.toolTip = _settingsButton.accessibilityLabel;

    NSStackView *actions = [NSStackView stackViewWithViews:@[
        _inputModeButton, _punctuationButton, _fullWidthButton, _traditionalOutputButton, _emojiButton,
        _handwritingButton, _keyboardButton, _voiceButton, _settingsButton
    ]];
    actions.translatesAutoresizingMaskIntoConstraints = NO;
    actions.orientation = NSUserInterfaceLayoutOrientationHorizontal;
    actions.alignment = NSLayoutAttributeCenterY;
    actions.distribution = NSStackViewDistributionEqualSpacing;
    actions.spacing = 8.0;
    _actions = actions;
    [_chrome addSubview:actions];

    _leadingInset = [actions.leadingAnchor constraintEqualToAnchor:_chrome.leadingAnchor constant:10.0];
    _trailingInset = [actions.trailingAnchor constraintEqualToAnchor:_chrome.trailingAnchor constant:-10.0];
    [NSLayoutConstraint activateConstraints:@[
        _leadingInset,
        _trailingInset,
        [actions.centerYAnchor constraintEqualToAnchor:_chrome.centerYAnchor],
    ]];
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(applySkin)
                                                 name:MetasequoiaCandidateSkinDidChangeNotification
                                               object:nil];
    [self applySizingPreferences:@{}];
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

- (void)applySizingPreferences:(NSDictionary *)preferences
{
    id toolbar = preferences[@"floating_toolbar"];
    if (![toolbar isKindOfClass:NSDictionary.class]) toolbar = @{};
    id scaleValue = toolbar[@"scale_percent"] ?: @100;
    id fontValue = toolbar[@"font_size"] ?: @24;
    const CGFloat scale = [@[@75, @100, @125, @150] containsObject:scaleValue] ? [scaleValue doubleValue] / 100.0 : 1.0;
    const CGFloat fontSize = [@[@16, @18, @20, @22, @24, @26, @28] containsObject:fontValue] ? [fontValue doubleValue] : 24.0;
    NSArray<NSString *> *keys = @[@"punctuation", @"fullwidth", @"character_set", @"emoji", @"screen_keyboard", @"settings"];
    NSArray<NSButton *> *optionalButtons = @[_punctuationButton, _fullWidthButton, _traditionalOutputButton, _emojiButton, _keyboardButton, _settingsButton];
    NSUInteger mask = 0;
    NSUInteger count = 3; // Language switching, handwriting and voice are always present.
    for (NSUInteger index = 0; index < keys.count; ++index) {
        id value = toolbar[keys[index]];
        const BOOL defaultEnabled = ![keys[index] isEqualToString:@"screen_keyboard"];
        const BOOL enabled = [value isKindOfClass:NSNumber.class] ? [value boolValue] : defaultEnabled;
        if (enabled) { mask |= 1u << index; ++count; }
    }
    if (scale == _appliedScale && fontSize == _appliedFontSize && mask == _appliedComponentMask) return;
    _appliedScale = scale;
    _appliedFontSize = fontSize;
    _appliedComponentMask = mask;
    for (NSUInteger index = 0; index < optionalButtons.count; ++index)
        optionalButtons[index].hidden = (mask & (1u << index)) == 0;
    for (NSButton *button in @[_inputModeButton, _punctuationButton, _fullWidthButton, _traditionalOutputButton, _emojiButton, _handwritingButton, _keyboardButton, _voiceButton, _settingsButton]) {
        for (NSLayoutConstraint *constraint in button.constraints) {
            if (constraint.firstItem != button || constraint.secondItem != nil) continue;
            if ([constraint.identifier isEqualToString:@"ToolbarButtonWidth"]) constraint.constant = (fontSize + 18.0) * scale;
            if ([constraint.identifier isEqualToString:@"ToolbarButtonHeight"]) constraint.constant = (fontSize + 8.0) * scale;
        }
        button.font = [NSFont systemFontOfSize:fontSize * scale * 0.833 weight:NSFontWeightMedium];
    }
    _settingsButton.symbolConfiguration = [NSImageSymbolConfiguration configurationWithPointSize:fontSize * scale weight:NSFontWeightRegular];
    _emojiButton.symbolConfiguration = _settingsButton.symbolConfiguration;
    _handwritingButton.symbolConfiguration = _settingsButton.symbolConfiguration;
    _keyboardButton.symbolConfiguration = _settingsButton.symbolConfiguration;
    _voiceButton.symbolConfiguration = _settingsButton.symbolConfiguration;
    _actions.spacing = 8.0 * scale;
    _leadingInset.constant = 10.0 * scale;
    _trailingInset.constant = -10.0 * scale;
    _chrome.layer.cornerRadius = 10.0 * scale;
    // NSWindow rounds fractional point sizes; round outward so controls are never clipped.
    _preferredSize = NSMakeSize(std::ceil((count * (fontSize + 18.0) + (count - 1) * 8.0 + 30.0) * scale), std::ceil((fontSize + 20.0) * scale));
    NSRect frame = self.frame;
    frame.size = _preferredSize;
    NSScreen *screen = ScreenContainingFrame(frame) ?: NSScreen.mainScreen;
    if (screen) frame = SizedToolbarFrame(frame, screen.visibleFrame, YES, _preferredSize);
    [self setFrame:frame display:YES];
    [_chrome layoutSubtreeIfNeeded];
    [self applySkin];
}

- (void)applyThemePreferences:(NSDictionary *)preferences
{
    NSString *surface = preferences[@"toolbar_theme"];
    NSString *mode = preferences[@"theme"];
    NSString *resolved = ([surface isEqual:@"dark"] || [surface isEqual:@"light"]) ? surface : mode;
    if ([resolved isEqual:@"light"])
        self.appearance = [NSAppearance appearanceNamed:NSAppearanceNameAqua];
    else if ([resolved isEqual:@"system"])
        self.appearance = nil;
    else
        self.appearance = [NSAppearance appearanceNamed:NSAppearanceNameDarkAqua];
    [self applySkin];
}

- (void)applyLightSkin:(const msime::mac::SkinTokens &)light darkSkin:(const msime::mac::SkinTokens &)dark
{
    _lightSkin = light;
    _darkSkin = dark;
    _hasHostSkin = YES;
    [self applySkin];
}

- (void)applySkin
{
    if (_inputModeButton == nil || _settingsButton == nil)
    {
        return;
    }
    const BOOL dark = MetasequoiaAppearanceIsDark(_chrome.effectiveAppearance);
    const auto tokens = _hasHostSkin ? (dark ? _darkSkin : _lightSkin)
        : MetasequoiaResolveStoredCandidateSkin(dark).tokens;
    _chrome.fillColor = MetasequoiaColorFromRgba(tokens.surface);
    _chrome.strokeColor = MetasequoiaColorFromRgba(tokens.border);
    NSColor *text = MetasequoiaColorFromRgba(tokens.text);
    for (NSButton *button in
         @[ _inputModeButton, _punctuationButton, _fullWidthButton, _traditionalOutputButton, _emojiButton, _handwritingButton, _keyboardButton, _voiceButton, _settingsButton ])
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
        [self setFrame:SizedToolbarFrame(self.frame, screen.visibleFrame, hasSavedFrame, _preferredSize) display:NO];
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

- (void)openEmoji:(id)sender
{
    (void)sender;
    [self.toolbarDelegate floatingToolbarDidRequestOpenEmoji:self];
}

- (void)openHandwriting:(id)sender
{
    (void)sender;
    [self.toolbarDelegate floatingToolbarDidRequestOpenHandwriting:self];
}

- (void)openScreenKeyboard:(id)sender
{
    (void)sender;
    [self.toolbarDelegate floatingToolbarDidRequestOpenScreenKeyboard:self];
}

- (void)toggleVoice:(id)sender
{
    (void)sender;
    [self.toolbarDelegate floatingToolbarDidRequestToggleVoice:self];
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
