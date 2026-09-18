#pragma once
#import <Foundation/Foundation.h>

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
