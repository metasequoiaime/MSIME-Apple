#import <AppKit/AppKit.h>
#import <InputMethodKit/InputMethodKit.h>
#import "MSIMEClientSession.h"
#import "../../shared/apple/TextClient.h"
#include "msime_client.h"
#import "CandidatePlacement.h"
#import "AppearancePreferences.h"
#import "CandidateChrome.h"
#include "CandidateSkin.h"

static NSColor *SkinColor(msime::mac::Rgba color) {
    return [NSColor colorWithSRGBRed:color.r green:color.g blue:color.b alpha:color.a];
}

@interface MSIMECandidatePanel : NSPanel
@end
@implementation MSIMECandidatePanel
- (BOOL)canBecomeKeyWindow { return NO; }
- (BOOL)canBecomeMainWindow { return NO; }
@end

@interface MSIMEInputController : IMKInputController
@end

@implementation MSIMEInputController {
    MSIMEClientSession *_session;
    id _activeClient;
    NSDictionary *_view;
    NSPanel *_panel;
    NSString *_preferencesDirectory;
    NSTimer *_preferencesTimer;
    BOOL _preferencesLoading;
    MSIMEAppearancePreferences *_appearance;
    NSUInteger _requestedPageSize;
    BOOL _skinShowsSelectedBar;
    BOOL _focusPending;
}

- (void)ensureAppearance {
    if (_appearance) return;
    _appearance = [MSIMEAppearancePreferences sharedPreferences];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(appearanceChanged:) name:MSIMEAppearanceDidChangeNotification object:_appearance];
}
- (void)appearanceChanged:(NSNotification *)notification {
    (void)notification;
    if (_appearance.englishMode && _activeClient && ([_view[@"editing_text"] length] || [_view[@"candidates"] count])) {
        [self apply:[_session command:MSIME_FINISH_COMPOSITION error:nil]];
    }
    [self syncPageSize];
    if (_activeClient) [self renderCandidates];
}
- (void)syncPageSize {
    if (!_session) return;
    [self ensureAppearance];
    NSUInteger size = _appearance.pageSize;
    if (_requestedPageSize == size) return;
    NSDictionary *result = [_session setCandidatePageSize:(uint8_t)size error:nil];
    if (result) {
        _requestedPageSize = size;
        _view = result[@"view"];
    }
}
- (NSMenu *)menu {
    [self ensureAppearance];
    NSMenu *menu = [[NSMenu alloc] initWithTitle:@"水杉输入法"];
    menu.autoenablesItems = NO;
    for (NSUInteger mode = 0; mode < 2; ++mode) {
        NSMenuItem *item = [[NSMenuItem alloc] initWithTitle:mode ? @"英文输入" : @"中文输入" action:mode ? @selector(selectEnglishMode:) : @selector(selectChineseMode:) keyEquivalent:@""];
        item.target = self;
        item.state = _appearance.englishMode == (mode == 1) ? NSControlStateValueOn : NSControlStateValueOff;
        [menu addItem:item];
    }
    [menu addItem:NSMenuItem.separatorItem];
    NSMenuItem *palette = [[NSMenuItem alloc] initWithTitle:@"表情与符号…" action:@selector(openCharacterPalette:) keyEquivalent:@""];
    palette.target = self;
    [menu addItem:palette];
    NSMenuItem *item = [[NSMenuItem alloc] initWithTitle:@"候选设置…" action:@selector(showAppearance:) keyEquivalent:@""];
    item.target = self;
    [menu addItem:item];
    return menu;
}
- (void)setEnglishInputMode:(BOOL)enabled {
    [self ensureAppearance];
    if (enabled && !_appearance.englishMode && _session && _activeClient) {
        NSDictionary *finished = [_session command:MSIME_FINISH_COMPOSITION error:nil];
        if (!finished) return; // Do not hide an unsettled composition after an Engine failure.
        [self apply:finished];
    }
    _appearance.englishMode = enabled;
    [_panel orderOut:nil];
}
- (void)selectChineseMode:(id)sender { (void)sender; [self setEnglishInputMode:NO]; }
- (void)selectEnglishMode:(id)sender { (void)sender; [self setEnglishInputMode:YES]; }
- (void)showSystemCharacterPalette { [NSApp orderFrontCharacterPalette:nil]; }
- (void)openCharacterPalette:(id)sender {
    (void)sender;
    if (_session && _activeClient) {
        NSDictionary *finished = [_session command:MSIME_FINISH_COMPOSITION error:nil];
        if (!finished) return;
        [self apply:finished];
    }
    [self showSystemCharacterPalette];
}
- (void)showAppearance:(id)sender {
    [self ensureAppearance];
    [_appearance showWindow:sender];
    [NSApp activateIgnoringOtherApps:YES];
}

