#import "VoiceInputService.h"
#import "VoiceSettings.h"
#import "ShuangpinKeymapPanel.h"
#import "ChineseTextConversion.h"
#import <AppKit/AppKit.h>
#import <InputMethodKit/InputMethodKit.h>
#import "MSIMEClientSession.h"
#import "../../shared/apple/TextClient.h"
#include "msime_client.h"
#import "CandidatePlacement.h"
#import "FullWidthInput.h"
#import "InputModeRouting.h"
#import "InputMenu.h"
#import "CandidateAppearance.h"
#import "CandidateChrome.h"
#import "PreferencesWindowController.h"
#import "FloatingToolbarPanel.h"
#include "CandidateSkin.h"

@interface MSIMECandidatePanel : NSPanel
@end
@implementation MSIMECandidatePanel
- (BOOL)canBecomeKeyWindow { return NO; }
- (BOOL)canBecomeMainWindow { return NO; }
@end

@interface MSIMEInputController : IMKInputController <MSIMEFloatingToolbarDelegate>
@end

@implementation MSIMEInputController {
    MSIMEClientSession *_session;
    id _activeClient;
    NSDictionary *_view;
    NSPanel *_panel;
    id<MetasequoiaVoiceService> _voiceService;
    NSUInteger _voiceGeneration;
    id _voiceMouseMonitor;
    MetasequoiaShuangpinKeymapPanel *_keymapPanel;
    MSIMEFloatingToolbarPanel *_toolbar;
    NSString *_preferencesDirectory;
    NSTimer *_preferencesTimer;
    BOOL _preferencesLoading;
    BOOL _verticalCandidates;
    NSUInteger _candidateFontSize;
    NSString *_candidateSkin;
    BOOL _fullWidthInput;
    BOOL _chinesePunctuation;
    BOOL _traditionalOutput;
    BOOL _englishMode;
    BOOL _inputModeShortcutEnabled;
    BOOL _floatingToolbarEnabled;
    BOOL _toolbarHiddenByUser;
    NSString *_resolvedSkinID;
    msime::mac::ResolvedSkin _lightSkin;
    msime::mac::ResolvedSkin _darkSkin;
    NSImage *_skinDecoration;
}

static NSColor *MSIMESkinColor(msime::mac::Rgba color)
{
    return [NSColor colorWithSRGBRed:color.r green:color.g blue:color.b alpha:color.a];
}

static BOOL MSIMEIsDarkAppearance(NSAppearance *appearance)
{
    NSAppearanceName match = [appearance bestMatchFromAppearancesWithNames:@[NSAppearanceNameAqua, NSAppearanceNameDarkAqua]];
    return [match isEqualToString:NSAppearanceNameDarkAqua];
}

- (void)refreshResolvedSkins
{
    const std::filesystem::path root = msime::mac::DefaultSkinsRoot();
    const std::string skinID = _candidateSkin.UTF8String ?: "fluent";
    _lightSkin = msime::mac::ResolveSkin(skinID, false, root);
    _darkSkin = msime::mac::ResolveSkin(skinID, true, root);
    _resolvedSkinID = [_candidateSkin copy];
    _skinDecoration = nil;
    if (_lightSkin.decorationTopDip > 0.0 && !_lightSkin.decorationPath.empty()) {
        _skinDecoration = [[NSImage alloc] initWithContentsOfFile:@(_lightSkin.decorationPath.c_str())];
    }
}

- (void)applyView:(NSDictionary *)view {
    if (![view isKindOfClass:NSDictionary.class] || !_activeClient) return;
    _view = view;
    [self renderCandidates];
}

- (void)refreshToolbar {
    if (!_toolbar) return;
    [_toolbar updateEnglishInputMode:_englishMode
             chinesePunctuationEnabled:_chinesePunctuation
                      fullWidthEnabled:_fullWidthInput
       traditionalChineseOutputEnabled:_traditionalOutput];
    [_toolbar setVisible:_floatingToolbarEnabled && !_toolbarHiddenByUser forDelegate:self];
}

