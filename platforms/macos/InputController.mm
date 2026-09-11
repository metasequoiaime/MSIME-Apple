#import <AppKit/AppKit.h>
#import <InputMethodKit/InputMethodKit.h>
#import "MSIMEClientSession.h"
#import "../../shared/apple/TextClient.h"
#include "msime_client.h"
#import "CandidatePlacement.h"
#import "UpdateController.h"
#import "DictionaryWindowController.h"
#import "ClientDictionaryRuntime.h"
#import "AppearancePreferences.h"
#import "PreferencesWindowController.h"
#import "BackendAccountEntry.h"
#include "PreferenceSaveState.h"
#include "PreferenceSnapshotMerge.h"
#import "CandidateChrome.h"
#include "CandidateSkin.h"
#import "ChineseTextConversion.h"
#include "FullWidthInput.h"
#import "ShuangpinKeymapPanel.h"
#import "FloatingToolbarPanel.h"
#import "VoiceInputService.h"
#import "VoiceSettings.h"
#include "WubiCommitPolicy.h"

static BOOL MSIMEScriptConversionApplies(id value) {
    if (![value isKindOfClass:NSDictionary.class] || ![value[@"scheme"] isKindOfClass:NSNumber.class]) return NO;
    if ([value[@"scheme"] integerValue] < 0 || [value[@"scheme"] integerValue] > 2) return NO;
    NSString *mode = value[@"local_mode"];
    return ![mode isKindOfClass:NSString.class] || ![mode isEqualToString:@"unicode"];
}

static NSString *CandidateDisplay(NSDictionary *candidate, BOOL traditional) {
    NSString *annotation = candidate[@"annotation"];
    NSString *text = candidate[@"text"];
    if ([annotation isKindOfClass:NSString.class]) text = [text stringByAppendingString:annotation];
    return MSIMEChineseOutputString(text, traditional);
}

static NSColor *SkinColor(msime::mac::Rgba color) {
    return [NSColor colorWithSRGBRed:color.r green:color.g blue:color.b alpha:color.a];
}

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
    MSIMEVoiceInputService *_voiceService;
    uint64_t _voiceGeneration;
    id _activeClient;
    NSDictionary *_view;
    NSPanel *_panel;
    MSIMEShuangpinKeymapPanel *_keymapPanel;
    MSIMEFloatingToolbarPanel *_toolbar;
    NSString *_preferencesDirectory;
    NSTimer *_preferencesTimer;
    BOOL _preferencesLoading;
    MSIMEPreferenceSaveState _preferenceSaveState;
    MSIMEAppearancePreferences *_appearance;
    NSUInteger _requestedPageSize;
    BOOL _skinShowsSelectedBar;
    BOOL _focusPending;
    MSIMEDictionaryWindowController *_dictionaryWindow;
}

