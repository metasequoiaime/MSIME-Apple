#pragma once
#import <Foundation/Foundation.h>

// Decide the in-process recognition transport from the persisted provider id.
// Keep this pure so the settings surface and controller cannot silently drift:
// every HTTPS multipart preset belongs to the batch request path, while Doubao
// and system Speech have dedicated transports. An external provider socket owns
// all provider routing when present.
static inline BOOL MSIMEVoiceUsesNativeHTTPProvider(NSString *provider,
                                                     BOOL providerSocketAvailable,
                                                     BOOL localASRAvailable) {
    if (providerSocketAvailable) return NO;
    NSString *identifier = provider.lowercaseString ?: @"";
    if ([identifier isEqual:@"local"]) return localASRAvailable;
    return [@[@"openai", @"groq", @"siliconflow", @"everyapi", @"mistral", @"cloud"]
        containsObject:identifier];
}

// MSIME-Windows StartRecording refuses to record when the current ASR provider has no API token, and tells the user where to fill it in. Here that covers the providers this host calls itself with a token - the HTTPS presets and Doubao, which an unset provider preference means - and not the on-device, system Speech or external-socket paths, which take none from this preference.
static inline BOOL MSIMEVoiceASRTokenMissing(NSString *provider, NSString *token, BOOL providerSocketAvailable) {
    if (providerSocketAvailable || token.length) return NO;
    return !provider || [provider.lowercaseString isEqual:@"doubao"] ||
        MSIMEVoiceUsesNativeHTTPProvider(provider, NO, NO);
}

// Adapt native preferences to the existing provider contract. Do not infer an
// authentication mode here: older configurations rely on provider-side inference.
static inline NSDictionary *MSIMEVoiceProviderOptions(NSDictionary *query, NSUserDefaults *defaults) {
    NSMutableDictionary *result = [query mutableCopy];
    id commitMode = [defaults objectForKey:@"MSIMEClientVoiceCommitMode"];
    result[@"commit_mode"] = [commitMode isKindOfClass:NSString.class] &&
        [@[@"tsf", @"sendinput", @"ctrl_v"] containsObject:commitMode] ? commitMode : @"tsf";
    id mode = [defaults objectForKey:@"MSIMEClientVoiceDoubaoAuthMode"];
    if ([mode isKindOfClass:NSString.class] && [@[@"api_key", @"legacy"] containsObject:mode])
        result[@"doubao_auth_mode"] = mode;
    else
        [result removeObjectForKey:@"doubao_auth_mode"];
    NSArray *options = @[
        @[@"polish_text", @"MSIMEClientVoicePolishText", @NO],
        @[@"doubao_enable_itn", @"MSIMEClientVoiceDoubaoEnableITN", @YES],
        @[@"doubao_enable_punc", @"MSIMEClientVoiceDoubaoEnablePunctuation", @YES],
        @[@"doubao_enable_ddc", @"MSIMEClientVoiceDoubaoEnableDDC", @NO]
    ];
    for (NSArray *option in options) {
        id value = [defaults objectForKey:option[1]];
        BOOL valid = [value isKindOfClass:NSNumber.class] &&
            CFGetTypeID((__bridge CFTypeRef)value) == CFBooleanGetTypeID();
        result[option[0]] = valid ? value : option[2];
    }
    return [result copy];
}
