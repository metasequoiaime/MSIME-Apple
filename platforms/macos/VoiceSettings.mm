#import "VoiceSettings.h"
#import "VoiceInputService.h"
NSNotificationName const MSIMEVoiceSettingsDidChangeNotification = @"MSIMEClientVoiceSettingsDidChange";
@implementation MSIMEVoiceSettings {
    NSPopUpButton *_language;
    NSTextField *_status;
    NSPopUpButton *_provider, *_polishProvider;
    NSButton *_polish;
    NSTextField *_model, *_endpoint, *_asrModel;
    NSSecureTextField *_token;
    NSButton *_hotkey, *_muteAudio;
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
        _polish = [NSButton checkboxWithTitle:@"启用文本润色" target:self action:nil];
        _polishProvider = [[NSPopUpButton alloc] initWithFrame:NSZeroRect pullsDown:NO];
        [_polishProvider addItemsWithTitles:@[@"DeepSeek", @"OpenAI", @"SiliconFlow", @"Groq"]];
        _model = [NSTextField textFieldWithString:@""]; _model.placeholderString = @"留空使用提供商默认模型";
        _endpoint = [NSTextField textFieldWithString:@""]; _endpoint.placeholderString = @"ASR 接口地址（可选）";
        _token = [[NSSecureTextField alloc] initWithFrame:NSZeroRect]; _token.placeholderString = @"ASR Token（仅保存在本机）";
        _asrModel = [NSTextField textFieldWithString:@""]; _asrModel.placeholderString = @"ASR 模型（可选）";
        NSUserDefaults *defaults = NSUserDefaults.standardUserDefaults;
        [_provider selectItemAtIndex:[@[@"doubao", @"openai", @"siliconflow", @"groq"] indexOfObject:[defaults stringForKey:@"MSIMEClientVoiceASRProvider"] ?: @"doubao"]];
        _polish.state = [defaults boolForKey:@"MSIMEClientVoicePolish"] ? NSControlStateValueOn : NSControlStateValueOff;
        [_polishProvider selectItemAtIndex:[@[@"deepseek", @"openai", @"siliconflow", @"groq"] indexOfObject:[defaults stringForKey:@"MSIMEClientVoicePolishProvider"] ?: @"deepseek"]];
        _model.stringValue = [defaults stringForKey:@"MSIMEClientVoicePolishModel"] ?: @"";
        _endpoint.stringValue = [defaults stringForKey:@"MSIMEClientVoiceASREndpoint"] ?: @"";
        _token.stringValue = [defaults stringForKey:@"MSIMEClientVoiceASRToken"] ?: @"";
        _hotkey = [NSButton checkboxWithTitle:@"启用 Ctrl+F9 语音快捷键" target:self action:@selector(voiceOptionsChanged:)];
        _hotkey.state = [NSUserDefaults.standardUserDefaults objectForKey:@"MSIMEClientVoiceHotkeyCtrlF9"] == nil || [NSUserDefaults.standardUserDefaults boolForKey:@"MSIMEClientVoiceHotkeyCtrlF9"] ? NSControlStateValueOn : NSControlStateValueOff;
        _muteAudio = [NSButton checkboxWithTitle:@"语音输入时静音系统音频" target:self action:@selector(voiceOptionsChanged:)];
        _muteAudio.state = [defaults boolForKey:@"MSIMEClientVoiceMuteSystemAudio"] ? NSControlStateValueOn : NSControlStateValueOff;
        _provider.target = self; _provider.action = @selector(voiceOptionsChanged:);
        _polish.target = self; _polish.action = @selector(voiceOptionsChanged:);
        _polishProvider.target = self; _polishProvider.action = @selector(voiceOptionsChanged:);
        _model.target = self; _model.action = @selector(voiceOptionsChanged:);
        _endpoint.target = self; _endpoint.action = @selector(voiceOptionsChanged:); _token.target = self; _token.action = @selector(voiceOptionsChanged:); _asrModel.target = self; _asrModel.action = @selector(asrModelChanged:);
        _status = [NSTextField labelWithString:@"权限状态未知"];
        NSButton *permission = [NSButton buttonWithTitle:@"请求麦克风与语音权限" target:self action:@selector(requestPermission:)];
        NSGridView *grid = [NSGridView gridViewWithViews:@[@[[NSTextField labelWithString:@"识别语言"], _language], @[[NSTextField labelWithString:@"ASR 提供商"], _provider], @[[NSTextField labelWithString:@"ASR 接口"], _endpoint], @[[NSTextField labelWithString:@"ASR Token"], _token], @[[NSTextField labelWithString:@"语音快捷键"], _hotkey], @[[NSTextField labelWithString:@"系统音频"], _muteAudio], @[[NSTextField labelWithString:@"文本润色"], _polish], @[[NSTextField labelWithString:@"润色提供商"], _polishProvider], @[[NSTextField labelWithString:@"润色模型"], _model], @[[NSTextField labelWithString:@"权限"], _status], @[[NSTextField labelWithString:@""], permission]]];
        [grid addRowWithViews:@[[NSTextField labelWithString:@"ASR 模型"], _asrModel]];
        _asrModel.stringValue = [defaults stringForKey:@"MSIMEClientVoiceASRModel"] ?: @"";
        grid.rowSpacing = 16; grid.columnSpacing = 16; grid.translatesAutoresizingMaskIntoConstraints = NO; [window.contentView addSubview:grid];
        [NSLayoutConstraint activateConstraints:@[[grid.centerXAnchor constraintEqualToAnchor:window.contentView.centerXAnchor], [grid.topAnchor constraintEqualToAnchor:window.contentView.topAnchor constant:24]]]; self.window = window;
    }
    [self refreshStatus]; [self showWindow:nil]; [NSApp activateIgnoringOtherApps:YES];
}
- (void)refreshStatus { _status.stringValue = (_service.microphoneAuthorizationStatus == AVAuthorizationStatusAuthorized && _service.speechAuthorizationStatus == SFSpeechRecognizerAuthorizationStatusAuthorized) ? @"已授权" : @"尚未完全授权"; }
- (void)requestPermission:(id)sender { (void)sender; [_service requestSpeechPermission:^(BOOL granted) { if (granted) [_service requestMicrophonePermission:^(BOOL grantedMicrophone) { (void)grantedMicrophone; [self refreshStatus]; }]; else [self refreshStatus]; }]; }
- (void)languageChanged:(NSPopUpButton *)sender { [[NSUserDefaults standardUserDefaults] setObject:(sender.indexOfSelectedItem == 0 ? @"zh-CN" : @"en-US") forKey:@"MSIMEClientVoiceLanguage"]; [[NSNotificationCenter defaultCenter] postNotificationName:MSIMEVoiceSettingsDidChangeNotification object:self]; }
- (void)asrModelChanged:(NSTextField *)sender { [NSUserDefaults.standardUserDefaults setObject:sender.stringValue forKey:@"MSIMEClientVoiceASRModel"]; [[NSNotificationCenter defaultCenter] postNotificationName:MSIMEVoiceSettingsDidChangeNotification object:self]; }
- (void)voiceOptionsChanged:(id)sender { (void)sender; NSUserDefaults *d=NSUserDefaults.standardUserDefaults; NSArray *asr=@[@"doubao",@"openai",@"siliconflow",@"groq"], *polish=@[@"deepseek",@"openai",@"siliconflow",@"groq"]; [d setObject:asr[_provider.indexOfSelectedItem] forKey:@"MSIMEClientVoiceASRProvider"]; [d setObject:_endpoint.stringValue forKey:@"MSIMEClientVoiceASREndpoint"]; [d setObject:_token.stringValue forKey:@"MSIMEClientVoiceASRToken"]; [d setBool:_hotkey.state==NSControlStateValueOn forKey:@"MSIMEClientVoiceHotkeyCtrlF9"]; [d setBool:_muteAudio.state==NSControlStateValueOn forKey:@"MSIMEClientVoiceMuteSystemAudio"]; [d setBool:_polish.state==NSControlStateValueOn forKey:@"MSIMEClientVoicePolish"]; [d setObject:polish[_polishProvider.indexOfSelectedItem] forKey:@"MSIMEClientVoicePolishProvider"]; [d setObject:_model.stringValue forKey:@"MSIMEClientVoicePolishModel"]; [[NSNotificationCenter defaultCenter] postNotificationName:MSIMEVoiceSettingsDidChangeNotification object:self]; }
@end