- (void)ensureAppearance {
    if (_appearance) return;
    _appearance = [MSIMEAppearancePreferences sharedPreferences];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(appearanceChanged:) name:MSIMEAppearanceDidChangeNotification object:_appearance];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(appearanceChanged:) name:MSIMEVoiceSettingsDidChangeNotification object:nil];
}
- (void)appearanceChanged:(NSNotification *)notification {
    (void)notification;
    if (_appearance.englishMode && _activeClient && ([_view[@"editing_text"] length] || [_view[@"candidates"] count])) {
        [self apply:[_session command:MSIME_FINISH_COMPOSITION error:nil]];
    }
    [self syncPageSize];
    [self syncPunctuation];
    [_toolbar updateEnglishInputMode:_appearance.englishMode chinesePunctuationEnabled:_appearance.chinesePunctuation fullWidthEnabled:_appearance.fullWidthInput traditionalChineseOutputEnabled:_appearance.traditionalOutput];
    if (_activeClient) [self renderCandidates];
    [self persistAppearancePreferences];
}
- (void)persistAppearancePreferences {
    if (!_preferencesDirectory || !_session) return;
    if (!_preferenceSaveState.request()) return;
    NSString *directory = [_preferencesDirectory copy];
    // Capture all host-owned fields together on the main thread. Both CAS
    // attempts use this same snapshot; later changes schedule a fresh save.
    NSDictionary *overrides = [_appearance sharedPreferencesByMerging:@{}];
    __weak MSIMEInputController *weakSelf = self;
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{
        NSError *loadError = nil;
        NSDictionary *snapshot = [MSIMEClientSession loadPreferencesInDirectory:directory error:&loadError];
        NSDictionary *preferences = snapshot ? MSIMEMergePreferenceSnapshot(snapshot[@"preferences"], overrides) : nil;
        uint64_t revision = [snapshot[@"revision"] unsignedLongLongValue];
        NSError *saveError = nil;
        NSDictionary *saved = nil;
        if (preferences) {
            saved = [MSIMEClientSession savePreferencesInDirectory:directory expectedRevision:revision snapshot:@{ @"format_version": @1, @"revision": @(revision), @"preferences": preferences } error:&saveError];
        }
        if (!saved && snapshot) {
            NSError *retryLoadError = nil;
            NSDictionary *latest = [MSIMEClientSession loadPreferencesInDirectory:directory error:&retryLoadError];
            NSDictionary *latestPreferences = latest ? MSIMEMergePreferenceSnapshot(latest[@"preferences"], overrides) : nil;
            if (latestPreferences) {
                saveError = nil;
                saved = [MSIMEClientSession savePreferencesInDirectory:directory expectedRevision:[latest[@"revision"] unsignedLongLongValue] snapshot:@{ @"format_version": @1, @"revision": latest[@"revision"] ?: @0, @"preferences": latestPreferences } error:&saveError];
            }
        }
        dispatch_async(dispatch_get_main_queue(), ^{
            MSIMEInputController *controller = weakSelf;
            if (!controller) return;
            const bool again = controller->_preferenceSaveState.finish();
            if (saved && !saveError) [controller reloadPreferences];
            if (again) [controller persistAppearancePreferences];
        });
    });
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
- (void)syncPunctuation {
    if (_session) [self apply:[_session setChinesePunctuationEnabled:_appearance.chinesePunctuation error:nil]];
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
    for (NSUInteger script = 0; script < 2; ++script) {
        NSMenuItem *item = [[NSMenuItem alloc] initWithTitle:script ? @"繁体输出" : @"简体输出" action:script ? @selector(selectTraditionalOutput:) : @selector(selectSimplifiedOutput:) keyEquivalent:@""];
        item.target = self;
        item.state = _appearance.traditionalOutput == (script == 1) ? NSControlStateValueOn : NSControlStateValueOff;
        [menu addItem:item];
    }
    [menu addItem:NSMenuItem.separatorItem];
    NSMenuItem *palette = [[NSMenuItem alloc] initWithTitle:@"表情与符号…" action:@selector(openCharacterPalette:) keyEquivalent:@""];
    palette.target = self;
    [menu addItem:palette];
    NSMenuItem *emoji = [[NSMenuItem alloc] initWithTitle:@"水杉表情面板…" action:@selector(showEmoji:) keyEquivalent:@""];
    emoji.target = self;
    [menu addItem:emoji];
    NSMenuItem *item = [[NSMenuItem alloc] initWithTitle:@"候选设置…" action:@selector(showAppearance:) keyEquivalent:@""];
    item.target = self;
    [menu addItem:item];
    NSMenuItem *dictionary = [[NSMenuItem alloc] initWithTitle:@"个人词典…" action:@selector(showDictionary:) keyEquivalent:@""];
    dictionary.target = self;
    [menu addItem:dictionary];
    NSMenuItem *account = [[NSMenuItem alloc] initWithTitle:@"账户状态…" action:@selector(showAccount:) keyEquivalent:@""]; account.target = self; [menu addItem:account];
    NSMenuItem *clipboard = [[NSMenuItem alloc] initWithTitle:@"云剪贴板…" action:@selector(showCloudClipboard:) keyEquivalent:@""]; clipboard.target = self; [menu addItem:clipboard];
    NSMenuItem *handwriting = [[NSMenuItem alloc] initWithTitle:@"手写输入…" action:@selector(showHandwriting:) keyEquivalent:@""]; handwriting.target = self; [menu addItem:handwriting];
    NSMenuItem *prepare = [[NSMenuItem alloc] initWithTitle:@"准备词库…" action:@selector(prepareDictionary:) keyEquivalent:@""];
    prepare.target = self;
    [menu addItem:prepare];
    [menu addItem:NSMenuItem.separatorItem];
    NSMenuItem *updates = [[NSMenuItem alloc] initWithTitle:@"检查更新…" action:@selector(checkForUpdates:) keyEquivalent:@""];
    updates.target = self;
    [menu addItem:updates];
    NSMenuItem *website = [[NSMenuItem alloc] initWithTitle:@"官方网站" action:@selector(openWebsite:) keyEquivalent:@""];
    website.target = self;
    [menu addItem:website];
    NSMenuItem *voice = [[NSMenuItem alloc] initWithTitle:@"开始/结束语音输入" action:@selector(toggleVoiceInput:) keyEquivalent:@""];
    voice.target = self;
    [menu addItem:voice];
    NSMenuItem *voiceSettings = [[NSMenuItem alloc] initWithTitle:@"语音输入设置…" action:@selector(showVoiceSettings:) keyEquivalent:@""];
    voiceSettings.target = self;
    [menu addItem:voiceSettings];
    return menu;
}
- (void)showAccount:(id)sender {
    (void)sender;
    if (!MSIMEOpenBackendAccount(NSClassFromString(@"MSIMEBackendAccountWindow"))) {
        NSAlert *alert = [[NSAlert alloc] init];
        alert.messageText = @"账户窗口暂不可用";
        alert.informativeText = @"请重新启动输入法；若仍无法打开，请检查安装是否完整。";
        [alert runModal];
    }
}
- (void)showCloudClipboard:(id)sender {
    if (!MSIMEOpenBackendClipboard(NSClassFromString(@"MSIMEBackendAccountWindow"))) {
        [self showAccount:sender];
    }
}
- (void)showHandwriting:(id)sender {
    (void)sender;
    Class bridge = NSClassFromString(@"MSIMEBackendWindowBridge");
    id shared = [bridge respondsToSelector:@selector(shared)] ? [bridge performSelector:@selector(shared)] : nil;
    if (![shared respondsToSelector:@selector(showHandwriting)]) { [self showAccount:nil]; return; }
    [shared performSelector:@selector(showHandwriting)];
}
- (void)showEmoji:(id)sender {
    (void)sender;
    Class bridge = NSClassFromString(@"MSIMEBackendWindowBridge");
    id shared = [bridge respondsToSelector:@selector(shared)] ? [bridge performSelector:@selector(shared)] : nil;
    if ([shared respondsToSelector:@selector(showEmoji)]) [shared performSelector:@selector(showEmoji)];
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
    [_keymapPanel orderOut:nil];
}
- (void)selectChineseMode:(id)sender { (void)sender; [self setEnglishInputMode:NO]; }
- (void)selectSimplifiedOutput:(id)sender { (void)sender; [self ensureAppearance]; _appearance.traditionalOutput = NO; }
- (void)selectTraditionalOutput:(id)sender { (void)sender; [self ensureAppearance]; _appearance.traditionalOutput = YES; }
- (void)selectEnglishMode:(id)sender { (void)sender; [self setEnglishInputMode:YES]; }
- (void)showSystemCharacterPalette { [NSApp orderFrontCharacterPalette:nil]; }
- (void)checkForUpdates:(id)sender { (void)sender; [[MSIMEUpdateController sharedController] checkForUpdates:nil]; }
- (void)showVoiceSettings:(id)sender { (void)sender; [[MSIMEVoiceSettings sharedSettings] showAndActivate]; }
- (void)toggleVoiceInput:(id)sender {
    (void)sender;
    if (!_session) [self prepareSession];
    if (!_session) return;
    if (!_voiceService) _voiceService = [[MSIMEVoiceInputService alloc] init];
    if (_voiceService.active) { [_voiceService stopMicrophoneCapture]; [_voiceService stopTranscription]; [_voiceService cancelWithError:nil]; return; }
    __weak MSIMEInputController *weakSelf = self;
    void (^start)(void) = ^{
        MSIMEInputController *controller = weakSelf;
        if (!controller || !controller->_session) return;
        NSError *error = nil;
        if (![controller->_voiceService startWithSession:controller->_session generation:&controller->_voiceGeneration error:&error]) return;
        NSString *language = [[NSUserDefaults standardUserDefaults] stringForKey:@"MSIMEClientVoiceLanguage"] ?: @"zh-CN";
        if (![controller->_voiceService startTranscriptionWithLanguage:language textHandler:^(NSString *text, BOOL final) {
            (void)final;
            [controller->_voiceService applyText:text generation:controller->_voiceGeneration completion:^(NSDictionary *result, NSError *applyError) { if (result && !applyError) [controller apply:result]; }];
        } error:&error]) { [controller->_voiceService cancelWithError:nil]; return; }
        if (![controller->_voiceService startMicrophoneCapture:^(AVAudioPCMBuffer *buffer) { (void)buffer; } error:&error]) { [controller->_voiceService stopTranscription]; [controller->_voiceService cancelWithError:nil]; }
    };
    if (_voiceService.speechAuthorizationStatus != SFSpeechRecognizerAuthorizationStatusAuthorized) {
        [_voiceService requestSpeechPermission:^(BOOL granted) { if (granted) [weakSelf toggleVoiceInput:nil]; }];
        return;
    }
    if (_voiceService.microphoneAuthorizationStatus != AVAuthorizationStatusAuthorized) {
        [_voiceService requestMicrophonePermission:^(BOOL granted) { if (granted) [weakSelf toggleVoiceInput:nil]; }];
        return;
    }
    start();
}
- (void)openWebsite:(id)sender { (void)sender; [[NSWorkspace sharedWorkspace] openURL:[NSURL URLWithString:@"https://msime.app/"]]; }
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
    (void)sender;
    [[MSIMEPreferencesWindowController sharedController] showAndActivate];
}
- (void)showDictionary:(id)sender { (void)sender; if (!_session) [self prepareSession]; if (!_session) return; _dictionaryWindow = [[MSIMEDictionaryWindowController alloc] initWithOptions:_session.hostOptions]; [_dictionaryWindow showWindow:nil]; [NSApp activateIgnoringOtherApps:YES]; }
- (void)prepareDictionary:(id)sender {
    (void)sender;
    if (_session && _activeClient) {
        NSDictionary *finished = [_session command:MSIME_FINISH_COMPOSITION error:nil];
        if (!finished) return;
        [self apply:finished];
        [_session setFocused:NO error:nil];
        [_session closeWithError:nil];
        _session = nil;
        [_preferencesTimer invalidate];
        _preferencesTimer = nil;
    }
    NSOpenPanel *panel = [NSOpenPanel openPanel];
    panel.canChooseFiles = NO; panel.canChooseDirectories = YES; panel.allowsMultipleSelection = NO;
    [panel beginWithCompletionHandler:^(NSModalResponse response) {
        if (response != NSModalResponseOK || !panel.URL) return;
        NSURL *support = [[NSFileManager defaultManager] URLsForDirectory:NSApplicationSupportDirectory inDomains:NSUserDomainMask].firstObject;
        NSURL *state = [support URLByAppendingPathComponent:@"app.msime.client.preview" isDirectory:YES];
        [MSIMEDictionaryRuntime prepareResourcesDirectory:panel.URL.path stateRoot:state.path completion:^(NSDictionary *options, NSError *error) {
            if (!options) { NSAlert *alert = [NSAlert new]; alert.messageText = @"词库准备失败"; alert.informativeText = error.localizedDescription ?: @"无法准备词库"; [alert runModal]; return; }
            NSData *data = [NSJSONSerialization dataWithJSONObject:options options:0 error:nil];
            NSURL *target = [state URLByAppendingPathComponent:@"runtime-options.json"];
            [[NSFileManager defaultManager] createDirectoryAtURL:state withIntermediateDirectories:YES attributes:nil error:nil];
            [data writeToURL:target options:NSDataWritingAtomic error:nil];
        }];
    }];
}

