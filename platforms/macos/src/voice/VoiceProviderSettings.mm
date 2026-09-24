#import "VoiceProviderSettings.h"
#import "VoiceProviderSettingsKeys.h"
#import "VoiceCaptureDevice.h"
#import "../settings/SettingsLayout.h"
NSNotificationName const MSIMEVoiceProviderSettingsDidChangeNotification = @"MSIMEClientVoiceProviderSettingsDidChange";
#import <Security/Security.h>

namespace
{
NSArray<NSDictionary<NSString *, NSString *> *> *ProviderSpecs()
{
    static NSArray<NSDictionary<NSString *, NSString *> *> *specs;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        specs = @[
            @{@"id" : @"doubao", @"title" : @"豆包", @"endpoint" : @"wss://openspeech.bytedance.com/api/v3/sauc/bigmodel_async", @"model" : @""},
            @{@"id" : @"openai", @"title" : @"OpenAI", @"endpoint" : @"https://api.openai.com/v1/audio/transcriptions", @"model" : @"whisper-1"},
            @{@"id" : @"siliconflow", @"title" : @"SiliconFlow", @"endpoint" : @"https://api.siliconflow.cn/v1/audio/transcriptions", @"model" : @"FunAudioLLM/SenseVoiceSmall"},
            @{@"id" : @"groq", @"title" : @"Groq", @"endpoint" : @"https://api.groq.com/openai/v1/audio/transcriptions", @"model" : @"whisper-large-v3-turbo"},
            @{@"id" : @"everyapi", @"title" : @"EveryAPI", @"endpoint" : @"https://api.everyapi.ai/v1/audio/transcriptions", @"model" : @"openai/whisper-large-v3-turbo"},
            @{@"id" : @"mistral", @"title" : @"Mistral · Voxtral", @"endpoint" : @"https://api.mistral.ai/v1/audio/transcriptions", @"model" : @"voxtral-mini-latest"},
            @{@"id" : @"system", @"title" : @"macOS 系统识别", @"endpoint" : @"", @"model" : @""},
            @{@"id" : @"local", @"title" : @"本地模型", @"endpoint" : @"", @"model" : @""}
        ];
    });
    return specs;
}

NSArray<NSString *> *ProviderValues(NSString *key)
{
    NSMutableArray<NSString *> *values = [NSMutableArray arrayWithCapacity:ProviderSpecs().count];
    for (NSDictionary<NSString *, NSString *> *spec in ProviderSpecs())
        [values addObject:spec[key]];
    return [values copy];
}

NSString *ProviderValue(NSString *provider, NSString *key)
{
    NSString *identifier = provider.lowercaseString ?: @"";
    for (NSDictionary<NSString *, NSString *> *spec in ProviderSpecs())
        if ([spec[@"id"] isEqual:identifier]) return spec[key];
    return @"";
}
} // namespace

NSArray<NSString *> *MSIMEVoiceASRProviderIDs(void)
{
    return ProviderValues(@"id");
}

NSArray<NSString *> *MSIMEVoiceASRProviderTitles(void)
{
    return ProviderValues(@"title");
}

NSString *MSIMEVoiceASRProviderDefaultEndpoint(NSString *provider)
{
    return ProviderValue(provider, @"endpoint");
}

NSString *MSIMEVoiceASRProviderDefaultModel(NSString *provider)
{
    return ProviderValue(provider, @"model");
}

BOOL MSIMEVoiceASRProviderUsesService(NSString *provider)
{
    NSString *identifier = provider.lowercaseString ?: @"";
    return [MSIMEVoiceASRProviderIDs() containsObject:identifier] &&
           ![@[ @"system", @"local" ] containsObject:identifier];
}

