#pragma once

#import <AppKit/AppKit.h>

// The shared building blocks of the settings window: the metrics, the cards, and the label/control
// row. They live here rather than in AppearancePreferences.mm because pages built elsewhere — the
// voice form is the first — have to look like the pages built there, and a second copy of "what a
// preference row is" drifts from the first the moment either is touched.
//
// Header-only on purpose: the macOS target lists its sources explicitly and every test executable
// repeats that list, so a new .mm would have to be added to a dozen of them.

namespace msime::mac::layout {
inline constexpr CGFloat kSidebarWidth = 204.0;
inline constexpr CGFloat kSidebarRowHeight = 28.0;
/// The titlebar is transparent and the sidebar runs the full height behind it, so its own content
/// starts below the traffic lights.
inline constexpr CGFloat kSidebarTopInset = 46.0;
inline constexpr CGFloat kRowHeight = 30.0;
inline constexpr CGFloat kBodyFontSize = 13.0;
inline constexpr CGFloat kCardRadius = 8.0;
inline constexpr CGFloat kCardInsetH = 12.0;
inline constexpr CGFloat kCardInsetV = 6.0;
inline constexpr CGFloat kPageMargin = 22.0;
inline constexpr CGFloat kControlWidth = 190.0;
/// Rows whose control column is a cluster — a field beside a colour well, a popup beside three
/// buttons — rather than one popup.
inline constexpr CGFloat kWideControlWidth = 300.0;
}  // namespace msime::mac::layout

static inline void MSIMEConfigureCard(NSBox *card) {
    card.boxType = NSBoxCustom;
    card.titlePosition = NSNoTitle;
    card.borderWidth = 0.5;
    card.cornerRadius = msime::mac::layout::kCardRadius;
    card.borderColor = [NSColor separatorColor];
    card.fillColor = [NSColor controlBackgroundColor];
    card.translatesAutoresizingMaskIntoConstraints = NO;
}

static inline NSTextField *MSIMESectionLabel(NSString *title) {
    NSTextField *label = [NSTextField labelWithString:title];
    label.font = [NSFont systemFontOfSize:msime::mac::layout::kBodyFontSize weight:NSFontWeightSemibold];
    label.textColor = [NSColor labelColor];
    return label;
}

static inline NSView *MSIMEPreferenceRowOfWidth(NSString *title, NSView *control, CGFloat controlWidth) {
    NSView *row = [[NSView alloc] initWithFrame:NSZeroRect];
    NSTextField *label = [NSTextField labelWithString:title];
    label.font = [NSFont systemFontOfSize:msime::mac::layout::kBodyFontSize weight:NSFontWeightRegular];
    label.translatesAutoresizingMaskIntoConstraints = NO;
    control.translatesAutoresizingMaskIntoConstraints = NO;
    [row addSubview:label];
    [row addSubview:control];
    NSMutableArray<NSLayoutConstraint *> *constraints = [NSMutableArray arrayWithArray:@[
        [row.heightAnchor constraintGreaterThanOrEqualToConstant:msime::mac::layout::kRowHeight],
        [label.leadingAnchor constraintEqualToAnchor:row.leadingAnchor],
        [label.centerYAnchor constraintEqualToAnchor:row.centerYAnchor],
        [label.trailingAnchor constraintLessThanOrEqualToAnchor:control.leadingAnchor constant:-12.0],
        [control.trailingAnchor constraintEqualToAnchor:row.trailingAnchor],
        [control.centerYAnchor constraintEqualToAnchor:row.centerYAnchor],
        [control.topAnchor constraintGreaterThanOrEqualToAnchor:row.topAnchor constant:4.0],
        [control.bottomAnchor constraintLessThanOrEqualToAnchor:row.bottomAnchor constant:-4.0],
    ]];
    // A switch is its own intrinsic size; pinning it to the control column would stretch its track.
    if (![control isKindOfClass:NSSwitch.class])
        [constraints addObject:[control.widthAnchor constraintEqualToConstant:controlWidth]];
    // The row is the standard height unless its control does not fit in it — a push button is
    // taller than a popup — in which case the required margins above win and the row grows.
    NSLayoutConstraint *preferred = [row.heightAnchor constraintEqualToConstant:msime::mac::layout::kRowHeight];
    preferred.priority = NSLayoutPriorityDefaultLow;
    [constraints addObject:preferred];
    [NSLayoutConstraint activateConstraints:constraints];
    return row;
}

static inline NSView *MSIMEPreferenceRow(NSString *title, NSView *control) {
    return MSIMEPreferenceRowOfWidth(title, control, msime::mac::layout::kControlWidth);
}

/// A setting that takes effect the moment it is flipped, which is what AppKit puts a switch on.
/// Checkboxes stay where they belong — the multiple-choice groups (fuzzy rules, toolbar
/// components, extended input modes), where the boxes are peers of one another.
static inline NSSwitch *MSIMESettingSwitch(id target, SEL action, NSString *accessibilityLabel) {
    NSSwitch *toggle = [[NSSwitch alloc] initWithFrame:NSZeroRect];
    toggle.target = target;
    toggle.action = action;
    toggle.accessibilityLabel = accessibilityLabel;
    return toggle;
}

