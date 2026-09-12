#import "InputModeHUDPanel.h"

#import <cmath>

namespace
{
// A capsule rather than a square: the logo and the character sit side by side, the way the badge on
// a toolbar would carry them.
constexpr CGFloat kPanelWidth = 100.0;
constexpr CGFloat kPanelHeight = 56.0;
constexpr CGFloat kLogoSide = 30.0;
constexpr CGFloat kContentSpacing = 6.0;
constexpr CGFloat kCornerRadius = 16.0;
constexpr CGFloat kScreenMargin = 8.0;
constexpr CGFloat kCaretGap = 10.0;
// Long enough to be read at a glance, short enough that it is gone before the next word is typed.
constexpr NSTimeInterval kVisibleDuration = 0.6;
constexpr NSTimeInterval kFadeDuration = 0.18;

CGFloat Clamp(CGFloat value, CGFloat minimum, CGFloat maximum)
{
    if (maximum < minimum)
    {
        return minimum;
    }
    return value < minimum ? minimum : (value > maximum ? maximum : value);
}
} // namespace

NSColor *MetasequoiaForestColor(void)
{
    return [NSColor
          colorWithName:@"MetasequoiaForest"
        dynamicProvider:^NSColor *(NSAppearance *appearance) {
          const BOOL dark =
              [appearance bestMatchFromAppearancesWithNames:@[ NSAppearanceNameAqua, NSAppearanceNameDarkAqua ]] ==
              NSAppearanceNameDarkAqua;
          return dark ? [NSColor colorWithSRGBRed:97.0 / 255.0 green:180.0 / 255.0 blue:145.0 / 255.0 alpha:1.0]
                      : [NSColor colorWithSRGBRed:24.0 / 255.0 green:92.0 / 255.0 blue:72.0 / 255.0 alpha:1.0];
        }];
}

NSColor *MetasequoiaOnForestColor(void)
{
    return [NSColor
          colorWithName:@"MetasequoiaOnForest"
        dynamicProvider:^NSColor *(NSAppearance *appearance) {
          const BOOL dark =
              [appearance bestMatchFromAppearancesWithNames:@[ NSAppearanceNameAqua, NSAppearanceNameDarkAqua ]] ==
              NSAppearanceNameDarkAqua;
          // White reads 7.9:1 on the light green and 2.5:1 on the dark one, so the dark
          // shade takes ink instead. The pair comes from the iOS theme for that reason.
          return dark ? [NSColor colorWithSRGBRed:20.0 / 255.0 green:35.0 / 255.0 blue:29.0 / 255.0 alpha:1.0]
                      : [NSColor whiteColor];
        }];
}

NSString *MetasequoiaInputModeHUDText(BOOL englishInputMode)
{
    return englishInputMode ? @"英" : @"中";
}

BOOL MetasequoiaIsUsableCaretRect(NSRect caretRect)
{
    return std::isfinite(NSMinX(caretRect)) && std::isfinite(NSMinY(caretRect)) && std::isfinite(NSMaxX(caretRect)) &&
           std::isfinite(NSMaxY(caretRect)) && NSHeight(caretRect) > 0.0;
}

NSRect MetasequoiaInputModeHUDFrame(NSRect caretRect, NSSize panelSize, NSRect visibleFrame)
{
    const CGFloat minimumX = NSMinX(visibleFrame) + kScreenMargin;
    const CGFloat maximumX = NSMaxX(visibleFrame) - kScreenMargin - panelSize.width;
    const CGFloat minimumY = NSMinY(visibleFrame) + kScreenMargin;
    const CGFloat maximumY = NSMaxY(visibleFrame) - kScreenMargin - panelSize.height;

    if (!MetasequoiaIsUsableCaretRect(caretRect))
    {
        const CGFloat centredX = NSMidX(visibleFrame) - panelSize.width / 2.0;
        const CGFloat lowerThirdY = NSMinY(visibleFrame) + NSHeight(visibleFrame) / 4.0;
        return NSMakeRect(Clamp(centredX, minimumX, maximumX), Clamp(lowerThirdY, minimumY, maximumY), panelSize.width,
                          panelSize.height);
    }

    // Centred on the caret and below it, so it does not cover the line being typed. It goes above
    // only when there is no room underneath.
    const CGFloat x = Clamp(NSMidX(caretRect) - panelSize.width / 2.0, minimumX, maximumX);
    const CGFloat belowY = NSMinY(caretRect) - kCaretGap - panelSize.height;
    const CGFloat preferredY = belowY >= minimumY ? belowY : NSMaxY(caretRect) + kCaretGap;
    return NSMakeRect(x, Clamp(preferredY, minimumY, maximumY), panelSize.width, panelSize.height);
}

@implementation MetasequoiaInputModeHUDPanel
{
    NSTextField *_label;
    NSImageView *_logoView;
    NSTimer *_dismissTimer;
}

+ (instancetype)sharedPanel
{
    static MetasequoiaInputModeHUDPanel *panel = nil;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
      panel = [[MetasequoiaInputModeHUDPanel alloc] init];
    });
    return panel;
}