namespace
{
NSString *const service = @"app.msime.client.voice.providers";
NSError *Error(NSString *message)
{
    return [NSError errorWithDomain:service code:1 userInfo:@{NSLocalizedDescriptionKey : message}];
}
NSDictionary *Key(NSString *kind, NSString *provider, NSString *endpoint)
{
    return @{
        (__bridge id)kSecClass : (__bridge id)kSecClassGenericPassword,
        (__bridge id)kSecAttrService : service,
        (__bridge id)kSecAttrAccount : MSIMEVoiceProviderCredentialAccount(kind, provider, endpoint)
    };
}
NSDictionary *LegacyKey(NSString *kind, NSString *endpoint)
{
    NSURLComponents *url = [NSURLComponents componentsWithString:endpoint ?: @""];
    NSString *origin = [NSString stringWithFormat:@"%@://%@:%@", url.scheme.lowercaseString ?: @"",
                                                   url.host.lowercaseString ?: @"", url.port ?: @443];
    return @{
        (__bridge id)kSecClass : (__bridge id)kSecClassGenericPassword,
        (__bridge id)kSecAttrService : service,
        (__bridge id)kSecAttrAccount : [kind stringByAppendingFormat:@"|%@", origin]
    };
}
NSString *ReadKey(NSDictionary *key)
{
    NSMutableDictionary *query = [key mutableCopy];
    query[(__bridge id)kSecReturnData] = @YES;
    CFTypeRef result = nullptr;
    OSStatus status = SecItemCopyMatching((__bridge CFDictionaryRef)query, &result);
    if (status != errSecSuccess)
        return @"";
    NSData *data = CFBridgingRelease(result);
    NSString *text = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
    return text ? text : @"";
}
NSString *ReadToken(NSString *kind, NSString *provider, NSString *endpoint, BOOL allowLegacy)
{
    NSString *token = ReadKey(Key(kind, provider, endpoint));
    return token.length || !allowLegacy ? token : ReadKey(LegacyKey(kind, endpoint));
}
void DeleteKey(NSDictionary *key)
{
    SecItemDelete((__bridge CFDictionaryRef)key);
}
BOOL WriteToken(NSString *kind, NSString *provider, NSString *endpoint, NSString *token, NSError **error)
{
    NSDictionary *query = Key(kind, provider, endpoint);
    if (token.length == 0)
    {
        const OSStatus status = SecItemDelete((__bridge CFDictionaryRef)query);
        if (status == errSecSuccess || status == errSecItemNotFound)
            return YES;
    }
    else
    {
        NSDictionary *attributes = @{(__bridge id)kSecValueData : [token dataUsingEncoding:NSUTF8StringEncoding]};
        OSStatus status = SecItemUpdate((__bridge CFDictionaryRef)query, (__bridge CFDictionaryRef)attributes);
        if (status == errSecItemNotFound)
        {
            NSMutableDictionary *item = [query mutableCopy];
            [item addEntriesFromDictionary:attributes];
            status = SecItemAdd((__bridge CFDictionaryRef)item, nullptr);
        }
        if (status == errSecSuccess)
            return YES;
    }
    if (error)
        *error = Error(@"无法保存到系统钥匙串，请解锁钥匙串后重试。");
    return NO;
}
void DeleteToken(NSString *kind, NSString *provider, NSString *endpoint)
{
    DeleteKey(Key(kind, provider, endpoint));
    DeleteKey(LegacyKey(kind, endpoint));
}
BOOL IsEndpoint(NSString *value)
{
    NSURLComponents *url = [NSURLComponents componentsWithString:value];
    return [url.scheme.lowercaseString isEqualToString:@"https"] && url.host.length > 0 && !url.user && !url.password &&
           !url.fragment;
}
BOOL IsWebSocketEndpoint(NSString *value)
{
    NSURLComponents *url = [NSURLComponents componentsWithString:value];
    return [url.scheme.lowercaseString isEqualToString:@"wss"] && url.host.length > 0 && !url.user && !url.password &&
           !url.fragment;
}
} // namespace
@implementation MetasequoiaVoiceProviderSettings
// dictionaryForKey: type-checks the container and nothing inside it, and the NSString * properties
// enforce nothing at runtime, so a non-string leaf reached -length or -isEqualToString: and killed
// the input method with an unrecognized selector. The domain is only written here, so this needs an
// out-of-band edit (defaults write, a managed preference, a corrupt plist) — but the whole IME dies
// on the next Control+Option+V, and again on the one after that.
static NSString *StringSetting(NSDictionary *saved, NSString *key, NSString *fallback)
{
    id value = saved[key];
    return [value isKindOfClass:[NSString class]] ? (NSString *)value : fallback;
}

