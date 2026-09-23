#import "../../src/core/SharedVoicePreferences.h"
#import "../../src/voice/VoiceProviderOptions.h"
#include <cassert>
#import "../settings/TestPreferenceSuite.h"

int main() {
    @autoreleasepool {
        NSString *suite = [@"app.msime.test.provider." stringByAppendingString:NSUUID.UUID.UUIDString];
        NSUserDefaults *defaults = [[NSUserDefaults alloc] initWithSuiteName:suite];
        // Every provider offered as an HTTPS multipart preset must use the batch request path.
        // Falling through starts macOS Speech and silently ignores the selected endpoint and token.
        for (NSString *provider in @[@"openai", @"groq", @"siliconflow", @"everyapi", @"mistral", @"cloud"])
            assert(MSIMEVoiceUsesNativeHTTPProvider(provider, NO, NO));
        for (NSString *provider in @[@"doubao", @"system", @"unknown", @""])
            assert(!MSIMEVoiceUsesNativeHTTPProvider(provider, NO, NO));
        assert(!MSIMEVoiceUsesNativeHTTPProvider(@"everyapi", YES, NO));
        assert(!MSIMEVoiceUsesNativeHTTPProvider(@"local", NO, NO));
        assert(MSIMEVoiceUsesNativeHTTPProvider(@"local", NO, YES));
        NSDictionary *base = @{@"generation": @42, @"language": @"en-us", @"asr_provider": @"doubao"};
        NSDictionary *query = MSIMEVoiceProviderOptions(base, defaults);
        assert([query[@"commit_mode"] isEqual:@"tsf"]);
        for (NSString *mode in @[@"tsf", @"sendinput", @"ctrl_v"]) {
            MSIMEApplySharedVoicePreferences(@{@"commit_mode": mode}, defaults);
            assert([MSIMEVoiceProviderOptions(base, defaults)[@"commit_mode"] isEqual:mode]);
        }
        for (id invalid in @[@"unknown", @42, @[]]) {
            [defaults setObject:invalid forKey:@"MSIMEClientVoiceCommitMode"];
            assert([MSIMEVoiceProviderOptions(base, defaults)[@"commit_mode"] isEqual:@"tsf"]);
        }
        assert([query[@"polish_text"] isEqual:@YES]);
        assert(!query[@"doubao_auth_mode"]);
        assert([query[@"doubao_enable_itn"] isEqual:@YES]);
        assert([query[@"doubao_enable_punc"] isEqual:@YES]);
        assert([query[@"doubao_enable_ddc"] isEqual:@YES]);
        assert(MSIMEVoiceMuteSystemAudioEnabled(defaults));
        MSIMEApplySharedVoicePreferences(@{@"mute_system_audio": @NO}, defaults);
        assert(!MSIMEVoiceMuteSystemAudioEnabled(defaults));
        // Test the actual shared-settings -> native preferences -> request path.
        MSIMEApplySharedVoicePreferences(@{@"doubao_auth_mode": @"api_key",
            @"doubao_enable_itn": @NO, @"doubao_enable_punc": @NO, @"doubao_enable_ddc": @NO}, defaults);
        query = MSIMEVoiceProviderOptions(base, defaults);
        assert([query[@"doubao_auth_mode"] isEqual:@"api_key"]);
        assert([query[@"doubao_enable_itn"] isEqual:@NO]);
        assert([query[@"doubao_enable_punc"] isEqual:@NO]);
        assert([query[@"doubao_enable_ddc"] isEqual:@NO]);
        for (NSString *key in base) assert([query[key] isEqual:base[key]]);
        assert(base.count == 3 && [NSJSONSerialization isValidJSONObject:query]);
        MSIMEApplySharedVoicePreferences(@{@"polish_text": @YES, @"polish_enabled": @NO}, defaults);
        assert([MSIMEVoiceProviderOptions(base, defaults)[@"polish_text"] isEqual:@YES]);
        MSIMEApplySharedVoicePreferences(@{@"polish_text": @NO}, defaults);
        assert([MSIMEVoiceProviderOptions(base, defaults)[@"polish_text"] isEqual:@NO]);
        MSIMEApplySharedVoicePreferences(@{@"doubao_auth_mode": @"legacy"}, defaults);
        assert([MSIMEVoiceProviderOptions(base, defaults)[@"doubao_auth_mode"] isEqual:@"legacy"]);
        for (id invalid in @[@"", @"unknown", @42, @[]]) {
            [defaults setObject:invalid forKey:@"MSIMEClientVoiceDoubaoAuthMode"];
            assert(!MSIMEVoiceProviderOptions(base, defaults)[@"doubao_auth_mode"]);
        }
        [defaults setObject:@"false" forKey:@"MSIMEClientVoiceDoubaoEnableITN"];
        [defaults setObject:@[] forKey:@"MSIMEClientVoiceDoubaoEnablePunctuation"];
        [defaults setObject:@"false" forKey:@"MSIMEClientVoiceDoubaoEnableDDC"];
        query = MSIMEVoiceProviderOptions(base, defaults);
        assert([query[@"doubao_enable_itn"] isEqual:@YES]);
        assert([query[@"doubao_enable_punc"] isEqual:@YES]);
        assert([query[@"doubao_enable_ddc"] isEqual:@YES]);
        MSIMERemoveTestPreferenceSuite(defaults, suite);
    }
}