- (void)syncCharacterWidth {
    if (!_session) return;
    NSDictionary *view = [_session setCharacterWidthFull:_fullWidthInput error:nil];
    if (view) [self applyView:view];
}

- (void)syncChinesePunctuation {
    if (!_session) return;
    NSDictionary *view = [_session setChinesePunctuationEnabled:_chinesePunctuation error:nil];
    if (view) [self applyView:view];
}

- (void)setEnglishInputMode:(BOOL)enabled {
    if (enabled == _englishMode) return;
    if (!_session) {
        _englishMode = enabled;
        [[NSUserDefaults standardUserDefaults] setBool:enabled forKey:@"MSIMEClientEnglishMode"];
        [self refreshToolbar];
        return;
    }
    if (enabled && _activeClient && [_view[@"editing_text"] isKindOfClass:NSString.class] &&
        [(NSString *)_view[@"editing_text"] length]) {
        NSDictionary *finished = [_session command:MSIME_FINISH_COMPOSITION error:nil];
        if (!finished) return;
        [self apply:finished];
    }
    NSDictionary *transition = [_session setEnglishMode:enabled error:nil];
    if (!transition) return;
    _englishMode = enabled;
    [[NSUserDefaults standardUserDefaults] setBool:enabled forKey:@"MSIMEClientEnglishMode"];
    [self apply:transition];
    if (!enabled && _activeClient) [self apply:[_session setFocused:YES error:nil]];
    if (enabled) [_panel orderOut:nil];
    [self refreshToolbar];
}

- (void)selectChineseMode:(id)sender { (void)sender; [self setEnglishInputMode:NO]; }
- (void)selectEnglishMode:(id)sender { (void)sender; [self setEnglishInputMode:YES]; }
- (void)showCandidatePreview:(id)sender {
    (void)sender;
    [[MSIMEPreferencesWindowController sharedController] showAndActivate];
}
- (void)showPreferences:(id)sender { (void)sender; [[MSIMEPreferencesWindowController sharedController] showAndActivate]; }
- (void)openCharacterPalette:(id)sender { (void)sender; [[NSApplication sharedApplication] orderFrontCharacterPalette:nil]; }
- (void)checkForUpdates:(id)sender { (void)sender; }
- (void)openWebsite:(id)sender {
    (void)sender;
    [[NSWorkspace sharedWorkspace] openURL:[NSURL URLWithString:@"https://msime.app"]];
}

- (void)cancelVoiceInput {
    ++_voiceGeneration;
    [_voiceService cancel];
    if (_voiceMouseMonitor) [NSEvent removeMonitor:_voiceMouseMonitor];
    _voiceMouseMonitor = nil;
}