static NSString *SharedSetting(NSDictionary *saved, NSString *key, NSString *fallback)
{
    NSString *sharedKey = MSIMEVoiceProviderSharedKeys()[key];
    return MSIMEVoiceProviderSharedSetting(
        saved, key, sharedKey ? [NSUserDefaults.standardUserDefaults objectForKey:sharedKey] : nil, fallback);
}

+ (instancetype)loadSettings
{
    MetasequoiaVoiceProviderSettings *value = [self new];
    NSUserDefaults *defaults = NSUserDefaults.standardUserDefaults;
    NSDictionary *saved = [defaults dictionaryForKey:@"voiceInput"];
    if (!saved)
        saved = @{};
    NSString *rawProvider =
        SharedSetting(saved, @"provider", @"doubao").lowercaseString;
    // Keep legacy cloud settings readable while matching the Windows provider contract.
    if ([rawProvider isEqualToString:@"cloud"])
        rawProvider = @"siliconflow";
    if (![MSIMEVoiceASRProviderIDs() containsObject:rawProvider])
        rawProvider = @"doubao";
    value.provider = rawProvider;
    value.endpoint = SharedSetting(saved, @"endpoint", @"");
    value.model = SharedSetting(saved, @"model", @"");
    if (value.endpoint.length == 0)
        value.endpoint = MSIMEVoiceASRProviderDefaultEndpoint(rawProvider);
    if (value.model.length == 0)
        value.model = MSIMEVoiceASRProviderDefaultModel(rawProvider);
    value.modelPath = SharedSetting(saved, @"modelPath", @"");
    id polishEnabled = saved[@"polishEnabled"];
    value.polishEnabled =
        [polishEnabled isKindOfClass:[NSNumber class]] || [polishEnabled isKindOfClass:[NSString class]]
            ? [polishEnabled boolValue]
            : NO;
    value.polishEndpoint = SharedSetting(saved, @"polishEndpoint", MSIMEVoicePolishDefaultEndpoint);
    value.polishModel = SharedSetting(saved, @"polishModel", MSIMEVoicePolishDefaultModel);
    id sharedCaptureDevice = [defaults objectForKey:@"MSIMEClientVoiceCaptureDevice"];
    value.captureDevice = [sharedCaptureDevice isKindOfClass:NSString.class]
        ? sharedCaptureDevice : StringSetting(saved, @"captureDevice", @"");
    value.tokenSlots = MSIMEValidVoiceTokenSlots([defaults objectForKey:@"MSIMEClientVoiceASRTokens"]) ?: @{};
    const BOOL serviceProvider = MSIMEVoiceASRProviderUsesService(rawProvider);
    NSString *sharedToken = serviceProvider
        ? MSIMEVoiceTokenForProvider(defaults, @"MSIMEClientVoiceASRTokens", rawProvider,
                                     [defaults stringForKey:@"MSIMEClientVoiceASRToken"])
        : @"";
    value.token = sharedToken.length ? sharedToken
        : (serviceProvider ? ReadToken(@"asr", rawProvider, value.endpoint, YES) : @"");
    if (serviceProvider && value.token.length) {
        NSMutableDictionary *slots = [value.tokenSlots mutableCopy];
        slots[rawProvider] = value.token;
        value.tokenSlots = slots;
    }
    NSString *polishProvider = [defaults stringForKey:@"MSIMEClientVoicePolishProvider"] ?: MSIMEVoicePolishDefaultProvider;
    NSString *sharedPolishToken = MSIMEVoiceTokenForProvider(
        defaults, @"MSIMEClientVoicePolishTokens", polishProvider,
        [defaults stringForKey:@"MSIMEClientVoicePolishToken"]);
    value.polishToken = sharedPolishToken.length
        ? sharedPolishToken : ReadToken(@"polish", polishProvider, value.polishEndpoint, YES);
    return value;
}
- (BOOL)validate:(NSError **)error
{
    NSString *message = nil;
    if ([self.provider isEqualToString:@"local"])
    {
        // Either an installed model directory, which the model installer marks complete by writing msime-model.json last and which runs in the msime-voice-local helper, or a Whisper model file.
        BOOL directory = NO;
        NSFileManager *files = NSFileManager.defaultManager;
        if (![files fileExistsAtPath:self.modelPath isDirectory:&directory] ||
            (directory && ![files fileExistsAtPath:[self.modelPath stringByAppendingPathComponent:@"msime-model.json"]]))
            message = @"请选择已下载的本地语音模型目录或 Whisper 模型文件。";
    }
    else if (![MSIMEVoiceASRProviderIDs() containsObject:self.provider])
        message = @"请选择识别方式。";
    else if ([self.provider isEqualToString:@"doubao"] &&
             (!IsWebSocketEndpoint(self.endpoint) || self.token.length == 0))
        message = @"请填写 WSS 识别地址和 API 密钥。";
    else if (![self.provider isEqualToString:@"doubao"] && MSIMEVoiceASRProviderUsesService(self.provider) &&
             (!IsEndpoint(self.endpoint) || self.model.length == 0 || self.token.length == 0))
        message = @"请填写 HTTPS 识别地址、模型名称和 API 密钥。";
    if (self.polishEnabled &&
        (!IsEndpoint(self.polishEndpoint) || self.polishModel.length == 0 || self.polishToken.length == 0))
        message = @"启用文本整理需要 HTTPS 服务地址、模型名称和 API 密钥。";
    if (message)
    {
        if (error)
            *error = Error(message);
        return NO;
    }
    return YES;
}
- (BOOL)save:(NSError **)error
{
    if (![self validate:error])
        return NO;
    NSUserDefaults *defaults = NSUserDefaults.standardUserDefaults;
    NSString *previousProvider = [defaults stringForKey:@"MSIMEClientVoiceASRProvider"] ?: @"";
    NSString *previousEndpoint = [defaults stringForKey:@"MSIMEClientVoiceASREndpoint"] ?: @"";
    NSString *polishProvider = [defaults stringForKey:@"MSIMEClientVoicePolishProvider"] ?: MSIMEVoicePolishDefaultProvider;
    NSString *previousPolishEndpoint = [defaults stringForKey:@"MSIMEClientVoicePolishEndpoint"] ?: @"";
    const BOOL serviceProvider = MSIMEVoiceASRProviderUsesService(self.provider);
    const BOOL changedProvider = previousProvider.length &&
        ![previousProvider.lowercaseString isEqual:self.provider.lowercaseString];
    NSString *previousToken = [self.tokenSlots[previousProvider] isKindOfClass:NSString.class]
        ? self.tokenSlots[previousProvider] : @"";
    const BOOL migratePrevious = changedProvider && MSIMEVoiceASRProviderUsesService(previousProvider) &&
        previousEndpoint.length && previousToken.length;
    if ((migratePrevious && !WriteToken(@"asr", previousProvider, previousEndpoint, previousToken, error)) ||
        (serviceProvider && !WriteToken(@"asr", self.provider, self.endpoint, self.token, error)) ||
        !WriteToken(@"polish", polishProvider, self.polishEndpoint, self.polishToken, error))
        return NO;
    if (migratePrevious) DeleteKey(LegacyKey(@"asr", previousEndpoint));
    if (!changedProvider) DeleteKey(LegacyKey(@"asr", self.endpoint));
    DeleteKey(LegacyKey(@"polish", self.polishEndpoint));
    // An endpoint edit for the same provider retires that provider's old
    // credential. Switching providers preserves the provider being left.
    if (MSIMEVoiceProviderShouldDeletePreviousCredential(previousProvider, previousEndpoint,
                                                         self.provider, self.endpoint))
        DeleteToken(@"asr", previousProvider, previousEndpoint);
    if (previousPolishEndpoint.length &&
        ![MSIMEVoiceProviderCredentialAccount(@"polish", polishProvider, previousPolishEndpoint)
            isEqual:MSIMEVoiceProviderCredentialAccount(@"polish", polishProvider, self.polishEndpoint)])
        DeleteToken(@"polish", polishProvider, previousPolishEndpoint);
    [defaults setObject:@{
        @"provider" : self.provider,
        @"endpoint" : self.endpoint,
        @"model" : self.model,
        @"modelPath" : self.modelPath,
        @"polishEnabled" : @(self.polishEnabled),
        @"polishEndpoint" : self.polishEndpoint,
        @"polishModel" : self.polishModel,
        @"captureDevice" : self.captureDevice ?: @""
    }
                                              forKey:@"voiceInput"];
    // What the input method actually reads on the next recording. Driven by the shared key table so a
    // field added to this window cannot be saved into the private dictionary alone.
    NSDictionary *values = @{
        @"provider" : self.provider,
        @"endpoint" : self.endpoint,
        @"model" : self.model,
        @"modelPath" : self.modelPath,
        @"token" : self.token,
        @"polishEndpoint" : self.polishEndpoint,
        @"polishModel" : self.polishModel,
        @"polishToken" : self.polishToken,
        @"captureDevice" : self.captureDevice ?: @""
    };
    NSDictionary<NSString *, NSString *> *sharedKeys = MSIMEVoiceProviderSharedKeys();
    for (NSString *field in values)
        [defaults setObject:values[field] forKey:sharedKeys[field]];
    [defaults setObject:MSIMEVoiceProviderTokenSlotsByUpdating(
                            self.tokenSlots ?: [defaults objectForKey:@"MSIMEClientVoiceASRTokens"], self.provider,
                            self.token, serviceProvider)
                 forKey:@"MSIMEClientVoiceASRTokens"];
    [defaults setObject:MSIMEVoiceProviderTokenSlotsByUpdating(
                            [defaults objectForKey:@"MSIMEClientVoicePolishTokens"], polishProvider,
                            self.polishToken, YES)
                 forKey:@"MSIMEClientVoicePolishTokens"];
    [defaults setBool:self.polishEnabled forKey:@"MSIMEClientVoicePolish"];
    [[NSNotificationCenter defaultCenter] postNotificationName:MSIMEVoiceProviderSettingsDidChangeNotification object:self];
    return YES;
}
@end

