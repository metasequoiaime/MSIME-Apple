#import "../SharedVoicePreferences.h"
#include <cassert>

int main() {
    @autoreleasepool {
        NSString *suite = [@"app.msime.test.voice." stringByAppendingString:NSUUID.UUID.UUIDString];
        NSUserDefaults *defaults = [[NSUserDefaults alloc] initWithSuiteName:suite];
        assert(MSIMEVoiceInputEnabled(defaults));
        NSDictionary *voice = @{
            @"enabled": @NO, @"hotkey_rctrl_ralt": @YES,
            @"language": @"en-US", @"asr_provider": @"openai",
            @"asr_endpoint": @"https://example.invalid/asr", @"asr_model": @"fixture-model",
            @"asr_token": @"fixture-only", @"capture_device": @"fixture-device",
            @"asr_app_key": @"fixture-app", @"asr_resource_id": @"fixture-resource",
            @"doubao_boosting_table_id": @"fixture-table", @"polish_provider": @"groq",
            @"polish_endpoint": @"https://example.invalid/polish", @"polish_model": @"fixture-polish",
            @"polish_token": @"fixture-only", @"polish_prompt_id": @"custom1",
            @"polish_prompt": @"fixture", @"polish_prompt_custom_1": @"one",
            @"polish_prompt_custom_2": @"two", @"polish_prompt_custom_3": @"three",
            @"sound_enabled": @NO, @"mute_system_audio": @YES, @"stream_inline_preedit": @NO,
            @"polish_enabled": @YES, @"hotkey_ctrl_f9": @NO,
            @"hotkey_hold_space_lock": @NO, @"hotkey_ralt": @YES, @"hotkey_ctrl_win": @YES
        };
        MSIMEApplySharedVoicePreferences(voice, defaults);
        assert(!MSIMEVoiceInputEnabled(defaults));
        assert([defaults boolForKey:@"MSIMEClientVoiceHotkeyCtrlOption"]);
        assert([[defaults stringForKey:@"MSIMEClientVoiceCaptureDevice"] isEqual:@"fixture-device"]);
        assert([[defaults stringForKey:@"MSIMEClientVoiceASRProvider"] isEqual:@"openai"]);
        assert([[defaults stringForKey:@"MSIMEClientVoiceASREndpoint"] isEqual:voice[@"asr_endpoint"]]);
        assert([[defaults stringForKey:@"MSIMEClientVoicePolishPromptCustom3"] isEqual:@"three"]);
        assert([defaults boolForKey:@"MSIMEClientVoicePolish"]);
        assert([defaults boolForKey:@"MSIMEClientVoiceHotkeyCtrlCommand"]);
        assert(![defaults boolForKey:@"MSIMEClientVoiceSoundEnabled"]);
        NSDictionary *saved = [defaults persistentDomainForName:suite];
        assert(saved.count == voice.count);
        MSIMEApplySharedVoicePreferences(voice, defaults);
        MSIMEApplySharedVoicePreferences(nil, defaults);
        MSIMEApplySharedVoicePreferences(NSNull.null, defaults);
        MSIMEApplySharedVoicePreferences(@[], defaults);
        MSIMEApplySharedVoicePreferences(@{@"asr_token": NSNull.null, @"capture_device": @42,
                                           @"polish_enabled": @0, @"sound_enabled": @"true",
                                           @"enabled": @"true", @"hotkey_rctrl_ralt": @0}, defaults);
        assert([[defaults persistentDomainForName:suite] isEqual:saved]);
        MSIMEApplySharedVoicePreferences(@{@"capture_device": @"", @"asr_token": @"",
                                           @"polish_enabled": @NO}, defaults);
        assert([[defaults stringForKey:@"MSIMEClientVoiceCaptureDevice"] isEqual:@""]);
        assert([[defaults stringForKey:@"MSIMEClientVoiceASRToken"] isEqual:@""]);
        assert(![defaults boolForKey:@"MSIMEClientVoicePolish"]);
        MSIMEApplySharedVoicePreferences(@{@"enabled": @YES, @"hotkey_rctrl_ralt": @NO}, defaults);
        assert(MSIMEVoiceInputEnabled(defaults));
        assert(![defaults boolForKey:@"MSIMEClientVoiceHotkeyCtrlOption"]);
        [defaults removePersistentDomainForName:suite];
    }
}