- (void)toggleVoiceInput:(id)sender {
    (void)sender;
    if (!_activeClient) return;
#if MSIME_MACOS_VOICE_SERVICE
    if (!_voiceService) _voiceService = [MetasequoiaVoiceInputService new];
#endif
    if (!_voiceService) return;
    if (_voiceService.recording) { [_voiceService stop]; return; }
    if (_voiceService.active) { [self cancelVoiceInput]; return; }
    if (_session && [_view[@"editing_text"] length]) {
        NSDictionary *finished = [_session command:MSIME_FINISH_COMPOSITION error:nil];
        if (!finished) return;
        [self apply:finished];
    }
    id client = _activeClient;
    const NSUInteger generation = ++_voiceGeneration;
    const NSRange selection = [client respondsToSelector:@selector(selectedRange)] ? [client selectedRange] : NSMakeRange(NSNotFound, 0);
    __weak MSIMEInputController *weakSelf = self;
    _voiceMouseMonitor = [NSEvent addGlobalMonitorForEventsMatchingMask:NSEventMaskLeftMouseDown | NSEventMaskRightMouseDown handler:^(NSEvent *event) {
        (void)event;
        [weakSelf cancelVoiceInput];
    }];
    [_voiceService startWithCompletion:^(NSString *text, NSError *error) {
        MSIMEInputController *owner = weakSelf;
        if (!owner || owner->_voiceGeneration != generation || owner->_activeClient != client) return;
        NSRange current = [client respondsToSelector:@selector(selectedRange)] ? [client selectedRange] : NSMakeRange(NSNotFound, 0);
        [owner cancelVoiceInput];
        if (!NSEqualRanges(current, selection)) return;
        if (error) {
            dispatch_async(dispatch_get_main_queue(), ^{
                NSAlert *alert = [NSAlert new];
                alert.messageText = @"语音输入未完成";
                alert.informativeText = @"请检查麦克风权限和语音设置后重试。";
                [alert runModal];
            });
            return;
        }
        if (text.length) [(id<MSIMETextClient>)client insertText:MetasequoiaChineseOutputString(text, owner->_traditionalOutput) replacementRange:NSMakeRange(NSNotFound, NSNotFound)];
    }];
}

#if MSIME_MACOS_VOICE_SERVICE
- (void)showVoiceSettings:(id)sender {
    (void)sender;
    [self cancelVoiceInput];
    [[MetasequoiaVoiceSettingsWindow sharedController] showAndActivate];
}
#endif

- (void)showShuangpinKeymap:(NSMenuItem *)sender {
    if (!_keymapPanel) _keymapPanel = [MetasequoiaShuangpinKeymapPanel new];
    [_keymapPanel setProfileName:sender.representedObject];
    [_keymapPanel updateHighlightedKey:@""];
    [_keymapPanel center];
    [_keymapPanel orderFrontRegardless];
}
- (void)hideShuangpinKeymap:(id)sender { (void)sender; [_keymapPanel orderOut:nil]; }

- (NSMenu *)menu {
    NSMenu *menu = [[NSMenu alloc] initWithTitle:@"水杉输入法"];
    menu.autoenablesItems = NO;
    [menu addItem:CreateInputModeItem(@"中文输入", @selector(selectChineseMode:), self, !_englishMode)];
    [menu addItem:CreateInputModeItem(@"英文输入", @selector(selectEnglishMode:), self, _englishMode)];
    [menu addItem:[NSMenuItem separatorItem]];
    NSMenuItem *preview = [[NSMenuItem alloc] initWithTitle:@"候选预览…"
                                                        action:@selector(showCandidatePreview:)
                                                 keyEquivalent:@""];
    preview.target = self;
    [menu addItem:preview];
    [menu addItem:[[NSMenuItem alloc] initWithTitle:@"表情与符号…" action:@selector(openCharacterPalette:) keyEquivalent:@""]];
    [menu addItem:[[NSMenuItem alloc] initWithTitle:@"检查更新…" action:@selector(checkForUpdates:) keyEquivalent:@""]];
    [menu addItem:[[NSMenuItem alloc] initWithTitle:@"水杉输入法设置…" action:@selector(showPreferences:) keyEquivalent:@""]];

    NSMenuItem *keymap = [[NSMenuItem alloc] initWithTitle:@"双拼键位参考" action:nil keyEquivalent:@""];
    NSMenu *profiles = [[NSMenu alloc] initWithTitle:keymap.title];
    profiles.autoenablesItems = NO;
    NSArray *names = @[@"小鹤双拼", @"自然码双拼", @"首道双拼", @"微软双拼"];
    NSArray *identifiers = @[@"xiaohe", @"ziranma", @"shoudao", @"microsoft"];
    for (NSUInteger index = 0; index < names.count; ++index) {
        NSMenuItem *item = [[NSMenuItem alloc] initWithTitle:names[index] action:@selector(showShuangpinKeymap:) keyEquivalent:@""];
        item.representedObject = identifiers[index];
        item.target = self;
        [profiles addItem:item];
    }
    [profiles addItem:[NSMenuItem separatorItem]];
    NSMenuItem *hide = [[NSMenuItem alloc] initWithTitle:@"隐藏键位参考" action:@selector(hideShuangpinKeymap:) keyEquivalent:@""];
    hide.target = self;
    [profiles addItem:hide];
    keymap.submenu = profiles;
    [menu addItem:keymap];
#if MSIME_MACOS_VOICE_SERVICE
    for (NSArray *entry in @[@[@"语音输入（Control + Option + V）", NSStringFromSelector(@selector(toggleVoiceInput:))], @[@"语音设置…", NSStringFromSelector(@selector(showVoiceSettings:))]]) {
        NSMenuItem *item = [[NSMenuItem alloc] initWithTitle:entry[0] action:NSSelectorFromString(entry[1]) keyEquivalent:@""];
        item.target = self;
        [menu addItem:item];
    }
#endif
    return menu;
}