// The form is a view rather than a window's contents: the same controls are the 语音输入 page of
// the settings window and the contents of the standalone window the input method's toolbar opens.
// Upstream laid it out in absolute coordinates inside a fixed 610x580 window, which is why it could
// only ever be a window.
@interface MetasequoiaVoiceProviderSettingsView () <NSTextFieldDelegate>
@end
@implementation MetasequoiaVoiceProviderSettingsView
{
    NSPopUpButton *_provider;
    NSPopUpButton *_captureDevice;
    NSTextField *_endpoint, *_model, *_modelPath, *_polishEndpoint, *_polishModel;
    NSSecureTextField *_token, *_polishToken;
    NSSwitch *_polish;
    NSTextField *_status;
    NSString *_loadedProvider;
    NSMutableDictionary<NSString *, NSString *> *_tokenDrafts;
    /// Set while the controls are being filled from storage, so populating them saves nothing.
    BOOL _loading;
}

- (NSTextField *)fieldLabelled:(NSString *)label secure:(BOOL)secure
{
    NSTextField *field = secure ? [NSSecureTextField new] : [NSTextField new];
    field.accessibilityLabel = label;
    field.delegate = self;
    field.translatesAutoresizingMaskIntoConstraints = NO;
    return field;
}

- (instancetype)initWithFrame:(NSRect)frameRect
{
    self = [super initWithFrame:frameRect];
    if (self == nil)
    {
        return nil;
    }
    self.translatesAutoresizingMaskIntoConstraints = NO;
    _tokenDrafts = [NSMutableDictionary dictionary];

    _provider = [[NSPopUpButton alloc] initWithFrame:NSZeroRect pullsDown:NO];
    _provider.accessibilityLabel = @"识别方式";
    [_provider addItemsWithTitles:MSIMEVoiceASRProviderTitles()];
    _provider.target = self;
    _provider.action = @selector(providerChanged:);
    _endpoint = [self fieldLabelled:@"识别服务地址" secure:NO];
    _model = [self fieldLabelled:@"识别模型" secure:NO];
    _token = (NSSecureTextField *)[self fieldLabelled:@"API 密钥" secure:YES];
    _modelPath = [self fieldLabelled:@"本地模型" secure:NO];
    NSButton *browse = [NSButton buttonWithTitle:@"选择…" target:self action:@selector(browse:)];
    NSStackView *modelPathRow = [NSStackView stackViewWithViews:@[ _modelPath, browse ]];
    modelPathRow.orientation = NSUserInterfaceLayoutOrientationHorizontal;
    modelPathRow.spacing = 8.0;
    _captureDevice = [[NSPopUpButton alloc] initWithFrame:NSZeroRect pullsDown:NO];
    _captureDevice.accessibilityLabel = @"录音设备";
    _captureDevice.target = self;
    _captureDevice.action = @selector(commit:);
    _polish = MSIMESettingSwitch(self, @selector(polishChanged:), @"识别后整理文本");
    _polishEndpoint = [self fieldLabelled:@"整理服务地址" secure:NO];
    _polishModel = [self fieldLabelled:@"整理模型" secure:NO];
    _polishToken = (NSSecureTextField *)[self fieldLabelled:@"整理 API 密钥" secure:YES];

    NSBox *recognitionCard = MSIMECardWithViews(@[
        MSIMEPreferenceRow(@"识别方式", _provider),
        MSIMEPreferenceRow(@"服务地址", _endpoint),
        MSIMEPreferenceRow(@"识别模型", _model),
        MSIMEPreferenceRow(@"API 密钥", _token),
        MSIMEPreferenceRowOfWidth(@"本地模型", modelPathRow, msime::mac::layout::kWideControlWidth),
        MSIMEPreferenceRow(@"录音设备", _captureDevice),
    ], 0.0);
    recognitionCard.accessibilityLabel = @"语音识别卡片";
    NSBox *polishCard = MSIMECardWithViews(@[
        MSIMESwitchRow(@"识别后整理文本", _polish, @"会把本次转写的文本发送到下面的服务"),
        MSIMEPreferenceRow(@"服务地址", _polishEndpoint),
        MSIMEPreferenceRow(@"整理模型", _polishModel),
        MSIMEPreferenceRow(@"API 密钥", _polishToken),
    ], 0.0);
    polishCard.accessibilityLabel = @"文本整理卡片";

    NSTextField *hint = [NSTextField
        wrappingLabelWithString:@"Control+Option+V 开始/结束，Esc "
                                @"取消。云端识别会发送本次录音；本地识别使用所选模型。密钥保存在系统钥匙串中。"];
    hint.font = [NSFont systemFontOfSize:11.0];
    hint.textColor = NSColor.secondaryLabelColor;
    _status = [NSTextField wrappingLabelWithString:@""];
    _status.font = [NSFont systemFontOfSize:msime::mac::layout::kBodyFontSize];
    _status.textColor = NSColor.systemRedColor;
    _status.accessibilityLabel = @"语音设置状态";
    _status.hidden = YES;

    NSStackView *stack = [NSStackView stackViewWithViews:@[
        MSIMESectionLabel(@"语音识别"), recognitionCard,
        MSIMESectionLabel(@"文本整理"), polishCard,
        hint, _status,
    ]];
    stack.orientation = NSUserInterfaceLayoutOrientationVertical;
    stack.alignment = NSLayoutAttributeLeading;
    stack.distribution = NSStackViewDistributionFill;
    stack.spacing = 10.0;
    stack.translatesAutoresizingMaskIntoConstraints = NO;
    [self addSubview:stack];
    for (NSView *view in stack.arrangedSubviews)
    {
        [view.widthAnchor constraintEqualToAnchor:stack.widthAnchor].active = YES;
    }
    [NSLayoutConstraint activateConstraints:@[
        [stack.leadingAnchor constraintEqualToAnchor:self.leadingAnchor],
        [stack.trailingAnchor constraintEqualToAnchor:self.trailingAnchor],
        [stack.topAnchor constraintEqualToAnchor:self.topAnchor],
        [stack.bottomAnchor constraintEqualToAnchor:self.bottomAnchor],
    ]];
    [self reloadSettings];
    return self;
}

