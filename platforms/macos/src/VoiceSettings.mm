#import "VoiceSettings.h"
#import <Security/Security.h>

namespace
{
NSString *const service = @"app.msime.inputmethod.MetasequoiaIME.voice";
NSError *Error(NSString *message)
{
    return [NSError errorWithDomain:service code:1 userInfo:@{NSLocalizedDescriptionKey : message}];
}
NSDictionary *Key(NSString *kind, NSString *endpoint)
{
    NSURL *url = [NSURL URLWithString:endpoint];
    NSString *origin = [NSString
        stringWithFormat:@"%@://%@:%@", (url.scheme.lowercaseString ? url.scheme.lowercaseString : @""),
                         (url.host.lowercaseString ? url.host.lowercaseString : @""), (url.port ? url.port : @443)];
    return @{
        (__bridge id)kSecClass : (__bridge id)kSecClassGenericPassword,
        (__bridge id)kSecAttrService : service,
        (__bridge id)kSecAttrAccount : [kind stringByAppendingFormat:@"|%@", origin]
    };
}
NSString *ReadToken(NSString *kind, NSString *endpoint)
{
    NSMutableDictionary *query = [Key(kind, endpoint) mutableCopy];
    query[(__bridge id)kSecReturnData] = @YES;
    CFTypeRef result = nullptr;
    OSStatus status = SecItemCopyMatching((__bridge CFDictionaryRef)query, &result);
    if (status != errSecSuccess)
        return @"";
    NSData *data = CFBridgingRelease(result);
    NSString *text = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
    return text ? text : @"";
}
BOOL WriteToken(NSString *kind, NSString *endpoint, NSString *token, NSError **error)
{
    NSDictionary *query = Key(kind, endpoint);
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
// The account carries the endpoint origin, so editing an endpoint writes a new item and WriteToken
// only ever deletes the origin it was handed — the bearer token for the previous origin stayed in
// the login keychain indefinitely. Every save prunes whatever this service owns beyond the two
// accounts currently in use.
void PruneTokens(NSArray<NSDictionary *> *keptKeys)
{
    NSMutableSet<NSString *> *keptAccounts = [NSMutableSet set];
    for (NSDictionary *key in keptKeys)
    {
        [keptAccounts addObject:key[(__bridge id)kSecAttrAccount]];
    }
    NSDictionary *query = @{
        (__bridge id)kSecClass : (__bridge id)kSecClassGenericPassword,
        (__bridge id)kSecAttrService : service,
        (__bridge id)kSecMatchLimit : (__bridge id)kSecMatchLimitAll,
        (__bridge id)kSecReturnAttributes : @YES
    };
    CFTypeRef result = nullptr;
    if (SecItemCopyMatching((__bridge CFDictionaryRef)query, &result) != errSecSuccess)
        return;
    NSArray<NSDictionary *> *items = CFBridgingRelease(result);
    for (NSDictionary *item in items)
    {
        NSString *account = item[(__bridge id)kSecAttrAccount];
        if (account.length == 0 || [keptAccounts containsObject:account])
            continue;
        SecItemDelete((__bridge CFDictionaryRef) @{
            (__bridge id)kSecClass : (__bridge id)kSecClassGenericPassword,
            (__bridge id)kSecAttrService : service,
            (__bridge id)kSecAttrAccount : account
        });
    }
}
BOOL IsEndpoint(NSString *value)
{
    NSURLComponents *url = [NSURLComponents componentsWithString:value];
    return [url.scheme.lowercaseString isEqualToString:@"https"] && url.host.length > 0 && !url.user && !url.password &&
           !url.fragment;
}
} // namespace
@implementation MetasequoiaVoiceSettings
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

+ (instancetype)loadSettings
{
    MetasequoiaVoiceSettings *value = [self new];
    NSDictionary *saved = [[NSUserDefaults standardUserDefaults] dictionaryForKey:@"voiceInput"];
    if (!saved)
        saved = @{};
    value.provider = StringSetting(saved, @"provider", @"cloud");
    value.endpoint = StringSetting(saved, @"endpoint", @"https://api.siliconflow.cn/v1/audio/transcriptions");
    value.model = StringSetting(saved, @"model", @"FunAudioLLM/SenseVoiceSmall");
    value.modelPath = StringSetting(saved, @"modelPath", @"");
    id polishEnabled = saved[@"polishEnabled"];
    value.polishEnabled =
        [polishEnabled isKindOfClass:[NSNumber class]] || [polishEnabled isKindOfClass:[NSString class]]
            ? [polishEnabled boolValue]
            : NO;
    value.polishEndpoint = StringSetting(saved, @"polishEndpoint", @"https://api.siliconflow.cn/v1/chat/completions");
    value.polishModel = StringSetting(saved, @"polishModel", @"Qwen/Qwen3-8B");
    value.token = ReadToken(@"asr", value.endpoint);
    value.polishToken = ReadToken(@"polish", value.polishEndpoint);
    return value;
}
- (BOOL)validate:(NSError **)error
{
    NSString *message = nil;
    if ([self.provider isEqualToString:@"local"])
    {
        BOOL directory = NO;
        if (![[NSFileManager defaultManager] fileExistsAtPath:self.modelPath isDirectory:&directory] || directory)
            message = @"请选择已下载的 Whisper 模型文件。";
    }
    else if (![self.provider isEqualToString:@"cloud"])
        message = @"请选择识别方式。";
    else if (!IsEndpoint(self.endpoint) || self.model.length == 0 || self.token.length == 0)
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
    if (!WriteToken(@"asr", self.endpoint, self.token, error) ||
        !WriteToken(@"polish", self.polishEndpoint, self.polishToken, error))
        return NO;
    PruneTokens(@[ Key(@"asr", self.endpoint), Key(@"polish", self.polishEndpoint) ]);
    [[NSUserDefaults standardUserDefaults] setObject:@{
        @"provider" : self.provider,
        @"endpoint" : self.endpoint,
        @"model" : self.model,
        @"modelPath" : self.modelPath,
        @"polishEnabled" : @(self.polishEnabled),
        @"polishEndpoint" : self.polishEndpoint,
        @"polishModel" : self.polishModel
    }
                                              forKey:@"voiceInput"];
    return YES;
}
@end