- (void)activateServer:(id)sender {
    [super activateServer:sender];
    _activeClient = sender;
    [self ensureAppearance];
    _focusPending = _appearance.englishMode;
    if (!_appearance.englishMode) [self prepareSession];
}

- (void)prepareSession {
    if (!_session) {
        NSString *path = [[NSBundle mainBundle] pathForResource:@"runtime-options" ofType:@"json"];
        if (!path) {
            NSURL *support = [[[NSFileManager defaultManager] URLsForDirectory:NSApplicationSupportDirectory inDomains:NSUserDomainMask] firstObject];
            path = [[support URLByAppendingPathComponent:@"app.msime.client.preview/runtime-options.json"] path];
        }
        NSData *data = [NSData dataWithContentsOfFile:path];
        NSDictionary *options = data ? [NSJSONSerialization JSONObjectWithData:data options:0 error:nil] : nil;
        if ([options isKindOfClass:NSDictionary.class]) {
            _session = [[MSIMEClientSession alloc] initWithOptions:options error:nil];
            id directory = options[@"preferences_directory"];
            if ([directory isKindOfClass:NSString.class] && [directory isAbsolutePath]) _preferencesDirectory = [directory copy];
        }
    }
    [self syncPageSize];
    if (_session) {
        [self apply:[_session setFocused:YES error:nil]];
        _focusPending = NO;
    }
    if (_session && _preferencesDirectory) {
        [_preferencesTimer invalidate];
        __weak MSIMEInputController *weakSelf = self;
        _preferencesTimer = [NSTimer scheduledTimerWithTimeInterval:1.0 repeats:YES block:^(NSTimer *timer) {
            (void)timer;
            [weakSelf reloadPreferences];
        }];
        [self reloadPreferences];
    }
}

- (void)reloadPreferences {
    if (_preferencesLoading || !_activeClient) return;
    _preferencesLoading = YES;
    __weak MSIMEInputController *weakSelf = self;
    [_session reloadPreferencesDirectory:_preferencesDirectory completion:^(NSDictionary *result, NSError *error) {
        MSIMEInputController *controller = weakSelf;
        if (!controller) return;
        controller->_preferencesLoading = NO;
        // Failed loads retain the old configuration; never synthesize defaults here.
        if (result && !error && controller->_activeClient) {
            controller->_view = result[@"view"];
            [controller renderCandidates];
        }
    }];
}

- (void)deactivateServer:(id)sender {
    [_preferencesTimer invalidate];
    _preferencesTimer = nil;
    if (_session) [self apply:[_session setFocused:NO error:nil]];
    [_panel orderOut:nil];
    _activeClient = nil;
    [super deactivateServer:sender];
}