- (void)reloadSettings
{
    _loading = YES;
    MetasequoiaVoiceProviderSettings *value = [MetasequoiaVoiceProviderSettings loadSettings];
    NSArray *providerIDs = MSIMEVoiceASRProviderIDs();
    NSUInteger providerIndex = [providerIDs indexOfObject:value.provider];
    [_provider selectItemAtIndex:providerIndex == NSNotFound ? 0 : providerIndex];
    _endpoint.stringValue = value.endpoint;
    _model.stringValue = value.model;
    _token.stringValue = value.token;
    _loadedProvider = value.provider;
    _tokenDrafts = [value.tokenSlots mutableCopy] ?: [NSMutableDictionary dictionary];
    if (MSIMEVoiceASRProviderUsesService(_loadedProvider))
    {
        _tokenDrafts[_loadedProvider] = value.token ?: @"";
    }
    _modelPath.stringValue = value.modelPath;
    [_captureDevice removeAllItems];
    NSMenuItem *automatic = [[NSMenuItem alloc] initWithTitle:@"系统默认" action:nil keyEquivalent:@""];
    automatic.representedObject = @"";
    [_captureDevice.menu addItem:automatic];
    BOOL foundCaptureDevice = value.captureDevice.length == 0;
    for (NSDictionary *device in MSIMEListVoiceCaptureDevices())
    {
        NSString *uid = device[@"uid"], *name = device[@"name"];
        NSString *title =
            [device[@"default"] boolValue] ? [NSString stringWithFormat:@"%@（当前系统默认）", name] : name;
        NSMenuItem *item = [[NSMenuItem alloc] initWithTitle:title action:nil keyEquivalent:@""];
        item.representedObject = uid;
        [_captureDevice.menu addItem:item];
        if ([uid isEqual:value.captureDevice])
        {
            [_captureDevice selectItem:item];
            foundCaptureDevice = YES;
        }
    }
    if (!foundCaptureDevice)
    {
        NSMenuItem *unavailable =
            [[NSMenuItem alloc] initWithTitle:@"已保存的录音设备（当前不可用）" action:nil keyEquivalent:@""];
        unavailable.representedObject = value.captureDevice;
        [_captureDevice.menu addItem:unavailable];
        [_captureDevice selectItem:unavailable];
    }
    else if (value.captureDevice.length == 0)
    {
        [_captureDevice selectItem:automatic];
    }
    _polish.state = value.polishEnabled ? NSControlStateValueOn : NSControlStateValueOff;
    _polishEndpoint.stringValue = value.polishEndpoint;
    _polishModel.stringValue = value.polishModel;
    _polishToken.stringValue = value.polishToken;
    [self updateEnabled:nil];
    _status.stringValue = @"";
    _status.hidden = YES;
    _loading = NO;
}

