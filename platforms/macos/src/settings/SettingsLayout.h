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
/// The sidebar is draggable between these two, which is why it is a range rather than a width: the
/// system sidebar the window now uses is resizable and the widest item — 悬浮工具栏 — has to fit
/// without an ellipsis. The upper bound is also what the window's minimum width is derived from,
/// so that the body column never falls under kContentColumnMin.
inline constexpr CGFloat kSidebarWidth = 204.0;
inline constexpr CGFloat kSidebarMaxWidth = 240.0;
inline constexpr CGFloat kSidebarRowHeight = 28.0;
inline constexpr CGFloat kRowHeight = 30.0;
/// A row carrying a line of explanation under its label needs the height of two lines plus the
/// space that keeps them from reading as one paragraph.
inline constexpr CGFloat kDetailRowHeight = 38.0;
inline constexpr CGFloat kBodyFontSize = 13.0;
inline constexpr CGFloat kDetailFontSize = 11.0;
inline constexpr CGFloat kCardRadius = 10.0;
inline constexpr CGFloat kCardInsetH = 12.0;
inline constexpr CGFloat kCardInsetV = 6.0;
inline constexpr CGFloat kPageMargin = 22.0;
/// The body column is capped rather than filling the window: a switch eighty characters away from
/// the label it belongs to is a row nobody can read across.
inline constexpr CGFloat kContentColumnMax = 660.0;
/// The floor the window has to keep the body column above. It is not a design preference:
/// platforms/macos/tests/candidate/SkinPreviewTest.mm:250 asserts the candidate preview — which is
/// one of the views laid out in this column — comes out wider than 500pt.
inline constexpr CGFloat kContentColumnMin = 516.0;
/// The floor under the control column, not a width for it. One floor replaces the two fixed widths
/// this header used to hand out (190 for a popup, 300 for a cluster): a fixed width gave a card as
/// many control edges as it had kinds of control, while a floor lines the ordinary rows up with one
/// another and lets a cluster — a field beside a colour well, a popup beside three buttons — take
/// the room it actually needs.
inline constexpr CGFloat kControlMinWidth = 190.0;
}  // namespace msime::mac::layout

/// The name the settings window saves its position and size under. It lives here because the two
/// halves of "remember where this window was" are in different files: the window is created and
/// given the autosave name in AppearancePreferences.mm, and every presentation after that decides
/// in PreferencesWindowController.mm whether it still has to be centred.
static inline NSString *MSIMESettingsWindowFrameAutosaveName(void) { return @"MSIMESettingsWindow"; }

/// Whether the user has a saved frame for the settings window. AppKit keys autosaved frames as
/// "NSWindow Frame <name>" in the standard defaults, which is also the only way to ask the question
/// before the window exists. Centring a window that has one is how a restored frame gets thrown
/// away — the window comes back the right size in the wrong place, every single launch.
static inline BOOL MSIMESettingsWindowHasSavedFrame(void) {
    NSString *key = [@"NSWindow Frame " stringByAppendingString:MSIMESettingsWindowFrameAutosaveName()];
    return [NSUserDefaults.standardUserDefaults objectForKey:key] != nil;
}

/// The page the cards sit on. It is the page that has to move, not only the card: measured on
/// macOS 27.0, controlBackgroundColor and windowBackgroundColor resolve to the same grey in both
/// appearances — 1.000 in Aqua, 0.118 in Dark Aqua — so a card painted with either is invisible
/// against the window it is on. underPageBackgroundColor is the one system grey that sits
/// apart from the window, but it sits on opposite sides of it in the two appearances (0.965 under a
/// white Aqua window, 0.157 over a 0.118 Dark Aqua one), so only Aqua can take it: there the page
/// drops away from the card, which is the direction it has to go, since nothing can be lighter than
/// an Aqua window that is already pure white. Dark Aqua keeps the window colour here and lets the
/// card carry the lift instead.
static inline NSColor *MSIMESettingsSurfaceColor(void) {
    return [NSColor colorWithName:@"MSIMESettingsSurface" dynamicProvider:^NSColor *(NSAppearance *appearance) {
        NSAppearanceName match =
            [appearance bestMatchFromAppearancesWithNames:@[ NSAppearanceNameAqua, NSAppearanceNameDarkAqua ]];
        return [match isEqualToString:NSAppearanceNameDarkAqua] ? NSColor.windowBackgroundColor
                                                                : NSColor.underPageBackgroundColor;
    }];
}