- (void)activateServer:(id)sender {
    [super activateServer:sender];
    _activeClient = sender;
    _fullWidthInput = [[NSUserDefaults standardUserDefaults] boolForKey:@"MSIMEClientFullWidthInput"];
    _englishMode = [[NSUserDefaults standardUserDefaults] boolForKey:@"MSIMEClientEnglishMode"];
    _chinesePunctuation = [[NSUserDefaults standardUserDefaults] objectForKey:@"MSIMEClientChinesePunctuation"] == nil ||
                          [[NSUserDefaults standardUserDefaults] boolForKey:@"MSIMEClientChinesePunctuation"];
    _floatingToolbarEnabled = YES;
    _toolbarHiddenByUser = NO;
    _inputModeShortcutEnabled = [[NSUserDefaults standardUserDefaults] objectForKey:@"MSIMEClientInputModeShortcut"] == nil ||
                                [[NSUserDefaults standardUserDefaults] boolForKey:@"MSIMEClientInputModeShortcut"];
    _toolbar = [MSIMEFloatingToolbarPanel sharedPanel];
    [_toolbar activateForDelegate:self visible:_floatingToolbarEnabled];
    _verticalCandidates = YES;
    _candidateFontSize = 18;
    _candidateSkin = @"fluent";
    _traditionalOutput = [[NSUserDefaults standardUserDefaults] boolForKey:@"MSIMEClientTraditionalChineseOutput"];
    if (!_session) {
        NSString *path = [[NSBundle mainBundle] pathForResource:@"runtime-options" ofType:@"json"];
        if (!path) {
            NSURL *support = [[[NSFileManager defaultManager] URLsForDirectory:NSApplicationSupportDirectory inDomains:NSUserDomainMask] firstObject];
            path = [[support URLByAppendingPathComponent:@"app.msime.client.preview/runtime-options.json"] path];
        }
        NSData *data = [NSData dataWithContentsOfFile:path];
        NSDictionary *options = data ? [NSJSONSerialization JSONObjectWithData:data options:0 error:nil] : nil;
        if ([options isKindOfClass:NSDictionary.class]) {
            NSDictionary *preferences = options[@"preferences"];
            if ([preferences isKindOfClass:NSDictionary.class]) {
                if ([preferences[@"chinese_punctuation"] isKindOfClass:NSNumber.class]) {
                    _chinesePunctuation = [preferences[@"chinese_punctuation"] boolValue];
                    [[NSUserDefaults standardUserDefaults] setBool:_chinesePunctuation forKey:@"MSIMEClientChinesePunctuation"];
                }
                NSDictionary *toolbar = preferences[@"floating_toolbar"];
                if ([toolbar isKindOfClass:NSDictionary.class] && [toolbar[@"enabled"] isKindOfClass:NSNumber.class]) {
                    _floatingToolbarEnabled = [toolbar[@"enabled"] boolValue];
                }
            }
            _verticalCandidates = ![options[@"candidate_orientation"] isEqual:@"horizontal"];
            if ([preferences isKindOfClass:NSDictionary.class]) {
                if ([preferences[@"traditional_chinese_output"] isKindOfClass:NSNumber.class]) {
                    _traditionalOutput = [preferences[@"traditional_chinese_output"] boolValue];
                    [[NSUserDefaults standardUserDefaults] setBool:_traditionalOutput forKey:@"MSIMEClientTraditionalChineseOutput"];
                }
                id orientation = preferences[@"candidate_orientation"];
                if ([orientation isKindOfClass:NSString.class]) {
                    _verticalCandidates = metasequoia::mac::IsVerticalCandidateOrientation(orientation);
                }
                id fontSize = preferences[@"candidate_font_size"];
                if ([fontSize isKindOfClass:NSNumber.class]) {
                    _candidateFontSize = metasequoia::mac::NormalizeCandidateFontSize([fontSize unsignedIntegerValue]);
                }
                id skin = preferences[@"candidate_skin"];
                if ([skin isKindOfClass:NSString.class]) {
                    const std::string normalized = msime::mac::NormalizeSkinId([(NSString *)skin UTF8String] ?: "");
                    _candidateSkin = [NSString stringWithUTF8String:normalized.c_str()];
                }
            }
            [self refreshResolvedSkins];
            _session = [[MSIMEClientSession alloc] initWithOptions:options error:nil];
            id directory = options[@"preferences_directory"];
            if ([directory isKindOfClass:NSString.class] && [directory isAbsolutePath]) _preferencesDirectory = [directory copy];
        }
    }
    [self refreshToolbar];
    if (_session) {
        [self syncCharacterWidth];
        [self syncChinesePunctuation];
        if (_englishMode) [self apply:[_session setEnglishMode:YES error:nil]];
        else [self apply:[_session setFocused:YES error:nil]];
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
            NSDictionary *presentation = result[@"presentation"];
            if ([presentation isKindOfClass:NSDictionary.class]) {
                id orientation = presentation[@"candidate_orientation"];
                if ([orientation isKindOfClass:NSString.class]) {
                    controller->_verticalCandidates = metasequoia::mac::IsVerticalCandidateOrientation(orientation);
                }
                id fontSize = presentation[@"candidate_font_size"];
                if ([fontSize isKindOfClass:NSNumber.class]) {
                    controller->_candidateFontSize = metasequoia::mac::NormalizeCandidateFontSize([fontSize unsignedIntegerValue]);
                }
                id skin = presentation[@"candidate_skin"];
                if ([skin isKindOfClass:NSString.class]) {
                    const std::string normalized = msime::mac::NormalizeSkinId([(NSString *)skin UTF8String] ?: "");
                    controller->_candidateSkin = [NSString stringWithUTF8String:normalized.c_str()];
                }
                NSDictionary *toolbar = presentation[@"floating_toolbar"];
                if ([toolbar isKindOfClass:NSDictionary.class] &&
                    [toolbar[@"enabled"] isKindOfClass:NSNumber.class]) {
                    controller->_floatingToolbarEnabled = [toolbar[@"enabled"] boolValue];
                }
            }
            [controller refreshResolvedSkins];
            controller->_view = result[@"view"];
            [controller renderCandidates];
            [controller refreshToolbar];
        }
    }];
}