- (void)providerChanged:(id)sender
{
    (void)sender;
    if (MSIMEVoiceASRProviderUsesService(_loadedProvider))
    {
        _tokenDrafts[_loadedProvider] = _token.stringValue ?: @"";
    }
    NSArray *providerIDs = MSIMEVoiceASRProviderIDs();
    NSUInteger index = MIN((NSUInteger)_provider.indexOfSelectedItem, providerIDs.count - 1);
    NSString *provider = providerIDs[index];
    _endpoint.stringValue = MSIMEVoiceProviderValueAfterSelection(
        _endpoint.stringValue, MSIMEVoiceASRProviderDefaultEndpoint(provider), ProviderValues(@"endpoint"));
    _model.stringValue = MSIMEVoiceProviderValueAfterSelection(
        _model.stringValue, MSIMEVoiceASRProviderDefaultModel(provider), ProviderValues(@"model"));
    id draft = _tokenDrafts[provider];
    _token.stringValue = MSIMEVoiceASRProviderUsesService(provider)
        ? ([draft isKindOfClass:NSString.class] ? draft : ReadToken(@"asr", provider, _endpoint.stringValue, NO))
        : @"";
    _loadedProvider = provider;
    [self updateEnabled:nil];
    [self commit:nil];
}

- (void)polishChanged:(id)sender
{
    [self updateEnabled:sender];
    [self commit:sender];
}