/// A card is a group of rows lifted off the page it is drawn on — see MSIMESettingsSurfaceColor()
/// for which grey that page is in each appearance. In Aqua the card takes controlBackgroundColor,
/// pure white above the 0.965 page. In Dark Aqua the page is the window colour and the card is that
/// colour mixed a tenth of the way towards white, because controlBackgroundColor there is the same
/// grey as the window and would leave the card with no edge at all.
static inline NSColor *MSIMECardFillColor(void) {
    return [NSColor colorWithName:@"MSIMESettingsCardFill" dynamicProvider:^NSColor *(NSAppearance *appearance) {
        NSAppearanceName match =
            [appearance bestMatchFromAppearancesWithNames:@[ NSAppearanceNameAqua, NSAppearanceNameDarkAqua ]];
        if (![match isEqualToString:NSAppearanceNameDarkAqua]) return NSColor.controlBackgroundColor;
        // windowBackgroundColor is itself appearance-dependent, so it has to be resolved under the
        // appearance this provider was handed rather than under whatever is current when the card
        // happens to be drawn.
        __block NSColor *lifted = nil;
        [appearance performAsCurrentDrawingAppearance:^{
            lifted = [NSColor.windowBackgroundColor blendedColorWithFraction:0.10 ofColor:NSColor.whiteColor];
        }];
        return lifted ?: NSColor.controlBackgroundColor;
    }];
}

static inline void MSIMEConfigureCard(NSBox *card) {
    card.boxType = NSBoxCustom;
    card.titlePosition = NSNoTitle;
    // The difference between the card's fill and the page's carries the grouping, so there is no
    // border: a stroke around it as well is the hairline box AppKit stopped drawing around grouped
    // rows years ago. borderColor goes with borderWidth — a colour for a stroke that is never drawn
    // is the next reader's five minutes.
    card.borderWidth = 0.0;
    card.cornerRadius = msime::mac::layout::kCardRadius;
    card.fillColor = MSIMECardFillColor();
    card.translatesAutoresizingMaskIntoConstraints = NO;
}

static inline NSTextField *MSIMESectionLabel(NSString *title) {
    NSTextField *label = [NSTextField labelWithString:title];
    label.font = [NSFont systemFontOfSize:msime::mac::layout::kBodyFontSize weight:NSFontWeightSemibold];
    label.textColor = [NSColor labelColor];
    return label;
}

