#import "VoiceSettings.h"
#import "VoiceInputService.h"
#import "../core/SharedVoicePreferences.h"
NSNotificationName const MSIMEVoiceSettingsDidChangeNotification = @"MSIMEClientVoiceSettingsDidChange";
namespace {
NSString *NormalizedDoubaoAuthMode(NSUserDefaults *defaults)
{
    NSString *mode = [defaults stringForKey:@"MSIMEClientVoiceDoubaoAuthMode"].lowercaseString;
    if ([mode isEqualToString:@"api_key"] || [mode isEqualToString:@"legacy"])
        return mode;
    // Keep old native defaults compatible with the shared editor: a real App
    // ID means the legacy route, while a masked placeholder is not a usable ID.
    NSString *appKey = [defaults stringForKey:@"MSIMEClientVoiceDoubaoAppKey"];
    return appKey.length > 0 && ![appKey hasPrefix:@"<"] ? @"legacy" : @"api_key";
}

NSUInteger IndexOrZero(NSArray<NSString *> *values, NSString *value)
{
    NSUInteger index = [values indexOfObject:value ?: @""];
    return index == NSNotFound ? 0 : index;
}

} // namespace

// The prompt presets, as an identifier the preference stores and a name the user reads.
//
// This popup used to be built from the identifiers alone, so the window offered `cleanup` and
// `zh2en` as menu items and wrote back whichever string was on screen. The names are the reference's
// own (`PolishPromptPreset` in voice_providers.cpp); the three custom slots are this client's.
static inline NSArray<NSString *> *MSIMEPolishPromptIdentifiers(void)
{
    return @[@"cleanup", @"faithful", @"zh2en", @"casual", @"custom_1", @"custom_2", @"custom_3"];
}

static inline NSArray<NSString *> *MSIMEPolishPromptTitles(void)
{
    return @[@"精炼整理", @"忠实校对", @"中翻英", @"口语整理", @"自定义一", @"自定义二", @"自定义三"];
}

static inline NSString *MSIMEPolishPromptIdentifierForIndex(NSInteger index)
{
    NSArray<NSString *> *identifiers = MSIMEPolishPromptIdentifiers();
    return index >= 0 && (NSUInteger)index < identifiers.count ? identifiers[(NSUInteger)index]
                                                               : identifiers.firstObject;
}