- (void)updateEnabled:(id)sender
{
    (void)sender;
    NSArray *providerIDs = MSIMEVoiceASRProviderIDs();
    NSString *provider = providerIDs[MIN((NSUInteger)_provider.indexOfSelectedItem, providerIDs.count - 1)];
    BOOL service = MSIMEVoiceASRProviderUsesService(provider);
    _endpoint.enabled = service;
    _model.enabled = service && ![provider isEqualToString:@"doubao"];
    _token.enabled = service;
    _modelPath.enabled = [provider isEqualToString:@"local"];
    BOOL polish = _polish.state == NSControlStateValueOn;
    _polishEndpoint.enabled = polish;
    _polishModel.enabled = polish;
    _polishToken.enabled = polish;
}

- (void)controlTextDidChange:(NSNotification *)notification
{
    if (notification.object == _endpoint)
    {
        _token.stringValue = @"";
    }
    if (notification.object == _polishEndpoint)
    {
        _polishToken.stringValue = @"";
    }
}

// Everything is stored as soon as it is set: a popup or a switch the moment it changes, a field
// when it loses focus — which is also when a key reaches the keychain, rather than on every
// keystroke. Upstream collected the whole form behind a 保存 button, so a change made and not
// confirmed was discarded without a word when the window went away.
- (void)controlTextDidEndEditing:(NSNotification *)notification
{
    (void)notification;
    [self commit:nil];
}