- (void)deactivateServer:(id)sender {
    [self cancelVoiceInput];
    [_toolbar deactivateForDelegate:self];
    [_keymapPanel orderOut:nil];
    [_preferencesTimer invalidate];
    _preferencesTimer = nil;
    if (_session) [self apply:[_session setFocused:NO error:nil]];
    [_panel orderOut:nil];
    _activeClient = nil;
    [super deactivateServer:sender];
}

- (void)floatingToolbarDidRequestToggleInputMode:(MSIMEFloatingToolbarPanel *)toolbar {
    (void)toolbar;
    [self setEnglishInputMode:!_englishMode];
}

- (void)floatingToolbarDidRequestTogglePunctuation:(MSIMEFloatingToolbarPanel *)toolbar {
    (void)toolbar;
    if (_session && _activeClient && [_view[@"editing_text"] isKindOfClass:NSString.class] &&
        [(NSString *)_view[@"editing_text"] length]) {
        NSDictionary *finished = [_session command:MSIME_FINISH_COMPOSITION error:nil];
        if (!finished) return;
        [self apply:finished];
    }
    _chinesePunctuation = !_chinesePunctuation;
    [[NSUserDefaults standardUserDefaults] setBool:_chinesePunctuation forKey:@"MSIMEClientChinesePunctuation"];
    [self syncChinesePunctuation];
    [self refreshToolbar];
}

