#import <AppKit/AppKit.h>
#import <InputMethodKit/InputMethodKit.h>
#import "MSIMEClientSession.h"
#import "../../shared/apple/TextClient.h"
#include "msime_client.h"

@interface MSIMECandidateButton : NSButton
@property(nonatomic, copy) NSDictionary *candidateID;
@end
@implementation MSIMECandidateButton
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
}

- (void)activateServer:(id)sender {
    [super activateServer:sender];
    _activeClient = sender;
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
    if (!_session || event.type != NSEventTypeKeyDown) return NO;
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
    NSArray *candidates = _view[@"candidates"];
    if (![candidates isKindOfClass:NSArray.class] || candidates.count == 0) { [_panel orderOut:nil]; return; }
    if (!_panel) {
        _panel = [[NSPanel alloc] initWithContentRect:NSMakeRect(0, 0, 280, 40) styleMask:NSWindowStyleMaskBorderless | NSWindowStyleMaskNonactivatingPanel backing:NSBackingStoreBuffered defer:NO];
        _panel.level = NSPopUpMenuWindowLevel;
        _panel.hasShadow = YES;
        _panel.hidesOnDeactivate = NO;
        _panel.becomesKeyOnlyIfNeeded = YES;
        _panel.collectionBehavior = NSWindowCollectionBehaviorCanJoinAllSpaces | NSWindowCollectionBehaviorFullScreenAuxiliary;
    }
    CGFloat height = candidates.count * 34 + 12;
    [_panel setContentSize:NSMakeSize(280, height)];
    NSView *content = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 280, height)];
    NSUInteger slot = 0;
    for (NSDictionary *candidate in candidates) {
        NSString *title = [NSString stringWithFormat:@"%lu. %@", (unsigned long)(slot + 1), candidate[@"text"]];
        MSIMECandidateButton *button = [MSIMECandidateButton buttonWithTitle:title target:self action:@selector(selectCandidate:)];
        button.candidateID = candidate[@"id"];
        button.frame = NSMakeRect(6, height - (++slot * 34), 268, 30);
        button.bordered = [candidate[@"highlighted"] boolValue];
        button.alignment = NSTextAlignmentLeft;
        [content addSubview:button];
    }
    _panel.contentView = content;
    NSRect cursor = NSZeroRect;
    [(id<IMKTextInput>)_activeClient attributesForCharacterIndex:0 lineHeightRectangle:&cursor];
    NSScreen *screen = nil;
    for (NSScreen *candidate in NSScreen.screens) if (NSPointInRect(cursor.origin, candidate.frame)) { screen = candidate; break; }
    NSRect visible = (screen ?: NSScreen.mainScreen).visibleFrame;
    CGFloat x = MIN(MAX(cursor.origin.x, NSMinX(visible)), NSMaxX(visible) - 280);
    CGFloat y = cursor.origin.y - height;
    if (y < NSMinY(visible)) y = NSMaxY(cursor);
    y = MIN(MAX(y, NSMinY(visible)), NSMaxY(visible) - height);
    [_panel setFrameOrigin:NSMakePoint(x, y)];
    [_panel orderFrontRegardless];
}

- (void)selectCandidate:(MSIMECandidateButton *)button {
    NSDictionary *identifier = button.candidateID;
    if (![identifier isKindOfClass:NSDictionary.class] ||
        ![identifier[@"session"] isEqual:_view[@"session"]])
        return;
    [self apply:[_session selectGeneration:[identifier[@"generation"] unsignedLongLongValue] index:[identifier[@"index"] unsignedIntegerValue] error:nil]];
}
@end
