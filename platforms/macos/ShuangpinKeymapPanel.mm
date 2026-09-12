#import "ShuangpinKeymapPanel.h"
// Migrated from MSIME-Apple b637828e15eafcb5e459edd270a962dd14517285.

#include "ShuangpinProfileNames.h"
#include "shuangpin/shuangpin_profile.h"

namespace
{
constexpr CGFloat kPanelWidth = 620.0;
constexpr CGFloat kPanelHeight = 203.0;
constexpr CGFloat kScreenMargin = 16.0;

NSDictionary<NSString *, NSString *> *Key(NSString *key, NSString *codes)
{
    return @{@"key" : key, @"codes" : codes};
}

NSString *DisplayUnit(const std::string &unit)
{
    if (!unit.empty() && unit.front() == 'v')
    {
        return [@"ü" stringByAppendingString:[NSString stringWithUTF8String:unit.c_str() + 1]];
    }
    return [NSString stringWithUTF8String:unit.c_str()];
}

void AppendProfileUnits(const std::unordered_map<std::string, std::string> &mapping,
                        NSMutableDictionary<NSString *, NSMutableArray<NSString *> *> *unitsByKey)
{
    for (const auto &entry : mapping)
    {
        NSString *key = [NSString stringWithUTF8String:entry.second.c_str()].uppercaseString;
        if (unitsByKey[key] == nil)
        {
            unitsByKey[key] = [NSMutableArray array];
        }
        [unitsByKey[key] addObject:DisplayUnit(entry.first)];
    }
}

NSString *CodesForKey(NSString *key, NSDictionary<NSString *, NSMutableArray<NSString *> *> *initialsByKey,
                      NSDictionary<NSString *, NSMutableArray<NSString *> *> *finalsByKey)
{
    NSArray<NSString *> *initials = [initialsByKey[key] sortedArrayUsingSelector:@selector(compare:)];
    NSArray<NSString *> *finals = [finalsByKey[key] sortedArrayUsingSelector:@selector(compare:)];
    NSString *initialText = [initials componentsJoinedByString:@" · "];
    NSString *finalText = [finals componentsJoinedByString:@" · "];
    if (initialText.length > 0 && finalText.length > 0)
    {
        return [NSString stringWithFormat:@"%@ / %@", initialText, finalText];
    }
    return initialText.length > 0 ? initialText : finalText;
}

NSArray<NSDictionary<NSString *, NSString *> *> *KeyDefinitions(
    NSArray<NSString *> *keys, NSDictionary<NSString *, NSMutableArray<NSString *> *> *initialsByKey,
    NSDictionary<NSString *, NSMutableArray<NSString *> *> *finalsByKey)
{
    NSMutableArray<NSDictionary<NSString *, NSString *> *> *definitions = [NSMutableArray arrayWithCapacity:keys.count];
    for (NSString *key in keys)
    {
        [definitions addObject:Key(key, CodesForKey(key, initialsByKey, finalsByKey))];
    }
    return definitions;
}

CGFloat Clamp(CGFloat value, CGFloat minimum, CGFloat maximum)
{
    if (maximum < minimum)
    {
        return minimum;
    }
    return MIN(MAX(value, minimum), maximum);
}

CGFloat KeyRowInset(NSUInteger count)
{
    if (count >= 10)
    {
        return 14.0;
    }
    if (count == 9)
    {
        return 31.0;
    }
    return 58.0;
}

NSColor *KeymapAccentColor()
{
    return [NSColor colorWithName:@"MSIMEKeymapAccentColor"
                  dynamicProvider:^NSColor *(NSAppearance *appearance) {
                    NSString *match = [appearance
                        bestMatchFromAppearancesWithNames:@[ NSAppearanceNameAqua, NSAppearanceNameDarkAqua ]];
                    if ([match isEqualToString:NSAppearanceNameDarkAqua])
                    {
                        return [NSColor colorWithSRGBRed:0.16 green:0.58 blue:0.54 alpha:1.0];
                    }
                    return [NSColor colorWithSRGBRed:0.07 green:0.49 blue:0.45 alpha:1.0];
                  }];
}
} // namespace