/// The row every card is built from: the name of the setting on the leading edge, the control that
/// changes it on the trailing one, and — when the setting needs a sentence rather than a name — a
/// second, quieter line under the label.
///
/// Two columns of an NSGridView rather than hand-pinned anchors: the control column is placed
/// against the trailing edge, so a card has one control edge no matter what its rows are made of.
/// That placement is also what keeps the switch exemption below honest — a switch is its own
/// intrinsic size and a width constraint would stretch its track, so no row pins a control to a
/// width any more: what a row applies is a floor plus a preference for sitting on it, and the
/// switch is exempt from both.
static inline NSView *MSIMEPreferenceRowWithDetailOfWidth(NSString *title, NSString *detail, NSView *control,
                                                          CGFloat minimumControlWidth) {
    NSTextField *label = [NSTextField labelWithString:title];
    label.font = [NSFont systemFontOfSize:msime::mac::layout::kBodyFontSize weight:NSFontWeightRegular];
    label.translatesAutoresizingMaskIntoConstraints = NO;
    NSView *labelColumn = label;
    if (detail.length > 0) {
        NSTextField *detailLabel = [NSTextField wrappingLabelWithString:detail];
        detailLabel.font = [NSFont systemFontOfSize:msime::mac::layout::kDetailFontSize weight:NSFontWeightRegular];
        detailLabel.textColor = NSColor.secondaryLabelColor;
        detailLabel.selectable = NO;
        detailLabel.translatesAutoresizingMaskIntoConstraints = NO;
        // The sentence is what gives way when the row runs out of width: left at the default it
        // insists on the width of one line and pushes the control past the edge of the card.
        [detailLabel setContentCompressionResistancePriority:NSLayoutPriorityDefaultLow
                                              forOrientation:NSLayoutConstraintOrientationHorizontal];
        NSStackView *column = [NSStackView stackViewWithViews:@[ label, detailLabel ]];
        column.orientation = NSUserInterfaceLayoutOrientationVertical;
        column.alignment = NSLayoutAttributeLeading;
        column.spacing = 2.0;
        column.translatesAutoresizingMaskIntoConstraints = NO;
        labelColumn = column;
    }
    control.translatesAutoresizingMaskIntoConstraints = NO;
    NSGridView *row = [NSGridView gridViewWithViews:@[ @[ labelColumn, control ] ]];
    row.translatesAutoresizingMaskIntoConstraints = NO;
    row.columnSpacing = 12.0;
    row.rowAlignment = NSGridRowAlignmentNone;
    row.yPlacement = NSGridCellPlacementCenter;
    [row columnAtIndex:0].xPlacement = NSGridCellPlacementLeading;
    [row columnAtIndex:1].xPlacement = NSGridCellPlacementTrailing;
    // The breathing room a control taller than the row's own height needs — a push button is taller
    // than a popup — expressed once, on the row, rather than as a pair of inequalities per control.
    [row rowAtIndex:0].topPadding = 4.0;
    [row rowAtIndex:0].bottomPadding = 4.0;
    NSLayoutConstraint *clearance =
        [labelColumn.trailingAnchor constraintLessThanOrEqualToAnchor:control.leadingAnchor constant:-12.0];
    // The grid hands the width a row does not need to whichever column the solver reaches first,
    // which is the control's: left to itself it parks a label against a popup stretched across the
    // rest of the row. The label column takes the slack instead, and it has to want the slack
    // harder than the label hugs its own text.
    NSLayoutConstraint *slack =
        [labelColumn.trailingAnchor constraintEqualToAnchor:control.leadingAnchor constant:-12.0];
    slack.priority = NSLayoutPriorityDefaultHigh;
    NSMutableArray<NSLayoutConstraint *> *constraints = [NSMutableArray arrayWithArray:@[
        [row.heightAnchor constraintGreaterThanOrEqualToConstant:detail.length > 0
                                                                     ? msime::mac::layout::kDetailRowHeight
                                                                     : msime::mac::layout::kRowHeight],
        clearance,
        slack,
    ]];
    if (minimumControlWidth > 0.0 && ![control isKindOfClass:NSSwitch.class]) {
        [constraints addObject:[control.widthAnchor constraintGreaterThanOrEqualToConstant:minimumControlWidth]];
        // Sitting on the floor is a preference, not a rule: it has to outrank the label's content
        // hugging (250) so the label grows rather than the control, and lose to the compression
        // resistance (750) of a cluster whose own contents need more room than the floor.
        NSLayoutConstraint *preferred = [control.widthAnchor constraintEqualToConstant:minimumControlWidth];
        preferred.priority = 500.0;
        [constraints addObject:preferred];
    }
    [NSLayoutConstraint activateConstraints:constraints];
    return row;
}

static inline NSView *MSIMEPreferenceRowOfWidth(NSString *title, NSView *control, CGFloat minimumControlWidth) {
    return MSIMEPreferenceRowWithDetailOfWidth(title, nil, control, minimumControlWidth);
}

static inline NSView *MSIMEPreferenceRow(NSString *title, NSView *control) {
    return MSIMEPreferenceRowWithDetailOfWidth(title, nil, control, msime::mac::layout::kControlMinWidth);
}

/// A setting whose name does not say everything the user has to know about it — when it takes
/// effect, what it sends where, what it is not to be confused with. The window carries thirteen
/// such sentences today, in tooltips and accessibility help, where a trackpad user never meets them.
static inline NSView *MSIMEPreferenceRowWithDetail(NSString *title, NSString *detail, NSView *control) {
    return MSIMEPreferenceRowWithDetailOfWidth(title, detail, control, msime::mac::layout::kControlMinWidth);
}

/// A rejected value reported under the row that holds it, instead of a beep and a silent revert
/// that leave the user guessing which of the five fields on the card was the wrong one. Callers
/// keep the label and swap its stringValue and hidden as the error comes and goes.
static inline NSTextField *MSIMEInlineNotice(NSString *message) {
    NSTextField *notice = [NSTextField wrappingLabelWithString:message ?: @""];
    notice.font = [NSFont systemFontOfSize:msime::mac::layout::kDetailFontSize weight:NSFontWeightRegular];
    notice.textColor = NSColor.systemRedColor;
    notice.selectable = NO;
    notice.translatesAutoresizingMaskIntoConstraints = NO;
    notice.hidden = message.length == 0;
    return notice;
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