- (void)activateServer:(id)sender {
    [super activateServer:sender];
    [self ensureAppearance];
    _toolbar = [MSIMEFloatingToolbarPanel sharedPanel];
    [_toolbar activateForDelegate:self visible:_appearance.floatingToolbarEnabled];
    _activeClient = sender;
    [[NSNotificationCenter defaultCenter] removeObserver:self name:MSIMEClientSessionDidReplaceSnapshotNotification object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(snapshotSessionReplaced:) name:MSIMEClientSessionDidReplaceSnapshotNotification object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(handwritingCandidateSelected:) name:@"MSIMEHandwritingCandidateSelected" object:nil];
    [_toolbar updateEnglishInputMode:_appearance.englishMode chinesePunctuationEnabled:_appearance.chinesePunctuation fullWidthEnabled:_appearance.fullWidthInput traditionalChineseOutputEnabled:_appearance.traditionalOutput];
    [self ensureAppearance];
    _focusPending = _appearance.englishMode;
    if (!_appearance.englishMode) [self prepareSession];
}

- (void)handwritingCandidateSelected:(NSNotification *)notification {
    NSString *text = notification.userInfo[@"text"];
    if (![text isKindOfClass:NSString.class] || text.length == 0 || !_activeClient) return;
    [_activeClient insertText:text replacementRange:NSMakeRange(NSNotFound, 0)];
}