@interface MSIMEShuangpinKeyView : NSView
@property(nonatomic, copy) NSString *key;
@property(nonatomic, copy) NSString *codes;
@property(nonatomic) BOOL highlighted;
@end

@implementation MSIMEShuangpinKeyView

- (BOOL)isFlipped
{
    return YES;
}

- (void)setHighlighted:(BOOL)highlighted
{
    if (_highlighted == highlighted)
    {
        return;
    }
    _highlighted = highlighted;
    self.needsDisplay = YES;
}

- (void)drawRect:(NSRect)dirtyRect
{
    (void)dirtyRect;
    NSRect keyRect = NSInsetRect(self.bounds, 0.5, 0.5);
    NSBezierPath *keyPath = [NSBezierPath bezierPathWithRoundedRect:keyRect xRadius:7.0 yRadius:7.0];
    NSColor *fillColor = self.highlighted ? KeymapAccentColor() : [NSColor controlBackgroundColor];
    [fillColor setFill];
    [keyPath fill];
    NSColor *borderColor = self.highlighted ? [[NSColor whiteColor] colorWithAlphaComponent:0.28]
                                            : [[NSColor separatorColor] colorWithAlphaComponent:0.62];
    [borderColor setStroke];
    keyPath.lineWidth = 1.0;
    [keyPath stroke];

    NSColor *primaryColor = self.highlighted ? [NSColor whiteColor] : [NSColor labelColor];
    NSColor *secondaryColor =
        self.highlighted ? [[NSColor whiteColor] colorWithAlphaComponent:0.86] : [NSColor secondaryLabelColor];
    NSFont *keyFont = [NSFont monospacedSystemFontOfSize:11.0 weight:NSFontWeightBold]
        ?: [NSFont systemFontOfSize:11.0 weight:NSFontWeightBold];
    NSDictionary<NSAttributedStringKey, id> *keyAttributes = @{
        NSFontAttributeName : keyFont,
        NSForegroundColorAttributeName : primaryColor,
    };
    NSDictionary<NSAttributedStringKey, id> *codeAttributes = @{
        NSFontAttributeName : [NSFont systemFontOfSize:9.0 weight:NSFontWeightMedium],
        NSForegroundColorAttributeName : secondaryColor,
    };
    [self.key drawAtPoint:NSMakePoint(7.0, 4.0) withAttributes:keyAttributes];
    NSSize codeSize = [self.codes sizeWithAttributes:codeAttributes];
    [self.codes drawAtPoint:NSMakePoint(NSMidX(self.bounds) - (codeSize.width / 2.0),
                                        NSHeight(self.bounds) - codeSize.height - 4.0)
             withAttributes:codeAttributes];
}

@end

namespace
{

NSStackView *KeyRow(NSArray<NSDictionary<NSString *, NSString *> *> *definitions,
                    NSMutableArray<MSIMEShuangpinKeyView *> *keyViews)
{
    NSMutableArray<NSView *> *views = [NSMutableArray arrayWithCapacity:definitions.count];
    for (NSDictionary<NSString *, NSString *> *definition in definitions)
    {
        MSIMEShuangpinKeyView *view = [[MSIMEShuangpinKeyView alloc] initWithFrame:NSZeroRect];
        view.key = definition[@"key"];
        view.codes = definition[@"codes"];
        view.accessibilityRole = NSAccessibilityStaticTextRole;
        view.accessibilityLabel = view.key;
        view.accessibilityValue = view.codes;
        [keyViews addObject:view];
        [views addObject:view];
    }
    NSStackView *row = [NSStackView stackViewWithViews:views];
    row.orientation = NSUserInterfaceLayoutOrientationHorizontal;
    row.distribution = NSStackViewDistributionFillEqually;
    row.spacing = 5.0;
    row.translatesAutoresizingMaskIntoConstraints = NO;
    [row.heightAnchor constraintEqualToConstant:38.0].active = YES;
    return row;
}

NSString *AccessibleKeymapDescription(NSArray<MSIMEShuangpinKeyView *> *keyViews, NSString *highlightedKey)
{
    NSMutableArray<NSString *> *definitions = [NSMutableArray arrayWithCapacity:keyViews.count];
    NSString *highlightedDescription = nil;
    for (MSIMEShuangpinKeyView *view in keyViews)
    {
        NSString *definition = [NSString stringWithFormat:@"%@：%@", view.key, view.codes];
        [definitions addObject:definition];
        if ([view.key isEqualToString:highlightedKey])
        {
            highlightedDescription = definition;
        }
    }
    NSString *description = [definitions componentsJoinedByString:@"，"];
    return highlightedDescription == nil
               ? description
               : [description stringByAppendingFormat:@"；当前按键 %@", highlightedDescription];
}
} // namespace