- (void)floatingToolbarDidRequestToggleFullWidth:(MSIMEFloatingToolbarPanel *)toolbar {
    (void)toolbar;
    _fullWidthInput = !_fullWidthInput;
    [[NSUserDefaults standardUserDefaults] setBool:_fullWidthInput forKey:@"MSIMEClientFullWidthInput"];
    [self syncCharacterWidth];
    [self refreshToolbar];
}

- (void)floatingToolbarDidRequestToggleTraditionalOutput:(MSIMEFloatingToolbarPanel *)toolbar {
    (void)toolbar;
    _traditionalOutput = !_traditionalOutput;
    [[NSUserDefaults standardUserDefaults] setBool:_traditionalOutput forKey:@"MSIMEClientTraditionalChineseOutput"];
    [self refreshToolbar];
    [self renderCandidates];
}

- (void)floatingToolbarDidRequestOpenCharacterPalette:(MSIMEFloatingToolbarPanel *)toolbar {
    (void)toolbar;
    [self openCharacterPalette:nil];
}

- (void)floatingToolbarDidRequestOpenSettings:(MSIMEFloatingToolbarPanel *)toolbar {
    (void)toolbar;
    [self showPreferences:nil];
}

- (void)floatingToolbarDidRequestCheckForUpdates:(MSIMEFloatingToolbarPanel *)toolbar {
    (void)toolbar;
    [self checkForUpdates:nil];
}

- (void)floatingToolbarDidRequestOpenWebsite:(MSIMEFloatingToolbarPanel *)toolbar {
    (void)toolbar;
    [[NSWorkspace sharedWorkspace] openURL:[NSURL URLWithString:@"https://msime.app"]];
}

- (void)floatingToolbarDidRequestHide:(MSIMEFloatingToolbarPanel *)toolbar {
    (void)toolbar;
    _toolbarHiddenByUser = YES;
    [self refreshToolbar];
}

- (void)dealloc { [_preferencesTimer invalidate]; [_voiceService cancel]; if (_voiceMouseMonitor) [NSEvent removeMonitor:_voiceMouseMonitor]; }

- (NSUInteger)recognizedEvents:(id)sender {
    (void)sender;
    return NSEventMaskKeyDown;
}