- (void)dealloc {
    [_preferencesTimer invalidate];
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (NSUInteger)recognizedEvents:(id)sender {
    (void)sender;
    return NSEventMaskKeyDown;
}

- (BOOL)handleEvent:(NSEvent *)event client:(id)sender {
    if (event.type != NSEventTypeKeyDown) return NO;
    [self ensureAppearance];
    if (sender != _activeClient) {
        // Clear the previous client's marked text before accepting the new focus.
        [self apply:[_session setFocused:NO error:nil]];
        _activeClient = sender;
        _focusPending = _appearance.englishMode;
        if (!_appearance.englishMode) [self apply:[_session setFocused:YES error:nil]];
    }
    const NSEventModifierFlags competing = NSEventModifierFlagCommand | NSEventModifierFlagControl | NSEventModifierFlagOption;
    if (_appearance.inputModeShortcut && event.keyCode == 49 && (event.modifierFlags & NSEventModifierFlagShift) && !(event.modifierFlags & competing)) {
        if (!event.isARepeat) [self setEnglishInputMode:!_appearance.englishMode];
        return YES;
    }
    if (_appearance.englishMode) return NO;
    if (!_session) [self prepareSession];
    if (!_session) return NO;
    if (_focusPending) [self prepareSession];
    [self syncPageSize];
    if (event.modifierFlags & (NSEventModifierFlagCommand | NSEventModifierFlagControl | NSEventModifierFlagOption)) {
        [self apply:[_session command:MSIME_FINISH_COMPOSITION error:nil]];
        return NO;
    }
    uint32_t command = UINT32_MAX;
    [self ensureAppearance];
    if (_panel.isVisible && !(event.modifierFlags & NSEventModifierFlagShift)) {
        NSString *characters = event.charactersIgnoringModifiers;
        if (characters.length == 1) {
            const unichar character = [characters characterAtIndex:0];
            const NSInteger shortcut = _appearance.pageShortcut;
            const BOOL previous = (shortcut == 0 && character == '-') || (shortcut == 1 && character == '[');
            const BOOL next = (shortcut == 0 && character == '=') || (shortcut == 1 && character == ']');
            if (previous || next) {
                [self apply:[_session command:previous ? MSIME_PREVIOUS_PAGE : MSIME_NEXT_PAGE error:nil]];
                return YES;
            }
        }
    }
    if (_panel.isVisible && event.keyCode >= 123 && event.keyCode <= 126) {
        const BOOL horizontal = event.keyCode == 123 || event.keyCode == 124;
        if (horizontal == _appearance.vertical) return YES;
        const BOOL backwards = event.keyCode == 123 || event.keyCode == 126;
        [self apply:[_session command:backwards ? MSIME_PREVIOUS_CANDIDATE : MSIME_NEXT_CANDIDATE error:nil]];
        return YES;
    }
    switch (event.keyCode) {
        case 51: command = MSIME_BACKSPACE; break;
        case 36: case 76: command = MSIME_COMMIT_RAW; break;
        case 53: command = MSIME_CANCEL; break;
        case 49: command = MSIME_COMMIT_CANDIDATE; break;
        case 123: command = MSIME_MOVE_LEFT; break;
        case 124: command = MSIME_MOVE_RIGHT; break;
        case 115: command = _panel.isVisible ? MSIME_FIRST_CANDIDATE_ON_PAGE : MSIME_MOVE_HOME; break;
        case 119: command = _panel.isVisible ? MSIME_LAST_CANDIDATE_ON_PAGE : MSIME_MOVE_END; break;
        case 117: command = MSIME_DELETE_FORWARD; break;
        case 116: command = MSIME_PREVIOUS_PAGE; break;
        case 121: command = MSIME_NEXT_PAGE; break;
        case 126: command = MSIME_PREVIOUS_CANDIDATE; break;
        case 125: command = MSIME_NEXT_CANDIDATE; break;
    }
    NSDictionary *transition = nil;
    if (command != UINT32_MAX) transition = [_session command:command error:nil];
    else if (event.characters.length == 1 && [event.characters characterAtIndex:0] <= 127) {
        transition = [_session typeASCII:(uint8_t)[event.characters characterAtIndex:0] shift:(event.modifierFlags & NSEventModifierFlagShift) != 0 error:nil];
    }
    if (!transition) return NO;
    [self apply:transition];
    return [transition[@"handled"] boolValue];
}

- (void)commitComposition:(id)sender {
    if (sender != _activeClient || !_session) return;
    [self apply:[_session command:MSIME_FINISH_COMPOSITION error:nil]];
}

- (void)apply:(NSDictionary *)transition {
    if (!transition || !_activeClient) return;
    MSIMEApplyTransition(transition, (id<MSIMETextClient>)_activeClient);
    _view = transition[@"view"];
    [self renderCandidates];
}

- (void)renderCandidates {
    if (_appearance.englishMode) { [_panel orderOut:nil]; return; }
    NSArray *candidates = _view[@"candidates"];
    if (![candidates isKindOfClass:NSArray.class] || candidates.count == 0) { [_panel orderOut:nil]; return; }
    NSRect cursor = NSZeroRect;
    [(id<IMKTextInput>)_activeClient attributesForCharacterIndex:0 lineHeightRectangle:&cursor];
    if (!MSIMEValidCaret(cursor)) { [_panel orderOut:nil]; return; }
    NSScreen *screen = nil;
    for (NSScreen *candidate in NSScreen.screens) {
        if (NSPointInRect(NSMakePoint(NSMinX(cursor), NSMidY(cursor)), candidate.frame)) { screen = candidate; break; }
    }
    screen = screen ?: NSScreen.mainScreen;
    if (!screen) { [_panel orderOut:nil]; return; }
    NSRect visible = screen.visibleFrame;
    [self ensureAppearance];
    const BOOL vertical = _appearance.vertical;
    NSAppearance *currentAppearance = _panel.effectiveAppearance ?: NSApp.effectiveAppearance;
    NSString *currentTheme = [currentAppearance bestMatchFromAppearancesWithNames:@[NSAppearanceNameAqua, NSAppearanceNameDarkAqua]];
    const auto skin = [_appearance resolvedSkinForDark:[currentTheme isEqual:NSAppearanceNameDarkAqua]];
    const auto geometry = skin.tokens;
    _skinShowsSelectedBar = geometry.showSelectedBar;
    const CGFloat inset = MAX(2.0, geometry.pad);
    NSFont *font = [NSFont systemFontOfSize:_appearance.fontSize];
    const CGFloat rowHeight = ceil(font.ascender - font.descender + font.leading) + 12;
    const NSUInteger page = [_view[@"page"] unsignedIntegerValue];
    const NSUInteger pageCount = [_view[@"page_count"] unsignedIntegerValue];
    const BOOL paging = pageCount > 1;
    CGFloat width = 20;
    NSMutableArray<NSNumber *> *widths = [NSMutableArray array];
    CGFloat totalWidth = 0;
    NSUInteger index = 0;
    for (NSDictionary *candidate in candidates) {
        NSString *title = [NSString stringWithFormat:@"%lu  %@", (unsigned long)++index, candidate[@"text"]];
        const CGFloat itemWidth = ceil([title sizeWithAttributes:@{NSFontAttributeName: font}].width) + 16 + (geometry.showSelectedBar ? 6 : 0);
        [widths addObject:@(itemWidth)];
        totalWidth += itemWidth;
        width = MAX(width, itemWidth + 2 * inset);
    }
    width = MIN(width, MAX(80, visible.size.width - 20));
    if (paging) width = MAX(width, 76);
    if (!vertical) {
        const CGFloat available = MAX(80, visible.size.width - 32 - (paging ? 56 : 0));
        if (totalWidth > available) {
            const CGFloat scale = available / totalWidth;
            totalWidth = 0;
            for (NSUInteger i = 0; i < widths.count; ++i) {
                widths[i] = @(MAX(24, floor(widths[i].doubleValue * scale)));
                totalWidth += widths[i].doubleValue;
            }
        }
        width = totalWidth + 2 * inset + (paging ? 56 : 0);
    }
    if (!_panel) {
        _panel = [[MSIMECandidatePanel alloc] initWithContentRect:NSZeroRect styleMask:NSWindowStyleMaskBorderless | NSWindowStyleMaskNonactivatingPanel backing:NSBackingStoreBuffered defer:NO];
        _panel.level = NSPopUpMenuWindowLevel;
        _panel.hasShadow = YES;
        _panel.hidesOnDeactivate = NO;
        _panel.becomesKeyOnlyIfNeeded = YES;
        _panel.collectionBehavior = NSWindowCollectionBehaviorCanJoinAllSpaces | NSWindowCollectionBehaviorFullScreenAuxiliary;
    }
    _panel.opaque = NO;
    _panel.backgroundColor = NSColor.clearColor;
    const CGFloat decorationHeight = skin.decorationTopDip;
    width = MAX(width, MAX(skin.minWidthDip, skin.decorationWidthDip));
    CGFloat height = (vertical ? candidates.count : 1) * rowHeight + 2 * inset + (paging && vertical ? 26 : 0) + decorationHeight;
    [_panel setContentSize:NSMakeSize(width, height)];
    MSIMECandidateChromeView *content = [[MSIMECandidateChromeView alloc] initWithFrame:NSMakeRect(0, 0, width, height)];
    NSUInteger slot = 0;
    CGFloat x = inset;
    for (NSDictionary *candidate in candidates) {
        NSString *title = [NSString stringWithFormat:@"%lu  %@", (unsigned long)(slot + 1), candidate[@"text"]];
        MSIMECandidateButton *button = [MSIMECandidateButton buttonWithTitle:title target:self action:@selector(selectCandidate:)];
        button.candidateID = candidate[@"id"];
        button.tag = (NSInteger)slot;
        CGFloat itemWidth = vertical ? width - 2 * inset : widths[slot].doubleValue;
        button.frame = NSMakeRect(x, vertical ? height - inset - decorationHeight - ((slot + 1) * rowHeight) : inset, itemWidth, rowHeight);
        ++slot;
        if (!vertical) x += itemWidth;
        button.font = font;
        button.lineBreakMode = NSLineBreakByTruncatingTail;
        button.toolTip = candidate[@"text"];
        button.bordered = NO;
        button.candidateHighlighted = [candidate[@"highlighted"] boolValue];
        button.alignment = NSTextAlignmentLeft;
        [content addSubview:button];
    }
    if (paging) {
        for (NSUInteger direction = 0; direction < 2; ++direction) {
            MSIMECandidateButton *button = [MSIMECandidateButton buttonWithTitle:direction == 0 ? @"‹" : @"›" target:self action:@selector(changeCandidatePage:)];
            button.frame = NSMakeRect((vertical ? inset : x) + direction * 28, inset, 28, vertical ? 26 : rowHeight);
            button.bordered = NO;
            button.tag = direction == 0 ? -1 : -2;
            button.enabled = direction == 0 ? page > 0 : page < pageCount - 1;
            button.accessibilityLabel = direction == 0 ? @"上一页候选" : @"下一页候选";
            // A retained button from an old page cannot navigate a newer view.
            button.candidateID = _view;
            [content addSubview:button];
        }
    }
    if (decorationHeight > 0 && _appearance.decorationImage) {
        NSImageView *decoration = [[NSImageView alloc] initWithFrame:NSMakeRect(width - skin.decorationWidthDip, height - decorationHeight, skin.decorationWidthDip, decorationHeight)];
        decoration.image = _appearance.decorationImage;
        decoration.imageScaling = NSImageScaleProportionallyUpOrDown;
        decoration.imageAlignment = NSImageAlignTopRight;
        decoration.wantsLayer = YES;
        [content addSubview:decoration];
    }
    _panel.contentView = content;
    content.appearanceTarget = self;
    content.appearanceAction = @selector(refreshCandidateSkin);
    [self refreshCandidateSkin];
    [_panel setFrameOrigin:MSIMECandidateOrigin(cursor, _panel.frame.size, visible)];
    [_panel orderFrontRegardless];
}

- (void)refreshCandidateSkin {
    if (![_panel.contentView isKindOfClass:MSIMECandidateChromeView.class]) return;
    MSIMECandidateChromeView *content = (id)_panel.contentView;
    NSString *match = [content.effectiveAppearance bestMatchFromAppearancesWithNames:@[NSAppearanceNameAqua, NSAppearanceNameDarkAqua]];
    const auto tokens = [_appearance resolvedSkinForDark:[match isEqual:NSAppearanceNameDarkAqua]].tokens;
    if (tokens.showSelectedBar != _skinShowsSelectedBar) { [self renderCandidates]; return; }
    content.fillColor = SkinColor(tokens.surface);
    content.strokeColor = SkinColor(tokens.border);
    content.cornerRadius = tokens.radius;
    content.lineWidth = tokens.borderWidth;
    for (MSIMECandidateButton *button in content.subviews) {
        if (![button isKindOfClass:MSIMECandidateButton.class]) continue;
        button.fillColor = SkinColor(tokens.selected);
        button.titleColor = SkinColor(button.candidateHighlighted ? tokens.selectedText : tokens.text);
        button.numberColor = SkinColor(button.candidateHighlighted ? tokens.selectedText : tokens.number);
        button.barColor = SkinColor(tokens.accent);
        button.showSelectedBar = tokens.showSelectedBar;
        button.contentTintColor = SkinColor(tokens.text);
        button.needsDisplay = YES;
    }
    content.needsDisplay = YES;
}

- (void)selectCandidate:(MSIMECandidateButton *)button {
    NSDictionary *identifier = button.candidateID;
    if (![identifier isKindOfClass:NSDictionary.class] ||
        ![identifier[@"session"] isEqual:_view[@"session"]])
        return;
    [self apply:[_session selectGeneration:[identifier[@"generation"] unsignedLongLongValue] index:[identifier[@"index"] unsignedIntegerValue] error:nil]];
}

- (void)changeCandidatePage:(MSIMECandidateButton *)button {
    if (!_activeClient || !_panel.isVisible || ![_view[@"focused"] boolValue] || !button.enabled) return;
    for (NSString *key in @[@"session", @"generation", @"page"]) {
        if (![button.candidateID[key] isEqual:_view[key]]) return;
    }
    const NSUInteger page = [_view[@"page"] unsignedIntegerValue];
    const NSUInteger count = [_view[@"page_count"] unsignedIntegerValue];
    if (button.tag == -1 && page > 0) [self apply:[_session command:MSIME_PREVIOUS_PAGE error:nil]];
    if (button.tag == -2 && count > 0 && page < count - 1) [self apply:[_session command:MSIME_NEXT_PAGE error:nil]];
}
@end