NSArray<NSArray<NSDictionary<NSString *, NSString *> *> *> *MSIMEShuangpinKeymapRows(NSString *profileName)
{
    const ShuangpinProfile &profile = GetShuangpinProfile(
        msime::mac::NormalizeShuangpinSchema(profileName.UTF8String != nullptr ? profileName.UTF8String : ""));
    NSMutableDictionary<NSString *, NSMutableArray<NSString *> *> *initialsByKey = [NSMutableDictionary dictionary];
    NSMutableDictionary<NSString *, NSMutableArray<NSString *> *> *finalsByKey = [NSMutableDictionary dictionary];
    AppendProfileUnits(profile.initials, initialsByKey);
    AppendProfileUnits(profile.finals, finalsByKey);
    NSMutableArray<NSString *> *homeKeys = [@[ @"A", @"S", @"D", @"F", @"G", @"H", @"J", @"K", @"L" ] mutableCopy];
    if (initialsByKey[@";"].count > 0 || finalsByKey[@";"].count > 0)
    {
        [homeKeys addObject:@";"];
    }
    return @[
        KeyDefinitions(@[ @"Q", @"W", @"E", @"R", @"T", @"Y", @"U", @"I", @"O", @"P" ], initialsByKey, finalsByKey),
        KeyDefinitions(homeKeys, initialsByKey, finalsByKey),
        KeyDefinitions(@[ @"Z", @"X", @"C", @"V", @"B", @"N", @"M" ], initialsByKey, finalsByKey),
    ];
}

NSString *MSIMEShuangpinZeroInitialText(NSString *profileName)
{
    const ShuangpinProfile &profile = GetShuangpinProfile(
        msime::mac::NormalizeShuangpinSchema(profileName.UTF8String != nullptr ? profileName.UTF8String : ""));
    NSMutableArray<NSString *> *entries = [NSMutableArray arrayWithCapacity:profile.zero_initials.size()];
    for (const auto &entry : profile.zero_initials)
    {
        [entries addObject:[NSString stringWithFormat:@"%@=%@", DisplayUnit(entry.first),
                                                      [NSString stringWithUTF8String:entry.second.c_str()]]];
    }
    [entries sortUsingSelector:@selector(compare:)];
    return [@"零声母  " stringByAppendingString:[entries componentsJoinedByString:@" · "]];
}

BOOL MSIMEShouldShowShuangpinKeymap(BOOL isShuangpin, BOOL enabled, BOOL hasComposition)
{
    return isShuangpin && enabled && hasComposition;
}

NSString *MSIMEShuangpinKeymapEditingText(NSDictionary *view)
{
    id editing = view[@"editing_text"];
    return [editing isKindOfClass:NSString.class] ? editing : @"";
}

NSString *MSIMEShuangpinKeymapHighlightedKey(NSDictionary *view)
{
    NSString *editing = MSIMEShuangpinKeymapEditingText(view);
    if (editing.length == 0) return @"";
    const unichar last = [editing characterAtIndex:editing.length - 1];
    if ((last >= 'a' && last <= 'z') || (last >= 'A' && last <= 'Z') || last == ';') {
        return [NSString stringWithCharacters:&last length:1];
    }
    return @"";
}