- (BOOL)handleEvent:(NSEvent *)event client:(id)sender {
    if (event.type != NSEventTypeKeyDown) return NO;
    if (sender != _activeClient) [self cancelVoiceInput];
#if MSIME_MACOS_VOICE_SERVICE
    NSEventModifierFlags voiceModifiers = event.modifierFlags & (NSEventModifierFlagControl | NSEventModifierFlagOption | NSEventModifierFlagCommand | NSEventModifierFlagShift);
    if (event.keyCode == 9 && voiceModifiers == (NSEventModifierFlagControl | NSEventModifierFlagOption)) {
        if (!event.isARepeat && sender == _activeClient) [self toggleVoiceInput:sender];
        return YES;
    }
#endif
    if (_voiceService.active) {
        [self cancelVoiceInput];
        if (event.keyCode == 53) return YES;
    }
    if (_inputModeShortcutEnabled && msime::mac::IsInputModeToggle(event.keyCode, event.modifierFlags)) {
        if (!event.isARepeat) [self setEnglishInputMode:!_englishMode];
        return YES;
    }
    if (msime::mac::IsFullWidthInputToggle(event.keyCode, event.modifierFlags)) {
        if (!event.isARepeat) {
            _fullWidthInput = !_fullWidthInput;
            [[NSUserDefaults standardUserDefaults] setBool:_fullWidthInput forKey:@"MSIMEClientFullWidthInput"];
            [self syncCharacterWidth];
            [self refreshToolbar];
        }
        return YES;
    }
    if (!_session) return NO;
    if (_englishMode) return NO;
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
    // Candidate navigation uses the runtime's highlight; hidden panels retain editing commands.
    if (_panel.isVisible) {
        switch (event.keyCode) {
            case 123: case 124:
                if (_verticalCandidates) return YES;
                command = event.keyCode == 123 ? MSIME_PREVIOUS_CANDIDATE : MSIME_NEXT_CANDIDATE;
                break;
            case 115: command = MSIME_FIRST_CANDIDATE_ON_PAGE; break;
            case 119: command = MSIME_LAST_CANDIDATE_ON_PAGE; break;
        }
    }
    if (command == UINT32_MAX) switch (event.keyCode) {
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
    if ([transition[@"commit"] isKindOfClass:NSString.class] &&
        _traditionalOutput) {
        NSMutableDictionary *converted = [transition mutableCopy];
        converted[@"commit"] = MetasequoiaChineseOutputString(transition[@"commit"], YES);
        transition = converted;
    }
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
    if (![_resolvedSkinID isEqualToString:_candidateSkin]) [self refreshResolvedSkins];
    NSFont *font = [NSFont systemFontOfSize:(CGFloat)metasequoia::mac::NormalizeCandidateFontSize(_candidateFontSize)];
    const BOOL dark = MSIMEIsDarkAppearance(_panel.effectiveAppearance ?: NSApp.effectiveAppearance);
    const msime::mac::ResolvedSkin &skin = dark ? _darkSkin : _lightSkin;
    const msime::mac::SkinTokens &tokens = skin.tokens;
    const CGFloat inset = MAX(2.0, static_cast<CGFloat>(tokens.pad));
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
    const CGFloat navigationWidth = !vertical && paging ? 56 : 0;
    const CGFloat availableWidth = MAX(80, visible.size.width - 20 - navigationWidth - 2 * inset);
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
    CGFloat panelWidth = vertical ? (paging ? MAX(candidateWidth, 64) : candidateWidth)
                                  : candidateWidth + navigationWidth + 2 * inset;
    panelWidth = MAX(panelWidth, MAX(static_cast<CGFloat>(skin.minWidthDip), static_cast<CGFloat>(skin.decorationWidthDip)));
    if (!_panel) {
        _panel = [[MSIMECandidatePanel alloc] initWithContentRect:NSZeroRect styleMask:NSWindowStyleMaskBorderless | NSWindowStyleMaskNonactivatingPanel backing:NSBackingStoreBuffered defer:NO];
        _panel.level = NSPopUpMenuWindowLevel;
        _panel.hasShadow = YES;
        _panel.hidesOnDeactivate = NO;
        _panel.becomesKeyOnlyIfNeeded = YES;
        _panel.collectionBehavior = NSWindowCollectionBehaviorCanJoinAllSpaces | NSWindowCollectionBehaviorFullScreenAuxiliary;
        _panel.backgroundColor = NSColor.clearColor;
        _panel.opaque = NO;
        _panel.contentView.wantsLayer = YES;
        _panel.contentView.layer.cornerRadius = 8.0;
        _panel.contentView.layer.masksToBounds = YES;
    }
    const CGFloat navigationHeight = paging && vertical ? 26 : 0;
    const CGFloat decorationHeight = static_cast<CGFloat>(skin.decorationTopDip);
    const CGFloat height = vertical ? candidates.count * rowHeight + navigationHeight + 2 * inset + decorationHeight
                                    : rowHeight + 2 * inset + decorationHeight;
    [_panel setContentSize:NSMakeSize(panelWidth, height)];
    MSIMECandidateChromeView *content = [[MSIMECandidateChromeView alloc] initWithFrame:NSMakeRect(0, 0, panelWidth, height)];
    content.fillColor = MSIMESkinColor(tokens.surface);
    content.strokeColor = MSIMESkinColor(tokens.border);
    content.cornerRadius = tokens.radius;
    content.lineWidth = tokens.borderWidth;
    NSUInteger slot = 0;
    const CGFloat contentTop = height - inset - decorationHeight - navigationHeight;
    for (NSDictionary *candidate in candidates) {
        NSString *title = [NSString stringWithFormat:@"%lu  %@", (unsigned long)(slot + 1), candidate[@"text"]];
        MSIMECandidateButton *button = [MSIMECandidateButton buttonWithTitle:title target:self action:@selector(selectCandidate:)];
        button.candidateID = candidate[@"id"];
        if (vertical) {
            button.frame = NSMakeRect(inset, contentTop - (++slot * rowHeight), panelWidth - 2 * inset, rowHeight);
        } else {
            CGFloat x = inset;
            for (NSUInteger index = 0; index < slot; ++index) x += itemWidths[index].doubleValue;
            button.frame = NSMakeRect(x, inset, itemWidths[slot].doubleValue, rowHeight);
            ++slot;
        }
        button.font = font;
        button.candidateHighlighted = [candidate[@"highlighted"] boolValue];
        button.fillColor = MSIMESkinColor(tokens.selected);
        button.titleColor = MSIMESkinColor(button.candidateHighlighted ? tokens.selectedText : tokens.text);
        button.numberColor = MSIMESkinColor(tokens.number);
        button.barColor = MSIMESkinColor(tokens.accent);
        button.showSelectedBar = tokens.showSelectedBar;
        button.bordered = NO;
        button.lineBreakMode = NSLineBreakByTruncatingTail;
        button.toolTip = candidate[@"text"];
        button.alignment = NSTextAlignmentLeft;
        [content addSubview:button];
    }
    if (paging) {
        for (NSUInteger index = 0; index < 2; ++index) {
            NSButton *button = [NSButton buttonWithTitle:index == 0 ? @"‹" : @"›"
                                                    target:self
                                                    action:@selector(changeCandidatePage:)];
            button.frame = vertical ? NSMakeRect(inset + index * 28, inset, 28, 26)
                                    : NSMakeRect(candidateWidth + inset + index * 28, inset, 28, rowHeight);
            button.bordered = NO;
            button.contentTintColor = MSIMESkinColor(tokens.text);
            button.font = font;
            button.tag = index == 0 ? -1 : -2;
            button.enabled = index == 0 ? hasPreviousPage : hasNextPage;
            button.accessibilityLabel = index == 0 ? @"上一页候选" : @"下一页候选";
            [content addSubview:button];
        }
    }
    if (decorationHeight > 0.0 && _skinDecoration && skin.decorationWidthDip > 0.0) {
        NSImageView *decoration = [[NSImageView alloc]
            initWithFrame:NSMakeRect(panelWidth - skin.decorationWidthDip, height - decorationHeight,
                                     skin.decorationWidthDip, decorationHeight)];
        decoration.image = _skinDecoration;
        decoration.imageScaling = NSImageScaleProportionallyUpOrDown;
        decoration.imageAlignment = NSImageAlignTopRight;
        [content addSubview:decoration];
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