@implementation MSIMEVoiceSettings {
    NSPopUpButton *_language;
    NSTextField *_status;
    NSPopUpButton *_provider, *_polishProvider, *_polishPromptID, *_doubaoAuthMode;
    NSButton *_polish;
    NSTextField *_model, *_endpoint, *_asrModel;
    NSSecureTextField *_token, *_polishToken;
    NSString *_loadedASRProvider;
    NSString *_loadedPolishProvider;
    NSTextField *_doubaoBoostingTable, *_doubaoAppKey, *_doubaoResourceID, *_polishPrompt, *_polishEndpoint, *_polishCustom1, *_polishCustom2, *_polishCustom3;
    NSButton *_hotkey, *_muteAudio, *_soundEnabled, *_holdSpace, *_rightAlt, *_streamInline, *_ctrlCommand, *_ctrlOption;
    MSIMEVoiceInputService *_service;
}
+ (instancetype)sharedSettings { static MSIMEVoiceSettings *value; static dispatch_once_t once; dispatch_once(&once, ^{ value = [[self alloc] initWithWindow:nil]; }); return value; }
- (void)showAndActivate {
    if (!self.window) {
        NSWindow *window = [[NSWindow alloc] initWithContentRect:NSMakeRect(0, 0, 560, 500) styleMask:NSWindowStyleMaskTitled | NSWindowStyleMaskClosable backing:NSBackingStoreBuffered defer:NO];
        window.title = @"语音输入设置";
        _service = [[MSIMEVoiceInputService alloc] init];
        _language = [[NSPopUpButton alloc] initWithFrame:NSZeroRect pullsDown:NO]; [_language addItemsWithTitles:@[@"中文（简体）", @"English"]];
        [_language selectItemAtIndex:[[[NSUserDefaults standardUserDefaults] stringForKey:@"MSIMEClientVoiceLanguage"] isEqualToString:@"en-US"] ? 1 : 0];
        _language.target = self; _language.action = @selector(languageChanged:);
        _provider = [[NSPopUpButton alloc] initWithFrame:NSZeroRect pullsDown:NO];
        [_provider addItemsWithTitles:@[@"豆包", @"OpenAI", @"SiliconFlow", @"Groq"]];
        _doubaoAuthMode = [[NSPopUpButton alloc] initWithFrame:NSZeroRect pullsDown:NO];
        [_doubaoAuthMode addItemsWithTitles:@[@"新版 API Key", @"旧版 App ID + Access Token"]];
        _doubaoAuthMode.target = self; _doubaoAuthMode.action = @selector(doubaoAuthModeChanged:);
        _polish = [NSButton checkboxWithTitle:@"启用文本润色" target:self action:nil];
        _polishProvider = [[NSPopUpButton alloc] initWithFrame:NSZeroRect pullsDown:NO];
        [_polishProvider addItemsWithTitles:@[@"DeepSeek", @"OpenAI", @"SiliconFlow", @"Groq"]];
        _polishToken = [[NSSecureTextField alloc] initWithFrame:NSZeroRect];
        _polishToken.placeholderString = @"润色 Token（仅保存在本机）";
        _model = [NSTextField textFieldWithString:@""]; _model.placeholderString = @"留空使用提供商默认模型"; _polishEndpoint = [NSTextField textFieldWithString:@""]; _polishEndpoint.placeholderString = @"整理服务地址（可选）"; _polishPrompt = [NSTextField textFieldWithString:@""]; _polishPrompt.placeholderString = @"整理提示词（可选）"; _polishCustom1 = [NSTextField textFieldWithString:@""]; _polishCustom2 = [NSTextField textFieldWithString:@""]; _polishCustom3 = [NSTextField textFieldWithString:@""]; _polishPromptID = [[NSPopUpButton alloc] initWithFrame:NSZeroRect pullsDown:NO]; [_polishPromptID addItemsWithTitles:MSIMEPolishPromptTitles()];
        _endpoint = [NSTextField textFieldWithString:@""]; _endpoint.placeholderString = @"ASR 接口地址（可选）";
        _token = [[NSSecureTextField alloc] initWithFrame:NSZeroRect]; _token.placeholderString = @"ASR Token（仅保存在本机）";
        _asrModel = [NSTextField textFieldWithString:@""]; _asrModel.placeholderString = @"ASR 模型（可选）"; _doubaoBoostingTable = [NSTextField textFieldWithString:@""]; _doubaoAppKey = [NSTextField textFieldWithString:@""]; _doubaoResourceID = [NSTextField textFieldWithString:@""];
        NSUserDefaults *defaults = NSUserDefaults.standardUserDefaults;
        NSArray *asrProviders = @[@"doubao", @"openai", @"siliconflow", @"groq"];
        NSString *selectedASRProvider = asrProviders[IndexOrZero(asrProviders, [defaults stringForKey:@"MSIMEClientVoiceASRProvider"] ?: @"doubao")];
        _loadedASRProvider = [selectedASRProvider copy];
        [_provider selectItemAtIndex:IndexOrZero(asrProviders, selectedASRProvider)];
        [_doubaoAuthMode selectItemAtIndex:[NormalizedDoubaoAuthMode(defaults) isEqualToString:@"legacy"] ? 1 : 0];
        _polish.state = ([defaults boolForKey:@"MSIMEClientVoicePolish"] || [defaults boolForKey:@"MSIMEClientVoicePolishText"]) ? NSControlStateValueOn : NSControlStateValueOff;
        NSArray *polishProviders = @[@"deepseek", @"openai", @"siliconflow", @"groq"];
        NSString *selectedPolishProvider = polishProviders[IndexOrZero(polishProviders, [defaults stringForKey:@"MSIMEClientVoicePolishProvider"] ?: @"deepseek")];
        _loadedPolishProvider = [selectedPolishProvider copy];
        [_polishProvider selectItemAtIndex:IndexOrZero(polishProviders, selectedPolishProvider)];
        _model.stringValue = [defaults stringForKey:@"MSIMEClientVoicePolishModel"] ?: @""; _polishEndpoint.stringValue = [defaults stringForKey:@"MSIMEClientVoicePolishEndpoint"] ?: @""; _polishPrompt.stringValue = [defaults stringForKey:@"MSIMEClientVoicePolishPrompt"] ?: @""; _polishCustom1.stringValue = [defaults stringForKey:@"MSIMEClientVoicePolishPromptCustom1"] ?: @""; _polishCustom2.stringValue = [defaults stringForKey:@"MSIMEClientVoicePolishPromptCustom2"] ?: @""; _polishCustom3.stringValue = [defaults stringForKey:@"MSIMEClientVoicePolishPromptCustom3"] ?: @""; NSUInteger preset = [MSIMEPolishPromptIdentifiers() indexOfObject:[defaults stringForKey:@"MSIMEClientVoicePolishPromptID"] ?: @"cleanup"]; [_polishPromptID selectItemAtIndex:preset == NSNotFound ? 0 : preset];
        _endpoint.stringValue = [defaults stringForKey:@"MSIMEClientVoiceASREndpoint"] ?: @"";
        _token.stringValue = MSIMEVoiceTokenForProvider(defaults, @"MSIMEClientVoiceASRTokens",
                                                        selectedASRProvider,
                                                        [defaults stringForKey:@"MSIMEClientVoiceASRToken"]);
        _polishToken.stringValue = MSIMEVoiceTokenForProvider(defaults, @"MSIMEClientVoicePolishTokens",
                                                              selectedPolishProvider,
                                                              [defaults stringForKey:@"MSIMEClientVoicePolishToken"]);
        _hotkey = [NSButton checkboxWithTitle:@"启用 Ctrl+F9 语音快捷键" target:self action:@selector(voiceOptionsChanged:)];
        _hotkey.state = [NSUserDefaults.standardUserDefaults objectForKey:@"MSIMEClientVoiceHotkeyCtrlF9"] == nil || [NSUserDefaults.standardUserDefaults boolForKey:@"MSIMEClientVoiceHotkeyCtrlF9"] ? NSControlStateValueOn : NSControlStateValueOff;
        _holdSpace = [NSButton checkboxWithTitle:@"按住语音快捷键时，按空格锁定录音" target:self action:@selector(voiceOptionsChanged:)]; _holdSpace.state = [defaults objectForKey:@"MSIMEClientVoiceHotkeyHoldSpace"] == nil || [defaults boolForKey:@"MSIMEClientVoiceHotkeyHoldSpace"] ? NSControlStateValueOn : NSControlStateValueOff;
        _rightAlt = [NSButton checkboxWithTitle:@"启用右 Option 语音快捷键" target:self action:@selector(voiceOptionsChanged:)]; _rightAlt.state = [defaults boolForKey:@"MSIMEClientVoiceHotkeyRightAlt"] ? NSControlStateValueOn : NSControlStateValueOff; _ctrlCommand = [NSButton checkboxWithTitle:@"启用 Control+Command 语音快捷键" target:self action:@selector(voiceOptionsChanged:)]; _ctrlCommand.state = [defaults boolForKey:@"MSIMEClientVoiceHotkeyCtrlCommand"] ? NSControlStateValueOn : NSControlStateValueOff; _ctrlOption = [NSButton checkboxWithTitle:@"启用右 Control+Option 语音快捷键" target:self action:@selector(voiceOptionsChanged:)]; _ctrlOption.state = [defaults boolForKey:@"MSIMEClientVoiceHotkeyCtrlOption"] ? NSControlStateValueOn : NSControlStateValueOff;
        _soundEnabled = [NSButton checkboxWithTitle:@"播放语音提示音" target:self action:@selector(voiceOptionsChanged:)];
        _soundEnabled.state = [defaults objectForKey:@"MSIMEClientVoiceSoundEnabled"] == nil || [defaults boolForKey:@"MSIMEClientVoiceSoundEnabled"] ? NSControlStateValueOn : NSControlStateValueOff;
        _muteAudio = [NSButton checkboxWithTitle:@"语音输入时静音系统音频" target:self action:@selector(voiceOptionsChanged:)];
        _streamInline = [NSButton checkboxWithTitle:@"实时显示语音中间结果" target:self action:@selector(voiceOptionsChanged:)];
        _streamInline.state = [defaults objectForKey:@"MSIMEClientVoiceStreamInlinePreedit"] == nil || [defaults boolForKey:@"MSIMEClientVoiceStreamInlinePreedit"] ? NSControlStateValueOn : NSControlStateValueOff;
        _muteAudio.state = [defaults boolForKey:@"MSIMEClientVoiceMuteSystemAudio"] ? NSControlStateValueOn : NSControlStateValueOff;
        _provider.target = self; _provider.action = @selector(voiceOptionsChanged:);
        _polish.target = self; _polish.action = @selector(polishChanged:);
        _polishProvider.target = self; _polishProvider.action = @selector(polishProviderChanged:);
        _model.target = self; _model.action = @selector(voiceOptionsChanged:);
        _endpoint.target = self; _endpoint.action = @selector(voiceOptionsChanged:); _token.target = self; _token.action = @selector(voiceOptionsChanged:); _polishToken.target = self; _polishToken.action = @selector(voiceOptionsChanged:); _asrModel.target = self; _asrModel.action = @selector(asrModelChanged:);
        _status = [NSTextField labelWithString:@"权限状态未知"];
        NSButton *permission = [NSButton buttonWithTitle:@"请求麦克风与语音权限" target:self action:@selector(requestPermission:)];
        NSGridView *grid = [NSGridView gridViewWithViews:@[@[[NSTextField labelWithString:@"识别语言"], _language], @[[NSTextField labelWithString:@"ASR 提供商"], _provider], @[[NSTextField labelWithString:@"豆包鉴权方式"], _doubaoAuthMode], @[[NSTextField labelWithString:@"ASR 接口"], _endpoint], @[[NSTextField labelWithString:@"ASR Token"], _token], @[[NSTextField labelWithString:@"语音快捷键"], _hotkey], @[[NSTextField labelWithString:@"按键方式"], _holdSpace], @[[NSTextField labelWithString:@"右 Option"], _rightAlt], @[[NSTextField labelWithString:@"Control+Command"], _ctrlCommand], @[[NSTextField labelWithString:@"右 Control+Option"], _ctrlOption], @[[NSTextField labelWithString:@"提示音"], _soundEnabled], @[[NSTextField labelWithString:@"系统音频"], _muteAudio], @[[NSTextField labelWithString:@"中间结果"], _streamInline], @[[NSTextField labelWithString:@"文本润色"], _polish], @[[NSTextField labelWithString:@"润色提供商"], _polishProvider], @[[NSTextField labelWithString:@"润色 Token"], _polishToken], @[[NSTextField labelWithString:@"润色模型"], _model], @[[NSTextField labelWithString:@"整理地址"], _polishEndpoint], @[[NSTextField labelWithString:@"整理预设"], _polishPromptID], @[[NSTextField labelWithString:@"整理提示词"], _polishPrompt], @[[NSTextField labelWithString:@"自定义整理 1"], _polishCustom1], @[[NSTextField labelWithString:@"自定义整理 2"], _polishCustom2], @[[NSTextField labelWithString:@"自定义整理 3"], _polishCustom3], @[[NSTextField labelWithString:@"权限"], _status], @[[NSTextField labelWithString:@""], permission]]];
        [grid addRowWithViews:@[[NSTextField labelWithString:@"ASR 模型"], _asrModel]]; [grid addRowWithViews:@[[NSTextField labelWithString:@"Doubao 词表"], _doubaoBoostingTable]]; [grid addRowWithViews:@[[NSTextField labelWithString:@"Doubao App Key"], _doubaoAppKey]]; [grid addRowWithViews:@[[NSTextField labelWithString:@"Doubao Resource ID"], _doubaoResourceID]];
        _asrModel.stringValue = [defaults stringForKey:@"MSIMEClientVoiceASRModel"] ?: @""; _doubaoBoostingTable.stringValue = [defaults stringForKey:@"MSIMEClientVoiceDoubaoBoostingTableID"] ?: @""; _doubaoAppKey.stringValue = [defaults stringForKey:@"MSIMEClientVoiceDoubaoAppKey"] ?: @""; _doubaoResourceID.stringValue = [defaults stringForKey:@"MSIMEClientVoiceDoubaoResourceID"] ?: @"";
        grid.rowSpacing = 16; grid.columnSpacing = 16; grid.translatesAutoresizingMaskIntoConstraints = NO; [window.contentView addSubview:grid];
        [NSLayoutConstraint activateConstraints:@[[grid.centerXAnchor constraintEqualToAnchor:window.contentView.centerXAnchor], [grid.topAnchor constraintEqualToAnchor:window.contentView.topAnchor constant:24]]]; self.window = window;
    }
    [self refreshStatus]; [self showWindow:nil]; [NSApp activateIgnoringOtherApps:YES];
}
- (void)refreshStatus { _status.stringValue = (_service.microphoneAuthorizationStatus == AVAuthorizationStatusAuthorized && _service.speechAuthorizationStatus == SFSpeechRecognizerAuthorizationStatusAuthorized) ? @"已授权" : @"尚未完全授权"; }
- (void)requestPermission:(id)sender { (void)sender; [_service requestSpeechPermission:^(BOOL granted) { if (granted) [_service requestMicrophonePermission:^(BOOL grantedMicrophone) { (void)grantedMicrophone; [self refreshStatus]; }]; else [self refreshStatus]; }]; }
- (void)languageChanged:(NSPopUpButton *)sender { [[NSUserDefaults standardUserDefaults] setObject:(sender.indexOfSelectedItem == 0 ? @"zh-CN" : @"en-US") forKey:@"MSIMEClientVoiceLanguage"]; [[NSNotificationCenter defaultCenter] postNotificationName:MSIMEVoiceSettingsDidChangeNotification object:self]; }
- (void)asrModelChanged:(NSTextField *)sender { [NSUserDefaults.standardUserDefaults setObject:sender.stringValue forKey:@"MSIMEClientVoiceASRModel"]; [[NSNotificationCenter defaultCenter] postNotificationName:MSIMEVoiceSettingsDidChangeNotification object:self]; }
- (void)doubaoAuthModeChanged:(NSPopUpButton *)sender { [[NSUserDefaults standardUserDefaults] setObject:(sender.indexOfSelectedItem == 1 ? @"legacy" : @"api_key") forKey:@"MSIMEClientVoiceDoubaoAuthMode"]; [self voiceOptionsChanged:nil]; }
- (void)polishChanged:(NSButton *)sender { [[NSUserDefaults standardUserDefaults] setBool:sender.state == NSControlStateValueOn forKey:@"MSIMEClientVoicePolishText"]; [self voiceOptionsChanged:nil]; }
- (void)polishProviderChanged:(id)sender
{
    (void)sender;
    NSArray *models = @[@"deepseek-v4-flash", @"gpt-4o-mini", @"Qwen/Qwen3-8B", @"llama-3.3-70b-versatile"];
    NSUInteger index = MIN((NSUInteger)_polishProvider.indexOfSelectedItem, models.count - 1);
    if (_model.stringValue.length == 0) _model.stringValue = models[index];
    [self voiceOptionsChanged:nil];
}
- (void)voiceOptionsChanged:(id)sender {
    (void)sender;
    NSUserDefaults *d = NSUserDefaults.standardUserDefaults;
    NSArray *asr = @[@"doubao", @"openai", @"siliconflow", @"groq"],
                   *polish = @[@"deepseek", @"openai", @"siliconflow", @"groq"];
    NSString *asrProvider = asr[_provider.indexOfSelectedItem];
    if (_loadedASRProvider.length && ![_loadedASRProvider isEqualToString:asrProvider]) {
        MSIMESaveVoiceTokenSlot(d, @"MSIMEClientVoiceASRTokens", _loadedASRProvider, _token.stringValue);
        _token.stringValue = MSIMEVoiceTokenForProvider(d, @"MSIMEClientVoiceASRTokens", asrProvider, nil);
    }
    _loadedASRProvider = [asrProvider copy];
    MSIMESaveVoiceTokenSlot(d, @"MSIMEClientVoiceASRTokens", asrProvider, _token.stringValue);
    NSString *polishProvider = polish[_polishProvider.indexOfSelectedItem];
    if (_loadedPolishProvider.length && ![_loadedPolishProvider isEqualToString:polishProvider]) {
        MSIMESaveVoiceTokenSlot(d, @"MSIMEClientVoicePolishTokens", _loadedPolishProvider, _polishToken.stringValue);
        _polishToken.stringValue = MSIMEVoiceTokenForProvider(d, @"MSIMEClientVoicePolishTokens", polishProvider, nil);
    }
    _loadedPolishProvider = [polishProvider copy];
    MSIMESaveVoiceTokenSlot(d, @"MSIMEClientVoicePolishTokens", polishProvider, _polishToken.stringValue);
    [d setObject:asrProvider forKey:@"MSIMEClientVoiceASRProvider"];
    [d setObject:_endpoint.stringValue forKey:@"MSIMEClientVoiceASREndpoint"];
    [d setObject:_token.stringValue forKey:@"MSIMEClientVoiceASRToken"];
    [d setBool:_hotkey.state == NSControlStateValueOn forKey:@"MSIMEClientVoiceHotkeyCtrlF9"];
    [d setBool:_holdSpace.state == NSControlStateValueOn forKey:@"MSIMEClientVoiceHotkeyHoldSpace"];
    [d setBool:_rightAlt.state == NSControlStateValueOn forKey:@"MSIMEClientVoiceHotkeyRightAlt"];
    [d setBool:_ctrlCommand.state == NSControlStateValueOn forKey:@"MSIMEClientVoiceHotkeyCtrlCommand"];
    [d setBool:_ctrlOption.state == NSControlStateValueOn forKey:@"MSIMEClientVoiceHotkeyCtrlOption"];
    [d setBool:_soundEnabled.state == NSControlStateValueOn forKey:@"MSIMEClientVoiceSoundEnabled"];
    [d setBool:_muteAudio.state == NSControlStateValueOn forKey:@"MSIMEClientVoiceMuteSystemAudio"];
    [d setBool:_streamInline.state == NSControlStateValueOn forKey:@"MSIMEClientVoiceStreamInlinePreedit"];
    [d setBool:_polish.state == NSControlStateValueOn forKey:@"MSIMEClientVoicePolish"];
    [d setObject:polishProvider forKey:@"MSIMEClientVoicePolishProvider"];
    [d setObject:_model.stringValue forKey:@"MSIMEClientVoicePolishModel"];
    [d setObject:_polishToken.stringValue forKey:@"MSIMEClientVoicePolishToken"];
    [d setObject:_polishEndpoint.stringValue forKey:@"MSIMEClientVoicePolishEndpoint"];
    [d setObject:_polishPrompt.stringValue forKey:@"MSIMEClientVoicePolishPrompt"];
    [d setObject:MSIMEPolishPromptIdentifierForIndex(_polishPromptID.indexOfSelectedItem)
          forKey:@"MSIMEClientVoicePolishPromptID"];
    [d setObject:_polishCustom1.stringValue forKey:@"MSIMEClientVoicePolishPromptCustom1"];
    [d setObject:_polishCustom2.stringValue forKey:@"MSIMEClientVoicePolishPromptCustom2"];
    [d setObject:_polishCustom3.stringValue forKey:@"MSIMEClientVoicePolishPromptCustom3"];
    [d setObject:_doubaoBoostingTable.stringValue forKey:@"MSIMEClientVoiceDoubaoBoostingTableID"];
    [d setObject:_doubaoAppKey.stringValue forKey:@"MSIMEClientVoiceDoubaoAppKey"];
    [d setObject:_doubaoResourceID.stringValue forKey:@"MSIMEClientVoiceDoubaoResourceID"];
    [[NSNotificationCenter defaultCenter] postNotificationName:MSIMEVoiceSettingsDidChangeNotification object:self];
}
@end