NSRect MSIMEShuangpinKeymapPanelFrame(NSRect caretRect, NSSize panelSize, CGFloat candidateClearance,
                                            NSRect visibleFrame)
{
    const CGFloat minimumX = NSMinX(visibleFrame) + kScreenMargin;
    const CGFloat maximumX = NSMaxX(visibleFrame) - kScreenMargin - panelSize.width;
    const CGFloat x = Clamp(NSMinX(caretRect), minimumX, maximumX);

    const CGFloat minimumY = NSMinY(visibleFrame) + kScreenMargin;
    const CGFloat maximumY = NSMaxY(visibleFrame) - kScreenMargin - panelSize.height;
    const CGFloat belowY = NSMinY(caretRect) - candidateClearance - 8.0 - panelSize.height;
    const CGFloat preferredY = belowY >= minimumY ? belowY : NSMaxY(caretRect) + candidateClearance + 8.0;
    const CGFloat y = Clamp(preferredY, minimumY, maximumY);
    return NSMakeRect(x, y, panelSize.width, panelSize.height);
}

@implementation MSIMEShuangpinKeymapPanel
{
    NSMutableArray<MSIMEShuangpinKeyView *> *_keyViews;
    NSString *_profileName;
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
    self.animationBehavior = NSWindowAnimationBehaviorUtilityWindow;
    [self setProfileName:@"xiaohe"];
    return self;
}

