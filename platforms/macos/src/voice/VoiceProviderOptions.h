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

// Adapt native preferences to the existing provider contract. Do not infer an
// authentication mode here: older configurations rely on provider-side inference.
// The boolean fallbacks match the shared macOS first-run defaults (`source_voice_default` in client-core).
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
        @[@"polish_text", @"MSIMEClientVoicePolishText", @YES],
        @[@"doubao_enable_itn", @"MSIMEClientVoiceDoubaoEnableITN", @YES],
        @[@"doubao_enable_punc", @"MSIMEClientVoiceDoubaoEnablePunctuation", @YES],
        @[@"doubao_enable_ddc", @"MSIMEClientVoiceDoubaoEnableDDC", @YES]
    ];
    for (NSArray *option in options) {
        id value = [defaults objectForKey:option[1]];
        BOOL valid = [value isKindOfClass:NSNumber.class] &&
            CFGetTypeID((__bridge CFTypeRef)value) == CFBooleanGetTypeID();
        result[option[0]] = valid ? value : option[2];
    }
    return [result copy];
}
