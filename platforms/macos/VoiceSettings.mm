#import "VoiceSettings.h"
#import "VoiceInputService.h"
NSNotificationName const MSIMEVoiceSettingsDidChangeNotification = @"MSIMEClientVoiceSettingsDidChange";
@implementation MSIMEVoiceSettings {
    NSPopUpButton *_language;
    NSTextField *_status;
    MSIMEVoiceInputService *_service;
}
+ (instancetype)sharedSettings { static MSIMEVoiceSettings *value; static dispatch_once_t once; dispatch_once(&once, ^{ value = [[self alloc] initWithWindow:nil]; }); return value; }
- (void)showAndActivate {
    if (!self.window) {
        NSWindow *window = [[NSWindow alloc] initWithContentRect:NSMakeRect(0, 0, 420, 190) styleMask:NSWindowStyleMaskTitled | NSWindowStyleMaskClosable backing:NSBackingStoreBuffered defer:NO];
        window.title = @"语音输入设置";
        _service = [[MSIMEVoiceInputService alloc] init];
        _language = [[NSPopUpButton alloc] initWithFrame:NSZeroRect pullsDown:NO]; [_language addItemsWithTitles:@[@"中文（简体）", @"English"]];
        [_language selectItemAtIndex:[[[NSUserDefaults standardUserDefaults] stringForKey:@"MSIMEClientVoiceLanguage"] isEqualToString:@"en-US"] ? 1 : 0];
        _language.target = self; _language.action = @selector(languageChanged:);
        _status = [NSTextField labelWithString:@"权限状态未知"];
        NSButton *permission = [NSButton buttonWithTitle:@"请求麦克风与语音权限" target:self action:@selector(requestPermission:)];
        NSGridView *grid = [NSGridView gridViewWithViews:@[@[[NSTextField labelWithString:@"识别语言"], _language], @[[NSTextField labelWithString:@"权限"], _status], @[[NSTextField labelWithString:@""], permission]]];
        grid.rowSpacing = 16; grid.columnSpacing = 16; grid.translatesAutoresizingMaskIntoConstraints = NO; [window.contentView addSubview:grid];
        [NSLayoutConstraint activateConstraints:@[[grid.centerXAnchor constraintEqualToAnchor:window.contentView.centerXAnchor], [grid.topAnchor constraintEqualToAnchor:window.contentView.topAnchor constant:24]]]; self.window = window;
    }
    [self refreshStatus]; [self showWindow:nil]; [NSApp activateIgnoringOtherApps:YES];
}
- (void)refreshStatus { _status.stringValue = (_service.microphoneAuthorizationStatus == AVAuthorizationStatusAuthorized && _service.speechAuthorizationStatus == SFSpeechRecognizerAuthorizationStatusAuthorized) ? @"已授权" : @"尚未完全授权"; }
- (void)requestPermission:(id)sender { (void)sender; [_service requestSpeechPermission:^(BOOL granted) { if (granted) [_service requestMicrophonePermission:^(BOOL grantedMicrophone) { (void)grantedMicrophone; [self refreshStatus]; }]; else [self refreshStatus]; }]; }
- (void)languageChanged:(NSPopUpButton *)sender { [[NSUserDefaults standardUserDefaults] setObject:(sender.indexOfSelectedItem == 0 ? @"zh-CN" : @"en-US") forKey:@"MSIMEClientVoiceLanguage"]; [[NSNotificationCenter defaultCenter] postNotificationName:MSIMEVoiceSettingsDidChangeNotification object:self]; }
@end