static inline NSView *MSIMESwitchRow(NSString *title, NSSwitch *toggle, NSString *tooltip) {
    NSView *row = MSIMEPreferenceRow(title, toggle);
    row.toolTip = tooltip;
    return row;
}

/// Peer checkboxes in columns. Eleven fuzzy-pinyin rules stacked vertically is most of a page of
/// scrolling for one card, and they are alternatives to one another, so the second column costs
/// nothing to read.
static inline NSView *MSIMECheckboxGrid(NSArray<NSButton *> *boxes, NSInteger columns) {
    NSMutableArray<NSArray<NSView *> *> *rows = [NSMutableArray array];
    for (NSUInteger index = 0; index < boxes.count; index += (NSUInteger)columns) {
        NSMutableArray<NSView *> *row = [NSMutableArray array];
        for (NSInteger column = 0; column < columns; ++column) {
            const NSUInteger position = index + (NSUInteger)column;
            [row addObject:position < boxes.count ? (NSView *)boxes[position] : [NSGridCell emptyContentView]];
        }
        [rows addObject:row];
    }
    NSGridView *grid = [NSGridView gridViewWithViews:rows];
    grid.rowSpacing = 7.0;
    grid.columnSpacing = 18.0;
    grid.translatesAutoresizingMaskIntoConstraints = NO;
    for (NSInteger column = 0; column < columns; ++column)
        [grid columnAtIndex:column].xPlacement = NSGridCellPlacementLeading;
    return grid;
}

static inline NSView *MSIMECardHeader(NSString *title) {
    NSView *row = [[NSView alloc] initWithFrame:NSZeroRect];
    NSTextField *label = [NSTextField labelWithString:title];
    label.font = [NSFont systemFontOfSize:msime::mac::layout::kBodyFontSize weight:NSFontWeightSemibold];
    label.textColor = [NSColor secondaryLabelColor];
    label.accessibilityLabel = [title stringByAppendingString:@"标题"];
    label.translatesAutoresizingMaskIntoConstraints = NO;
    [row addSubview:label];
    [NSLayoutConstraint activateConstraints:@[
        [row.heightAnchor constraintEqualToConstant:26.0],
        [label.leadingAnchor constraintEqualToAnchor:row.leadingAnchor],
        [label.centerYAnchor constraintEqualToAnchor:row.centerYAnchor],
    ]];
    return row;
}

static inline NSBox *MSIMECardSeparator(void) {
    NSBox *separator = [[NSBox alloc] initWithFrame:NSZeroRect];
    separator.boxType = NSBoxSeparator;
    separator.translatesAutoresizingMaskIntoConstraints = NO;
    [separator.heightAnchor constraintEqualToConstant:1.0].active = YES;
    return separator;
}

static inline NSBox *MSIMECardWithViews(NSArray<NSView *> *views, CGFloat spacing) {
    NSBox *card = [[NSBox alloc] initWithFrame:NSZeroRect];
    MSIMEConfigureCard(card);
    NSStackView *stack = [NSStackView stackViewWithViews:views];
    stack.orientation = NSUserInterfaceLayoutOrientationVertical;
    stack.alignment = NSLayoutAttributeLeading;
    stack.distribution = NSStackViewDistributionFill;
    stack.spacing = spacing;
    stack.translatesAutoresizingMaskIntoConstraints = NO;
    for (NSView *view in views) [view.widthAnchor constraintEqualToAnchor:stack.widthAnchor].active = YES;
    [card addSubview:stack];
    [NSLayoutConstraint activateConstraints:@[
        [stack.leadingAnchor constraintEqualToAnchor:card.leadingAnchor constant:msime::mac::layout::kCardInsetH],
        [stack.trailingAnchor constraintEqualToAnchor:card.trailingAnchor constant:-msime::mac::layout::kCardInsetH],
        [stack.topAnchor constraintEqualToAnchor:card.topAnchor constant:msime::mac::layout::kCardInsetV],
        [stack.bottomAnchor constraintEqualToAnchor:card.bottomAnchor constant:-msime::mac::layout::kCardInsetV],
    ]];
    return card;
}

static inline void MSIMELinkifyButton(NSButton *button, NSString *accessibilityLabel) {
    button.bezelStyle = NSBezelStyleInline;
    // Inline bezels draw a grey capsule behind the text. These rows are links, not buttons, so the
    // capsule reads as a control that is not there.
    button.bordered = NO;
    button.accessibilityLabel = accessibilityLabel;
    button.contentTintColor = [NSColor linkColor];
    button.attributedTitle = [[NSAttributedString alloc]
        initWithString:button.title
            attributes:@{
                NSFontAttributeName : [NSFont systemFontOfSize:msime::mac::layout::kBodyFontSize weight:NSFontWeightMedium],
                NSForegroundColorAttributeName : [NSColor linkColor],
            }];
}