- (instancetype)init
{
    self = [super initWithContentRect:NSMakeRect(0.0, 0.0, kPanelWidth, kPanelHeight)
                            styleMask:(NSWindowStyleMaskBorderless | NSWindowStyleMaskNonactivatingPanel)
                              backing:NSBackingStoreBuffered
                                defer:YES];
    if (self == nil)
    {
        return nil;
    }

    self.floatingPanel = YES;
    self.level = NSPopUpMenuWindowLevel;
    self.becomesKeyOnlyIfNeeded = YES;
    self.hidesOnDeactivate = NO;
    self.opaque = NO;
    self.backgroundColor = [NSColor clearColor];
    self.hasShadow = YES;
    self.ignoresMouseEvents = YES;
    self.collectionBehavior = NSWindowCollectionBehaviorCanJoinAllSpaces |
                              NSWindowCollectionBehaviorFullScreenAuxiliary | NSWindowCollectionBehaviorTransient |
                              NSWindowCollectionBehaviorIgnoresCycle;
    self.animationBehavior = NSWindowAnimationBehaviorNone;

    NSView *background = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, kPanelWidth, kPanelHeight)];
    background.wantsLayer = YES;
    background.layer.cornerRadius = kCornerRadius;
    background.layer.masksToBounds = YES;
    background.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;

    // The logo is the menu icon, drawn as a template so it takes the ink colour rather than staying
    // black on green. Outside the app bundle there is no resource to find, and the badge then shows
    // the character on its own.
    NSImage *logo = [[NSBundle bundleForClass:[self class]] imageForResource:@"MetasequoiaIMEMenuIcon"];
    // `template` is a keyword here, so the setter is sent rather than assigned through dot syntax.
    [logo setTemplate:YES];
    _logoView = [NSImageView imageViewWithImage:logo != nil ? logo : [[NSImage alloc] initWithSize:NSZeroSize]];
    _logoView.hidden = logo == nil;
    _logoView.translatesAutoresizingMaskIntoConstraints = NO;

    _label = [NSTextField labelWithString:@""];
    _label.alignment = NSTextAlignmentCenter;
    _label.font = [NSFont systemFontOfSize:30.0 weight:NSFontWeightSemibold];
    _label.translatesAutoresizingMaskIntoConstraints = NO;

    NSStackView *content = [NSStackView stackViewWithViews:logo != nil ? @[ _logoView, _label ] : @[ _label ]];
    content.orientation = NSUserInterfaceLayoutOrientationHorizontal;
    content.alignment = NSLayoutAttributeCenterY;
    content.spacing = kContentSpacing;
    content.translatesAutoresizingMaskIntoConstraints = NO;

    [background addSubview:content];
    [NSLayoutConstraint activateConstraints:@[
        [content.centerXAnchor constraintEqualToAnchor:background.centerXAnchor],
        [content.centerYAnchor constraintEqualToAnchor:background.centerYAnchor],
        [_logoView.widthAnchor constraintEqualToConstant:kLogoSide],
        [_logoView.heightAnchor constraintEqualToConstant:kLogoSide],
    ]];

    self.contentView = background;
    [self applyThemeColors];
    return self;
}

// The dynamic colours resolve against the appearance in force when they are read, so the badge is
// repainted when the system flips between light and dark rather than keeping the shade it was born
// with.
- (void)applyThemeColors
{
    [self.effectiveAppearance performAsCurrentDrawingAppearance:^{
      self.contentView.layer.backgroundColor = MetasequoiaForestColor().CGColor;
      self->_label.textColor = MetasequoiaOnForestColor();
      self->_logoView.contentTintColor = MetasequoiaOnForestColor();
    }];
}

- (BOOL)showsLogo
{
    return !_logoView.hidden;
}

- (NSString *)displayedText
{
    return self.isVisible ? _label.stringValue : nil;
}

- (void)showEnglishInputMode:(BOOL)englishInputMode nearCaretRect:(NSRect)caretRect
{
    _label.stringValue = MetasequoiaInputModeHUDText(englishInputMode);
    // The badge announces a state the user just chose, so it is spoken rather than left to be found.
    NSAccessibilityPostNotificationWithUserInfo(
        self, NSAccessibilityAnnouncementRequestedNotification,
        @{NSAccessibilityAnnouncementKey : englishInputMode ? @"英文输入" : @"中文输入"});

    NSScreen *screen = [NSScreen screens].firstObject;
    for (NSScreen *candidate in [NSScreen screens])
    {
        if (NSPointInRect(NSMakePoint(NSMidX(caretRect), NSMidY(caretRect)), candidate.frame))
        {
            screen = candidate;
            break;
        }
    }
    const NSRect visibleFrame = screen != nil ? screen.visibleFrame : NSMakeRect(0, 0, 1440, 900);
    [self setFrame:MetasequoiaInputModeHUDFrame(caretRect, NSMakeSize(kPanelWidth, kPanelHeight), visibleFrame)
           display:YES];
    [self applyThemeColors];

    [_dismissTimer invalidate];
    self.alphaValue = 1.0;
    [self orderFrontRegardless];

    __weak MetasequoiaInputModeHUDPanel *weakSelf = self;
    _dismissTimer = [NSTimer scheduledTimerWithTimeInterval:kVisibleDuration
                                                    repeats:NO
                                                      block:^(NSTimer *timer) {
                                                        (void)timer;
                                                        [weakSelf fadeOut];
                                                      }];
}

- (void)fadeOut
{
    [NSAnimationContext
        runAnimationGroup:^(NSAnimationContext *context) {
          context.duration = kFadeDuration;
          self.animator.alphaValue = 0.0;
        }
        completionHandler:^{
          // A switch during the fade has already raised the alpha again; hiding here would undo it.
          if (self.alphaValue <= 0.01)
          {
              [self orderOut:nil];
          }
        }];
}

@end
