#import <AppKit/AppKit.h>
#import <InputMethodKit/InputMethodKit.h>
#import "MSIMEClientSession.h"
#import "../../shared/apple/TextClient.h"
#include "msime_client.h"
#import "CandidatePlacement.h"
#import "FullWidthInput.h"

@interface MSIMECandidatePanel : NSPanel
@end
@implementation MSIMECandidatePanel
- (BOOL)canBecomeKeyWindow { return NO; }
- (BOOL)canBecomeMainWindow { return NO; }
@end

@interface MSIMECandidateButton : NSButton
@property(nonatomic, copy) NSDictionary *candidateID;
@end
@implementation MSIMECandidateButton
- (BOOL)acceptsFirstResponder { return NO; }
- (BOOL)acceptsFirstMouse:(NSEvent *)event { (void)event; return YES; }
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
    BOOL _verticalCandidates;
    BOOL _fullWidthInput;
}

- (void)activateServer:(id)sender {
    [super activateServer:sender];
    _activeClient = sender;
    _fullWidthInput = [[NSUserDefaults standardUserDefaults] boolForKey:@"MSIMEClientFullWidthInput"];
    _verticalCandidates = YES;
    if (!_session) {
        NSString *path = [[NSBundle mainBundle] pathForResource:@"runtime-options" ofType:@"json"];
        if (!path) {
            NSURL *support = [[[NSFileManager defaultManager] URLsForDirectory:NSApplicationSupportDirectory inDomains:NSUserDomainMask] firstObject];
            path = [[support URLByAppendingPathComponent:@"app.msime.client.preview/runtime-options.json"] path];
        }
        NSData *data = [NSData dataWithContentsOfFile:path];
        NSDictionary *options = data ? [NSJSONSerialization JSONObjectWithData:data options:0 error:nil] : nil;
        if ([options isKindOfClass:NSDictionary.class]) {
            _verticalCandidates = ![options[@"candidate_orientation"] isEqual:@"horizontal"];
            _session = [[MSIMEClientSession alloc] initWithOptions:options error:nil];
            id directory = options[@"preferences_directory"];
            if ([directory isKindOfClass:NSString.class] && [directory isAbsolutePath]) _preferencesDirectory = [directory copy];
        }
    }
    if (_session) [self apply:[_session setFocused:YES error:nil]];
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

- (void)dealloc { [_preferencesTimer invalidate]; }

- (NSUInteger)recognizedEvents:(id)sender {
    (void)sender;
    return NSEventMaskKeyDown;
}

- (BOOL)handleEvent:(NSEvent *)event client:(id)sender {
    if (event.type != NSEventTypeKeyDown) return NO;
    if (msime::mac::IsFullWidthInputToggle(event.keyCode, event.modifierFlags)) {
        if (!event.isARepeat) {
            _fullWidthInput = !_fullWidthInput;
            [[NSUserDefaults standardUserDefaults] setBool:_fullWidthInput forKey:@"MSIMEClientFullWidthInput"];
        }
        return YES;
    }
    if (!_session) return NO;
    if (sender != _activeClient) {
        // Clear the previous client's marked text before accepting the new focus.
        [self apply:[_session setFocused:NO error:nil]];
        _activeClient = sender;
        [self apply:[_session setFocused:YES error:nil]];
    }
    if (event.modifierFlags & (NSEventModifierFlagCommand | NSEventModifierFlagControl | NSEventModifierFlagOption)) {
        [self apply:[_session command:MSIME_FINISH_COMPOSITION error:nil]];
        return NO;
    }
    uint32_t command = UINT32_MAX;
    // The current panel is vertical: Apple consumes the non-primary direction
    // while candidates are visible, without editing the underlying composition.
    if (_panel.isVisible && (event.keyCode == 123 || event.keyCode == 124)) return YES;
    switch (event.keyCode) {
        case 51: command = MSIME_BACKSPACE; break;
        case 36: case 76: command = MSIME_COMMIT_RAW; break;
        case 53: command = MSIME_CANCEL; break;
        case 49: command = MSIME_COMMIT_CANDIDATE; break;
        case 123: command = MSIME_MOVE_LEFT; break;
        case 124: command = MSIME_MOVE_RIGHT; break;
        case 115: command = MSIME_MOVE_HOME; break;
        case 119: command = MSIME_MOVE_END; break;
        case 117: command = MSIME_DELETE_FORWARD; break;
        case 116: command = MSIME_PREVIOUS_PAGE; break;
        case 121: command = MSIME_NEXT_PAGE; break;
        case 126: command = MSIME_PREVIOUS_CANDIDATE; break;
        case 125: command = MSIME_NEXT_CANDIDATE; break;
    }
    NSDictionary *transition = nil;
    if (command != UINT32_MAX) transition = [_session command:command error:nil];
    else if (event.characters.length == 1 && [event.characters characterAtIndex:0] <= 127) {
        const unichar character = [event.characters characterAtIndex:0];
        transition = [_session typeASCII:(uint8_t)character shift:(event.modifierFlags & NSEventModifierFlagShift) != 0 error:nil];
    }
    if (!transition) return NO;
    [self apply:transition];
    if ([transition[@"handled"] boolValue]) return YES;
    if ([_view[@"editing_text"] isKindOfClass:NSString.class] && [_view[@"editing_text"] length]) {
        NSDictionary *finished = [_session command:MSIME_FINISH_COMPOSITION error:nil];
        if (!finished) return NO;
        [self apply:finished];
    }
    if (_fullWidthInput && [_view[@"editing_text"] isKindOfClass:NSString.class] &&
        ![_view[@"editing_text"] length] && event.characters.length == 1 &&
        msime::mac::IsFullWidthDirectCharacter([event.characters characterAtIndex:0], event.modifierFlags)) {
        const unichar converted = msime::mac::FullWidthCharacter([event.characters characterAtIndex:0]);
        [(id<IMKTextInput>)_activeClient insertText:[NSString stringWithCharacters:&converted length:1]
                                   replacementRange:NSMakeRange(NSNotFound, NSNotFound)];
        return YES;
    }
    return NO;
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
    NSFont *font = [NSFont systemFontOfSize:18];
    const CGFloat rowHeight = ceil(font.ascender - font.descender + font.leading) + 12;
    const BOOL vertical = _verticalCandidates;
    const NSUInteger page = [_view[@"page"] unsignedIntegerValue];
    const NSUInteger pageCount = [_view[@"page_count"] unsignedIntegerValue];
    const BOOL hasPreviousPage = page > 0;
    const BOOL hasNextPage = pageCount > 0 && page + 1 < pageCount;
    const BOOL paging = hasPreviousPage || hasNextPage;
    NSMutableArray<NSNumber *> *itemWidths = [NSMutableArray arrayWithCapacity:candidates.count];
    CGFloat candidateWidth = 0;
    for (NSDictionary *candidate in candidates) {
        const NSUInteger index = itemWidths.count + 1;
        NSString *title = [NSString stringWithFormat:@"%lu  %@", (unsigned long)index, candidate[@"text"]];
        CGFloat itemWidth = ceil([title sizeWithAttributes:@{NSFontAttributeName: font}].width) + (vertical ? 28 : 12);
        if (!vertical) itemWidth = MIN(180, itemWidth);
        [itemWidths addObject:@(itemWidth)];
        candidateWidth = vertical ? MAX(candidateWidth, itemWidth) : candidateWidth + itemWidth;
    }
    const CGFloat availableWidth = MAX(80, visible.size.width - 20 - (!vertical && paging ? 56 : 0));
    if (vertical) {
        candidateWidth = MIN(candidateWidth, availableWidth);
    } else if (candidateWidth > availableWidth && candidateWidth > 0) {
        const CGFloat scale = availableWidth / candidateWidth;
        candidateWidth = 0;
        for (NSUInteger index = 0; index < itemWidths.count; ++index) {
            const CGFloat scaled = MAX(24, floor(itemWidths[index].doubleValue * scale));
            itemWidths[index] = @(scaled);
            candidateWidth += scaled;
        }
    }
    const CGFloat panelWidth = paging ? (vertical ? MAX(candidateWidth, 64) : candidateWidth + 56) : candidateWidth;
    if (!_panel) {
        _panel = [[MSIMECandidatePanel alloc] initWithContentRect:NSZeroRect styleMask:NSWindowStyleMaskBorderless | NSWindowStyleMaskNonactivatingPanel backing:NSBackingStoreBuffered defer:NO];
        _panel.level = NSPopUpMenuWindowLevel;
        _panel.hasShadow = YES;
        _panel.hidesOnDeactivate = NO;
        _panel.becomesKeyOnlyIfNeeded = YES;
        _panel.collectionBehavior = NSWindowCollectionBehaviorCanJoinAllSpaces | NSWindowCollectionBehaviorFullScreenAuxiliary;
        _panel.backgroundColor = [NSColor colorWithCalibratedWhite:0.12 alpha:0.96];
        _panel.opaque = NO;
        _panel.contentView.wantsLayer = YES;
        _panel.contentView.layer.cornerRadius = 8.0;
        _panel.contentView.layer.masksToBounds = YES;
    }
    const CGFloat navigationHeight = paging && vertical ? 26 : 0;
    const CGFloat height = vertical ? candidates.count * rowHeight + navigationHeight + 12 : rowHeight + 12;
    [_panel setContentSize:NSMakeSize(panelWidth, height)];
    NSView *content = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, panelWidth, height)];
    NSUInteger slot = 0;
    const CGFloat contentTop = height - 6 - navigationHeight;
    for (NSDictionary *candidate in candidates) {
        NSString *title = [NSString stringWithFormat:@"%lu  %@", (unsigned long)(slot + 1), candidate[@"text"]];
        MSIMECandidateButton *button = [MSIMECandidateButton buttonWithTitle:title target:self action:@selector(selectCandidate:)];
        button.candidateID = candidate[@"id"];
        if (vertical) {
            button.frame = NSMakeRect(6, contentTop - (++slot * rowHeight), candidateWidth - 12, rowHeight);
        } else {
            CGFloat x = 6;
            for (NSUInteger index = 0; index < slot; ++index) x += itemWidths[index].doubleValue;
            button.frame = NSMakeRect(x, 6, itemWidths[slot].doubleValue, rowHeight);
            ++slot;
        }
        button.font = font;
        button.contentTintColor = [NSColor whiteColor];
        button.bezelStyle = NSBezelStyleTexturedRounded;
        button.wantsLayer = YES;
        button.layer.cornerRadius = 4.0;
        if ([candidate[@"highlighted"] boolValue]) {
            button.layer.backgroundColor = [NSColor colorWithCalibratedRed:0.18 green:0.42 blue:0.78 alpha:1.0].CGColor;
        }
        button.lineBreakMode = NSLineBreakByTruncatingTail;
        button.toolTip = candidate[@"text"];
        button.bordered = [candidate[@"highlighted"] boolValue];
        button.alignment = NSTextAlignmentLeft;
        [content addSubview:button];
    }
    if (paging) {
        for (NSUInteger index = 0; index < 2; ++index) {
            NSButton *button = [NSButton buttonWithTitle:index == 0 ? @"‹" : @"›"
                                                    target:self
                                                    action:@selector(changeCandidatePage:)];
            button.frame = vertical ? NSMakeRect(6 + index * 28, 6, 28, 26)
                                    : NSMakeRect(candidateWidth + 6 + index * 28, 6, 28, rowHeight);
            button.bordered = NO;
            button.contentTintColor = [NSColor whiteColor];
            button.tag = index == 0 ? -1 : -2;
            button.enabled = index == 0 ? hasPreviousPage : hasNextPage;
            button.accessibilityLabel = index == 0 ? @"上一页候选" : @"下一页候选";
            [content addSubview:button];
        }
    }
    _panel.contentView = content;
    [_panel setFrameOrigin:MSIMECandidateOrigin(cursor, _panel.frame.size, visible)];
    [_panel orderFrontRegardless];
}

- (void)changeCandidatePage:(NSButton *)button {
    if (!_session || ![_view[@"page"] isKindOfClass:NSNumber.class] || ![_view[@"page_count"] isKindOfClass:NSNumber.class]) return;
    const NSUInteger page = [_view[@"page"] unsignedIntegerValue];
    const NSUInteger pageCount = [_view[@"page_count"] unsignedIntegerValue];
    if (button.tag == -1 && page > 0) [self apply:[_session command:MSIME_PREVIOUS_PAGE error:nil]];
    if (button.tag == -2 && page + 1 < pageCount) [self apply:[_session command:MSIME_NEXT_PAGE error:nil]];
}

- (void)selectCandidate:(MSIMECandidateButton *)button {
    NSDictionary *identifier = button.candidateID;
    if (![identifier isKindOfClass:NSDictionary.class] ||
        ![identifier[@"session"] isEqual:_view[@"session"]])
        return;
    [self apply:[_session selectGeneration:[identifier[@"generation"] unsignedLongLongValue] index:[identifier[@"index"] unsignedIntegerValue] error:nil]];
}
@end
