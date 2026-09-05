#import "VoiceSettings.h"
#import <Security/Security.h>

namespace {
NSString *const service = @"com.houko.inputmethod.MetasequoiaIME.voice";
NSError *Error(NSString *message) {
    return [NSError errorWithDomain:service code:1 userInfo:@{NSLocalizedDescriptionKey: message}];
}
NSDictionary *Key(NSString *kind, NSString *endpoint) {
    NSURL *url = [NSURL URLWithString:endpoint];
    NSString *origin = [NSString stringWithFormat:@"%@://%@:%@", (url.scheme.lowercaseString ? url.scheme.lowercaseString : @""), (url.host.lowercaseString ? url.host.lowercaseString : @""), (url.port ? url.port : @443)];
    return @{(__bridge id)kSecClass: (__bridge id)kSecClassGenericPassword,
             (__bridge id)kSecAttrService: service,
             (__bridge id)kSecAttrAccount: [kind stringByAppendingFormat:@"|%@", origin]};
}
NSString *ReadToken(NSString *kind, NSString *endpoint) {
    NSMutableDictionary *query = [Key(kind, endpoint) mutableCopy];
    query[(__bridge id)kSecReturnData] = @YES;
    CFTypeRef result = nullptr;
    OSStatus status = SecItemCopyMatching((__bridge CFDictionaryRef)query, &result);
    if (status != errSecSuccess) return @"";
    NSData *data = CFBridgingRelease(result);
    NSString *text = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
    return text ? text : @"";
}
BOOL WriteToken(NSString *kind, NSString *endpoint, NSString *token, NSError **error) {
    NSDictionary *query = Key(kind, endpoint);
    if (token.length == 0) {
        const OSStatus status = SecItemDelete((__bridge CFDictionaryRef)query);
        if (status == errSecSuccess || status == errSecItemNotFound) return YES;
    } else {
        NSDictionary *attributes = @{(__bridge id)kSecValueData: [token dataUsingEncoding:NSUTF8StringEncoding]};
        OSStatus status = SecItemUpdate((__bridge CFDictionaryRef)query, (__bridge CFDictionaryRef)attributes);
        if (status == errSecItemNotFound) {
            NSMutableDictionary *item = [query mutableCopy];
            [item addEntriesFromDictionary:attributes];
            status = SecItemAdd((__bridge CFDictionaryRef)item, nullptr);
        }
        if (status == errSecSuccess) return YES;
    }
    if (error) *error = Error(@"无法保存到系统钥匙串，请解锁钥匙串后重试。");
    return NO;
}
// The account carries the endpoint origin, so editing an endpoint writes a new item and WriteToken
// only ever deletes the origin it was handed — the bearer token for the previous origin stayed in
// the login keychain indefinitely. Every save prunes whatever this service owns beyond the two
// accounts currently in use.
void PruneTokens(NSArray<NSDictionary *> *keptKeys) {
    NSMutableSet<NSString *> *keptAccounts = [NSMutableSet set];
    for (NSDictionary *key in keptKeys) {
        [keptAccounts addObject:key[(__bridge id)kSecAttrAccount]];
    }
    NSDictionary *query = @{(__bridge id)kSecClass: (__bridge id)kSecClassGenericPassword,
                            (__bridge id)kSecAttrService: service,
                            (__bridge id)kSecMatchLimit: (__bridge id)kSecMatchLimitAll,
                            (__bridge id)kSecReturnAttributes: @YES};
    CFTypeRef result = nullptr;
    if (SecItemCopyMatching((__bridge CFDictionaryRef)query, &result) != errSecSuccess) return;
    NSArray<NSDictionary *> *items = CFBridgingRelease(result);
    for (NSDictionary *item in items) {
        NSString *account = item[(__bridge id)kSecAttrAccount];
        if (account.length == 0 || [keptAccounts containsObject:account]) continue;
        SecItemDelete((__bridge CFDictionaryRef)@{(__bridge id)kSecClass: (__bridge id)kSecClassGenericPassword,
                                                  (__bridge id)kSecAttrService: service,
                                                  (__bridge id)kSecAttrAccount: account});
    }
}
BOOL IsEndpoint(NSString *value) {
    NSURLComponents *url = [NSURLComponents componentsWithString:value];
    return [url.scheme.lowercaseString isEqualToString:@"https"] && url.host.length > 0 && !url.user && !url.password && !url.fragment;
}
}
@implementation MetasequoiaVoiceSettings
+ (instancetype)loadSettings {
    MetasequoiaVoiceSettings *value = [self new];
    NSDictionary *saved = [[NSUserDefaults standardUserDefaults] dictionaryForKey:@"voiceInput"];
    if (!saved) saved = @{};
    value.provider = saved[@"provider"] ? saved[@"provider"] : @"cloud";
    value.endpoint = saved[@"endpoint"] ? saved[@"endpoint"] : @"https://api.siliconflow.cn/v1/audio/transcriptions";
    value.model = saved[@"model"] ? saved[@"model"] : @"FunAudioLLM/SenseVoiceSmall";
    value.modelPath = saved[@"modelPath"] ? saved[@"modelPath"] : @"";
    value.polishEnabled = [saved[@"polishEnabled"] boolValue];
    value.polishEndpoint = saved[@"polishEndpoint"] ? saved[@"polishEndpoint"] : @"https://api.siliconflow.cn/v1/chat/completions";
    value.polishModel = saved[@"polishModel"] ? saved[@"polishModel"] : @"Qwen/Qwen3-8B";
    value.token = ReadToken(@"asr", value.endpoint);
    value.polishToken = ReadToken(@"polish", value.polishEndpoint);
    return value;
}
- (BOOL)validate:(NSError **)error {
    NSString *message = nil;
    if ([self.provider isEqualToString:@"local"]) {
        BOOL directory = NO;
        if (![[NSFileManager defaultManager] fileExistsAtPath:self.modelPath isDirectory:&directory] || directory)
            message = @"请选择已下载的 Whisper 模型文件。";
    } else if (![self.provider isEqualToString:@"cloud"]) message = @"请选择识别方式。";
    else if (!IsEndpoint(self.endpoint) || self.model.length == 0 || self.token.length == 0)
        message = @"请填写 HTTPS 识别地址、模型名称和 API 密钥。";
    if (self.polishEnabled && (!IsEndpoint(self.polishEndpoint) || self.polishModel.length == 0 || self.polishToken.length == 0))
        message = @"启用文本整理需要 HTTPS 服务地址、模型名称和 API 密钥。";
    if (message) { if (error) *error = Error(message); return NO; }
    return YES;
}
- (BOOL)save:(NSError **)error {
    if (![self validate:error]) return NO;
    if (!WriteToken(@"asr", self.endpoint, self.token, error) || !WriteToken(@"polish", self.polishEndpoint, self.polishToken, error)) return NO;
    PruneTokens(@[Key(@"asr", self.endpoint), Key(@"polish", self.polishEndpoint)]);
    [[NSUserDefaults standardUserDefaults] setObject:@{
        @"provider":self.provider, @"endpoint":self.endpoint, @"model":self.model, @"modelPath":self.modelPath,
        @"polishEnabled":@(self.polishEnabled), @"polishEndpoint":self.polishEndpoint, @"polishModel":self.polishModel
    } forKey:@"voiceInput"];
    return YES;
}
@end

