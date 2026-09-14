#pragma once
#import <Foundation/Foundation.h>

// Match the shared default while preserving explicit disablement.
static inline BOOL MSIMEVoiceInputEnabled(NSUserDefaults *defaults) {
    return [defaults objectForKey:@"MSIMEClientVoiceEnabled"] == nil ||
        [defaults boolForKey:@"MSIMEClientVoiceEnabled"];
}

static inline BOOL MSIMEVoiceCueEnabled(NSUserDefaults *defaults, BOOL start) {
    NSString *key = start ? @"MSIMEClientVoiceStartSound" : @"MSIMEClientVoiceEndSound";
    return ([defaults objectForKey:@"MSIMEClientVoiceSoundEnabled"] == nil ||
            [defaults boolForKey:@"MSIMEClientVoiceSoundEnabled"]) &&
           ([defaults objectForKey:key] == nil || [defaults boolForKey:key]);
}

// Adapt shared settings to the legacy native consumers. Missing or malformed
// fields preserve local values; explicit false and empty strings clear them.
// Reloading settings must not restart an active recording or emit save events.
static inline void MSIMEApplySharedVoicePreferences(id voice, NSUserDefaults *defaults) {
    if (![voice isKindOfClass:NSDictionary.class]) return;
    NSDictionary *strings = @{
        @"language": @"Language",
        @"asr_provider": @"ASRProvider", @"asr_endpoint": @"ASREndpoint",
        @"asr_model": @"ASRModel", @"asr_token": @"ASRToken",
        @"capture_device": @"CaptureDevice",
        @"asr_app_key": @"DoubaoAppKey", @"asr_resource_id": @"DoubaoResourceID",
        @"doubao_auth_mode": @"DoubaoAuthMode",
        @"doubao_boosting_table_id": @"DoubaoBoostingTableID",
        @"polish_provider": @"PolishProvider", @"polish_endpoint": @"PolishEndpoint",
        @"polish_model": @"PolishModel", @"polish_token": @"PolishToken",
        @"polish_prompt_id": @"PolishPromptID", @"polish_prompt": @"PolishPrompt",
        @"polish_prompt_custom_1": @"PolishPromptCustom1",
        @"polish_prompt_custom_2": @"PolishPromptCustom2",
        @"polish_prompt_custom_3": @"PolishPromptCustom3"
    };
    for (NSString *field in strings) {
        id value = voice[field];
        if ([value isKindOfClass:NSString.class]) {
            NSString *key = [@"MSIMEClientVoice" stringByAppendingString:strings[field]];
            if (![[defaults objectForKey:key] isEqual:value]) [defaults setObject:value forKey:key];
        }
    }
    NSDictionary *booleans = @{
        @"enabled": @"Enabled",
        @"start_sound": @"StartSound", @"end_sound": @"EndSound",
        @"sound_enabled": @"SoundEnabled", @"mute_system_audio": @"MuteSystemAudio",
        @"stream_inline_preedit": @"StreamInlinePreedit", @"polish_enabled": @"Polish",
        @"doubao_enable_itn": @"DoubaoEnableITN",
        @"doubao_enable_punc": @"DoubaoEnablePunctuation",
        @"doubao_enable_ddc": @"DoubaoEnableDDC",
        @"hotkey_ctrl_f9": @"HotkeyCtrlF9", @"hotkey_hold_space_lock": @"HotkeyHoldSpace",
        @"hotkey_ralt": @"HotkeyRightAlt",
        @"hotkey_rctrl_ralt": @"HotkeyCtrlOption",
        // The shared Windows modifier is Command on macOS.
        @"hotkey_ctrl_win": @"HotkeyCtrlCommand"
    };
    for (NSString *field in booleans) {
        id value = voice[field];
        if ([value isKindOfClass:NSNumber.class] &&
            CFGetTypeID((__bridge CFTypeRef)value) == CFBooleanGetTypeID()) {
            NSString *key = [@"MSIMEClientVoice" stringByAppendingString:booleans[field]];
            if (![[defaults objectForKey:key] isEqual:value]) [defaults setObject:value forKey:key];
        }
    }
}