- (void)snapshotSessionReplaced:(NSNotification *)notification {
    if (notification.object != _session) return;
    _view = @{};
    [_panel orderOut:nil];
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
        [self syncPunctuation];
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
    [_toolbar deactivateForDelegate:self];
    [_keymapPanel orderOut:nil];
    [_preferencesTimer invalidate];
    _preferencesTimer = nil;
    if (_session) [self apply:[_session setFocused:NO error:nil]];
    [_panel orderOut:nil];
    _activeClient = nil;
    [super deactivateServer:sender];
}

- (void)floatingToolbarDidRequestToggleInputMode:(MSIMEFloatingToolbarPanel *)toolbar { (void)toolbar; [self setEnglishInputMode:!_appearance.englishMode]; }
- (void)floatingToolbarDidRequestTogglePunctuation:(MSIMEFloatingToolbarPanel *)toolbar {
    (void)toolbar;
    [self ensureAppearance];
    if (_session && _activeClient && [_view[@"editing_text"] length]) {
        NSDictionary *finished = [_session command:MSIME_FINISH_COMPOSITION error:nil];
        if (!finished) return;
        [self apply:finished];
    }
    _appearance.chinesePunctuation = !_appearance.chinesePunctuation;
    [self syncPunctuation];
    [_toolbar updateEnglishInputMode:_appearance.englishMode chinesePunctuationEnabled:_appearance.chinesePunctuation fullWidthEnabled:_appearance.fullWidthInput traditionalChineseOutputEnabled:_appearance.traditionalOutput];
}
- (void)floatingToolbarDidRequestToggleFullWidth:(MSIMEFloatingToolbarPanel *)toolbar { (void)toolbar; _appearance.fullWidthInput = !_appearance.fullWidthInput; }
- (void)floatingToolbarDidRequestToggleTraditionalOutput:(MSIMEFloatingToolbarPanel *)toolbar { (void)toolbar; _appearance.traditionalOutput = !_appearance.traditionalOutput; }
- (void)floatingToolbarDidRequestOpenCharacterPalette:(MSIMEFloatingToolbarPanel *)toolbar { (void)toolbar; [self openCharacterPalette:nil]; }
- (void)floatingToolbarDidRequestOpenSettings:(MSIMEFloatingToolbarPanel *)toolbar { (void)toolbar; [self showAppearance:nil]; }
- (void)floatingToolbarDidRequestCheckForUpdates:(MSIMEFloatingToolbarPanel *)toolbar { (void)toolbar; [[MSIMEUpdateController sharedController] checkForUpdates:nil]; }
- (void)floatingToolbarDidRequestOpenWebsite:(MSIMEFloatingToolbarPanel *)toolbar {
    (void)toolbar;
    [[NSWorkspace sharedWorkspace] openURL:[NSURL URLWithString:@"https://msime.app/"]];
}
- (void)floatingToolbarDidRequestHide:(MSIMEFloatingToolbarPanel *)toolbar {
    (void)toolbar;
    _appearance.floatingToolbarEnabled = NO;
    [_toolbar setVisible:NO forDelegate:self];
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
    if (msime::mac::IsFullWidthInputToggle(event.keyCode, event.modifierFlags)) {
        if (!event.isARepeat) _appearance.fullWidthInput = !_appearance.fullWidthInput;
        return YES;
    }
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
    if (command == UINT32_MAX && [transition[@"handled"] boolValue] &&
        ![transition[@"commit"] isKindOfClass:NSString.class] && event.characters.length == 1 &&
        [event.characters characterAtIndex:0] >= 'a' && [event.characters characterAtIndex:0] <= 'z' &&
        MSIMEShouldAutoCommitWubi(_appearance.wubiAutoCommitUnique, transition[@"view"])) {
        NSDictionary *committed = [_session command:MSIME_COMMIT_CANDIDATE error:nil];
        if (committed) [self apply:committed];
    }
    if ([transition[@"handled"] boolValue]) return YES;
    // Match Apple: Engine gets first refusal, then finish any composition before fallback.
    if ([_view[@"editing_text"] length]) {
        NSDictionary *finished = [_session command:MSIME_FINISH_COMPOSITION error:nil];
        if (!finished) return NO;
        [self apply:finished];
    }
    if (_appearance.fullWidthInput && [_view[@"editing_text"] isKindOfClass:NSString.class] &&
        ![_view[@"editing_text"] length] && event.characters.length == 1 &&
        msime::mac::IsFullWidthDirectCharacter([event.characters characterAtIndex:0], event.modifierFlags)) {
        const unichar converted = msime::mac::FullWidthCharacter([event.characters characterAtIndex:0]);
        [(id<MSIMETextClient>)sender insertText:[NSString stringWithCharacters:&converted length:1] replacementRange:NSMakeRange(NSNotFound, NSNotFound)];
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
    NSDictionary *displayTransition = transition;
    if (_appearance.traditionalOutput && MSIMEScriptConversionApplies(transition[@"commit_context"]) && [transition[@"commit"] isKindOfClass:NSString.class]) {
        NSMutableDictionary *converted = [transition mutableCopy];
        converted[@"commit"] = MSIMEChineseOutputString(transition[@"commit"], YES);
        displayTransition = converted;
    }
    MSIMEApplyTransition(displayTransition, (id<MSIMETextClient>)_activeClient);
    _view = transition[@"view"];
    [self renderCandidates];
}

- (void)updateKeymapPanel {
    NSString *preedit = _view[@"preedit"];
    NSNumber *scheme = _view[@"scheme"];
    NSString *profile = _view[@"shuangpin_profile"];
    if (!_session || !_activeClient || _appearance.englishMode ||
        ![scheme isKindOfClass:NSNumber.class] || scheme.integerValue != 1 ||
        ![profile isKindOfClass:NSString.class] || profile.length == 0 ||
        !MSIMEShouldShowShuangpinKeymap(YES, _appearance.shuangpinKeymap, [preedit isKindOfClass:NSString.class] && preedit.length > 0)) {
        [_keymapPanel orderOut:nil];
        return;
    }
    NSRect cursor = NSZeroRect;
    [_activeClient attributesForCharacterIndex:0 lineHeightRectangle:&cursor];
    if (!MSIMEValidCaret(cursor)) { [_keymapPanel orderOut:nil]; return; }
    if (!_keymapPanel) _keymapPanel = [[MSIMEShuangpinKeymapPanel alloc] init];
    [_keymapPanel setProfileName:profile];
    const unichar last = [preedit characterAtIndex:preedit.length - 1];
    NSString *key = ((last >= 'a' && last <= 'z') || (last >= 'A' && last <= 'Z') || last == ';') ? [NSString stringWithCharacters:&last length:1] : @"";
    [_keymapPanel updateHighlightedKey:key];
    CGFloat clearance = _appearance.fontSize + 42.0;
    if (_appearance.vertical) clearance = (_appearance.fontSize + 10.0) * MIN([_view[@"candidates"] count], _appearance.pageSize) + 24.0;
    [_keymapPanel showNearCaretRect:cursor candidateClearance:clearance];
}

- (void)renderCandidates {
    [self updateKeymapPanel];
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
    const BOOL traditional = _appearance.traditionalOutput && MSIMEScriptConversionApplies(_view);
    for (NSDictionary *candidate in candidates) {
        NSString *title = [NSString stringWithFormat:@"%lu  %@", (unsigned long)++index, CandidateDisplay(candidate, traditional)];
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
        NSString *display = CandidateDisplay(candidate, traditional);
        NSString *title = [NSString stringWithFormat:@"%lu  %@", (unsigned long)(slot + 1), display];
        MSIMECandidateButton *button = [MSIMECandidateButton buttonWithTitle:title target:self action:@selector(selectCandidate:)];
        button.candidateID = candidate[@"id"];
        button.tag = (NSInteger)slot;
        CGFloat itemWidth = vertical ? width - 2 * inset : widths[slot].doubleValue;
        button.frame = NSMakeRect(x, vertical ? height - inset - decorationHeight - ((slot + 1) * rowHeight) : inset, itemWidth, rowHeight);
        ++slot;
        if (!vertical) x += itemWidth;
        button.font = font;
        button.lineBreakMode = NSLineBreakByTruncatingTail;
        button.toolTip = display;
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