@interface MetasequoiaVoiceSettingsWindow () <NSTextFieldDelegate>
@end
@implementation MetasequoiaVoiceSettingsWindow {
    NSPopUpButton *_provider;
    NSTextField *_endpoint, *_model, *_modelPath, *_polishEndpoint, *_polishModel;
    NSSecureTextField *_token, *_polishToken;
    NSButton *_polish;
    NSTextField *_status;
}
+ (instancetype)sharedController {
    static MetasequoiaVoiceSettingsWindow *window;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ window = [self new]; });
    return window;
}
// The caption is an absolutely positioned label, which AppKit cannot associate with the field on
// its own, so every field announced itself as a bare "edit text" and the two endpoints and the two
// keys were indistinguishable under VoiceOver.
- (NSTextField *)field:(NSString *)title y:(CGFloat)y secure:(BOOL)secure {
    NSTextField *label = [NSTextField labelWithString:title];
    label.frame = NSMakeRect(20, y + 3, 125, 22);
    [self.window.contentView addSubview:label];
    NSTextField *field = secure ? [NSSecureTextField new] : [NSTextField new];
    field.frame = NSMakeRect(150, y, 435, 25);
    field.accessibilityLabel = title;
    [self.window.contentView addSubview:field];
    return field;
}
- (instancetype)init {
    NSWindow *window = [[NSWindow alloc] initWithContentRect:NSMakeRect(0, 0, 610, 505)
        styleMask:NSWindowStyleMaskTitled | NSWindowStyleMaskClosable backing:NSBackingStoreBuffered defer:NO];
    self = [super initWithWindow:window];
    if (self) {
        window.title = @"语音输入设置";
        _provider = [[NSPopUpButton alloc] initWithFrame:NSMakeRect(150, 455, 435, 28) pullsDown:NO];
        _provider.accessibilityLabel = @"识别方式";
        [_provider addItemsWithTitles:@[@"云端识别", @"本地 Whisper"]];
        _provider.target = self; _provider.action = @selector(updateEnabled:);
        [window.contentView addSubview:_provider];
        _endpoint = [self field:@"识别服务地址" y:415 secure:NO];
        _model = [self field:@"识别模型" y:380 secure:NO];
        _token = (NSSecureTextField *)[self field:@"API 密钥" y:345 secure:YES];
        _modelPath = [self field:@"Whisper 模型" y:310 secure:NO];
        _modelPath.frame = NSMakeRect(150, 310, 330, 25);
        NSButton *browse = [NSButton buttonWithTitle:@"选择…" target:self action:@selector(browse:)];
        browse.frame = NSMakeRect(488, 310, 97, 25); [window.contentView addSubview:browse];
        _polish = [NSButton checkboxWithTitle:@"识别后整理文本（向此服务发送转写文本）" target:self action:@selector(updateEnabled:)];
        _polish.frame = NSMakeRect(20, 265, 570, 25); [window.contentView addSubview:_polish];
        _polishEndpoint = [self field:@"整理服务地址" y:225 secure:NO];
        _polishModel = [self field:@"整理模型" y:190 secure:NO];
        _polishToken = (NSSecureTextField *)[self field:@"整理 API 密钥" y:155 secure:YES];
        _endpoint.delegate = self; _polishEndpoint.delegate = self;
        _status = [NSTextField wrappingLabelWithString:@"Control+Option+V 开始/结束，Esc 取消。云端识别会发送本次录音；本地识别使用所选模型。密钥保存在系统钥匙串中。"];
        _status.frame = NSMakeRect(20, 65, 570, 70); [window.contentView addSubview:_status];
        NSButton *save = [NSButton buttonWithTitle:@"保存" target:self action:@selector(save:)];
        save.frame = NSMakeRect(490, 20, 95, 30); [window.contentView addSubview:save];
        [window center];
    }
    return self;
}
- (void)showAndActivate {
    MetasequoiaVoiceSettings *value = [MetasequoiaVoiceSettings loadSettings];
    [_provider selectItemAtIndex:[value.provider isEqualToString:@"local"] ? 1 : 0];
    _endpoint.stringValue=value.endpoint; _model.stringValue=value.model; _token.stringValue=value.token;
    _modelPath.stringValue=value.modelPath; _polish.state=value.polishEnabled ? NSControlStateValueOn : NSControlStateValueOff;
    _polishEndpoint.stringValue=value.polishEndpoint; _polishModel.stringValue=value.polishModel; _polishToken.stringValue=value.polishToken;
    [self updateEnabled:nil]; [self showWindow:nil]; [NSApp activateIgnoringOtherApps:YES];
}
- (void)updateEnabled:(id)sender {
    (void)sender;
    BOOL cloud = _provider.indexOfSelectedItem == 0;
    _endpoint.enabled=cloud; _model.enabled=cloud; _token.enabled=cloud; _modelPath.enabled=!cloud;
    BOOL polish = _polish.state == NSControlStateValueOn;
    _polishEndpoint.enabled=polish; _polishModel.enabled=polish; _polishToken.enabled=polish;
}
- (void)controlTextDidChange:(NSNotification *)notification {
    if (notification.object == _endpoint) _token.stringValue = @"";
    if (notification.object == _polishEndpoint) _polishToken.stringValue = @"";
}
- (void)browse:(id)sender {
    (void)sender;
    NSOpenPanel *panel = [NSOpenPanel openPanel]; panel.canChooseDirectories=NO; panel.allowsMultipleSelection=NO;
    [panel beginSheetModalForWindow:self.window completionHandler:^(NSModalResponse response) {
        if (response == NSModalResponseOK) self->_modelPath.stringValue = panel.URL.path;
    }];
}
- (void)save:(id)sender {
    (void)sender;
    MetasequoiaVoiceSettings *value = [MetasequoiaVoiceSettings new];
    value.provider = _provider.indexOfSelectedItem == 0 ? @"cloud" : @"local";
    value.endpoint=_endpoint.stringValue; value.model=_model.stringValue; value.token=_token.stringValue;
    value.modelPath=_modelPath.stringValue; value.polishEnabled=_polish.state == NSControlStateValueOn;
    value.polishEndpoint=_polishEndpoint.stringValue; value.polishModel=_polishModel.stringValue; value.polishToken=_polishToken.stringValue;
    NSError *error = nil;
    _status.stringValue = [value save:&error] ? @"设置已保存。" : error.localizedDescription;
}
@end