- (void)setProfileName:(NSString *)profileName
{
    NSString *normalized =
        @(msime::mac::NormalizeShuangpinSchema(profileName.UTF8String != nullptr ? profileName.UTF8String : ""));
    if ([_profileName isEqualToString:normalized] && _keyViews.count > 0)
    {
        return;
    }
    _profileName = [normalized copy];

    NSVisualEffectView *background = [[NSVisualEffectView alloc] initWithFrame:NSZeroRect];
    background.material = NSVisualEffectMaterialPopover;
    background.blendingMode = NSVisualEffectBlendingModeBehindWindow;
    background.state = NSVisualEffectStateActive;
    background.wantsLayer = YES;
    background.layer.cornerRadius = 13.0;
    background.layer.masksToBounds = YES;
    background.accessibilityRole = NSAccessibilityGroupRole;
    NSString *schemaTitle =
        @(msime::mac::ShuangpinSchemaTitle(_profileName.UTF8String != nullptr ? _profileName.UTF8String : ""));
    background.accessibilityLabel = [schemaTitle stringByAppendingString:@"键位提示"];

    NSTextField *title = [NSTextField labelWithString:[schemaTitle stringByAppendingString:@"键位"]];
    title.font = [NSFont systemFontOfSize:12.0 weight:NSFontWeightSemibold];
    NSTextField *hint = [NSTextField labelWithString:@"当前按键会高亮 · 上屏后自动隐藏"];
    hint.font = [NSFont systemFontOfSize:10.0 weight:NSFontWeightRegular];
    hint.textColor = [NSColor secondaryLabelColor];
    NSStackView *header = [NSStackView stackViewWithViews:@[ title, hint ]];
    header.orientation = NSUserInterfaceLayoutOrientationHorizontal;
    header.alignment = NSLayoutAttributeCenterY;
    header.distribution = NSStackViewDistributionEqualSpacing;
    header.translatesAutoresizingMaskIntoConstraints = NO;

    _keyViews = [NSMutableArray arrayWithCapacity:27];
    NSArray<NSArray<NSDictionary<NSString *, NSString *> *> *> *definitions =
        MSIMEShuangpinKeymapRows(_profileName);
    NSStackView *topRow = KeyRow(definitions[0], _keyViews);
    NSStackView *homeRow = KeyRow(definitions[1], _keyViews);
    NSStackView *bottomRow = KeyRow(definitions[2], _keyViews);
    const CGFloat homeInset = KeyRowInset(definitions[1].count);
    const CGFloat bottomInset = KeyRowInset(definitions[2].count);

    NSTextField *zeroInitials = [NSTextField labelWithString:MSIMEShuangpinZeroInitialText(_profileName)];
    zeroInitials.font = [NSFont systemFontOfSize:10.0 weight:NSFontWeightRegular];
    zeroInitials.textColor = [NSColor secondaryLabelColor];
    zeroInitials.alignment = NSTextAlignmentCenter;
    zeroInitials.maximumNumberOfLines = 1;
    zeroInitials.accessibilityLabel = @"零声母键位";
    zeroInitials.translatesAutoresizingMaskIntoConstraints = NO;

    [background addSubview:header];
    [background addSubview:topRow];
    [background addSubview:homeRow];
    [background addSubview:bottomRow];
    [background addSubview:zeroInitials];
    [NSLayoutConstraint activateConstraints:@[
        [header.leadingAnchor constraintEqualToAnchor:background.leadingAnchor constant:14.0],
        [header.trailingAnchor constraintEqualToAnchor:background.trailingAnchor constant:-14.0],
        [header.topAnchor constraintEqualToAnchor:background.topAnchor constant:10.0],
        [topRow.leadingAnchor constraintEqualToAnchor:background.leadingAnchor constant:14.0],
        [topRow.trailingAnchor constraintEqualToAnchor:background.trailingAnchor constant:-14.0],
        [topRow.topAnchor constraintEqualToAnchor:header.bottomAnchor constant:7.0],
        [homeRow.leadingAnchor constraintEqualToAnchor:background.leadingAnchor constant:homeInset],
        [homeRow.trailingAnchor constraintEqualToAnchor:background.trailingAnchor constant:-homeInset],
        [homeRow.topAnchor constraintEqualToAnchor:topRow.bottomAnchor constant:5.0],
        [bottomRow.leadingAnchor constraintEqualToAnchor:background.leadingAnchor constant:bottomInset],
        [bottomRow.trailingAnchor constraintEqualToAnchor:background.trailingAnchor constant:-bottomInset],
        [bottomRow.topAnchor constraintEqualToAnchor:homeRow.bottomAnchor constant:5.0],
        [zeroInitials.leadingAnchor constraintEqualToAnchor:background.leadingAnchor constant:14.0],
        [zeroInitials.trailingAnchor constraintEqualToAnchor:background.trailingAnchor constant:-14.0],
        [zeroInitials.topAnchor constraintEqualToAnchor:bottomRow.bottomAnchor constant:6.0],
        [zeroInitials.heightAnchor constraintEqualToConstant:13.0],
        [zeroInitials.bottomAnchor constraintEqualToAnchor:background.bottomAnchor constant:-10.0],
    ]];
    background.accessibilityValue = AccessibleKeymapDescription(_keyViews, nil);
    self.contentView = background;
}

- (void)updateHighlightedKey:(NSString *)key
{
    NSString *normalizedKey = key.length == 1 ? key.uppercaseString : @"";
    for (MSIMEShuangpinKeyView *view in _keyViews)
    {
        view.highlighted = [view.key isEqualToString:normalizedKey];
    }
    self.contentView.accessibilityValue = AccessibleKeymapDescription(_keyViews, normalizedKey);
}

- (void)showNearCaretRect:(NSRect)caretRect candidateClearance:(CGFloat)candidateClearance
{
    NSScreen *targetScreen = nil;
    NSPoint caretPoint = NSMakePoint(NSMidX(caretRect), NSMidY(caretRect));
    for (NSScreen *screen in NSScreen.screens)
    {
        if (NSPointInRect(caretPoint, screen.frame))
        {
            targetScreen = screen;
            break;
        }
    }
    if (targetScreen == nil)
    {
        targetScreen = NSScreen.mainScreen;
    }
    if (targetScreen == nil)
    {
        [self orderOut:nil];
        return;
    }
    NSRect panelFrame = MSIMEShuangpinKeymapPanelFrame(caretRect, NSMakeSize(kPanelWidth, kPanelHeight),
                                                             candidateClearance, targetScreen.visibleFrame);
    [self setFrame:panelFrame display:NO];
    [self orderFrontRegardless];
}

@end