- (void)commit:(id)sender
{
    (void)sender;
    if (_loading)
    {
        return;
    }
    MetasequoiaVoiceProviderSettings *value = [MetasequoiaVoiceProviderSettings new];
    NSArray *providerIDs = MSIMEVoiceASRProviderIDs();
    value.provider = providerIDs[MIN((NSUInteger)_provider.indexOfSelectedItem, providerIDs.count - 1)];
    value.endpoint = _endpoint.stringValue;
    value.model = _model.stringValue;
    value.token = _token.stringValue;
    if (MSIMEVoiceASRProviderUsesService(value.provider))
    {
        _tokenDrafts[value.provider] = value.token ?: @"";
    }
    else
    {
        [_tokenDrafts removeObjectForKey:value.provider];
    }
    value.tokenSlots = [_tokenDrafts copy];
    value.modelPath = _modelPath.stringValue;
    value.polishEnabled = _polish.state == NSControlStateValueOn;
    value.polishEndpoint = _polishEndpoint.stringValue;
    value.polishModel = _polishModel.stringValue;
    value.polishToken = _polishToken.stringValue;
    id captureDevice = _captureDevice.selectedItem.representedObject;
    value.captureDevice = [captureDevice isKindOfClass:NSString.class] ? captureDevice : @"";
    NSError *error = nil;
    const BOOL saved = [value save:&error];
    _status.stringValue = saved ? @"" : (error.localizedDescription ?: @"设置未能保存。");
    _status.hidden = saved;
}

- (void)browse:(id)sender
{
    (void)sender;
    NSOpenPanel *panel = [NSOpenPanel openPanel];
    panel.canChooseDirectories = YES;
    panel.allowsMultipleSelection = NO;
    __weak MetasequoiaVoiceProviderSettingsView *weakSelf = self;
    [panel beginSheetModalForWindow:self.window
                  completionHandler:^(NSModalResponse response) {
                    if (response != NSModalResponseOK) return;
                    MetasequoiaVoiceProviderSettingsView *strongSelf = weakSelf;
                    strongSelf->_modelPath.stringValue = panel.URL.path;
                    [strongSelf commit:nil];
                  }];
}
@end

@implementation MetasequoiaVoiceProviderSettingsWindow
{
    MetasequoiaVoiceProviderSettingsView *_form;
}
+ (instancetype)sharedController
{
    static MetasequoiaVoiceProviderSettingsWindow *window;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
      window = [self new];
    });
    return window;
}
- (instancetype)init
{
    NSWindow *window = [[NSWindow alloc] initWithContentRect:NSMakeRect(0, 0, 620, 560)
                                                   styleMask:NSWindowStyleMaskTitled | NSWindowStyleMaskClosable |
                                                             NSWindowStyleMaskResizable
                                                     backing:NSBackingStoreBuffered
                                                       defer:NO];
    self = [super initWithWindow:window];
    if (self)
    {
        window.title = @"语音输入设置";
        window.releasedWhenClosed = NO;
        _form = [[MetasequoiaVoiceProviderSettingsView alloc] initWithFrame:NSZeroRect];
        [window.contentView addSubview:_form];
        [NSLayoutConstraint activateConstraints:@[
            [_form.leadingAnchor constraintEqualToAnchor:window.contentView.leadingAnchor constant:20.0],
            [_form.trailingAnchor constraintEqualToAnchor:window.contentView.trailingAnchor constant:-20.0],
            [_form.topAnchor constraintEqualToAnchor:window.contentView.topAnchor constant:20.0],
            [_form.bottomAnchor constraintLessThanOrEqualToAnchor:window.contentView.bottomAnchor constant:-20.0],
        ]];
        [window center];
    }
    return self;
}
- (void)showAndActivate
{
    [_form reloadSettings];
    [self showWindow:nil];
    [NSApp activateIgnoringOtherApps:YES];
}
@end
