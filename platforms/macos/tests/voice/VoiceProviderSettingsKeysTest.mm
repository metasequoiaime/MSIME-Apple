#import "../../src/voice/VoiceProviderSettings.h"
#import "../../src/voice/VoiceProviderSettingsKeys.h"

#import <objc/runtime.h>

#include <cassert>
#include <cstdio>

// Every text field the window edits has to reach the default the input method reads. The window used to
// write its own dictionary alone, so provider, endpoint, model and model path were stored and then ignored
// by every recording. Ask the runtime what the class actually carries rather than repeating a list here:
// a property added to the window without a shared key fails this.
static void TestEveryEditableFieldHasASharedKey()
{
    NSDictionary<NSString *, NSString *> *keys = MSIMEVoiceProviderSharedKeys();
    unsigned int count = 0;
    objc_property_t *properties = class_copyPropertyList(MetasequoiaVoiceProviderSettings.class, &count);
    NSUInteger strings = 0;
    for (unsigned int index = 0; index < count; ++index) {
        NSString *name = @(property_getName(properties[index]));
        const char *attributes = property_getAttributes(properties[index]);
        // The switch is a BOOL and is saved on its own; everything else the window edits is text.
        if (!strstr(attributes, "T@\"NSString\"")) continue;
        ++strings;
        assert(keys[name].length && "a text field with no shared key never reaches a recording");
    }
    free(properties);
    assert(strings == keys.count);

    NSMutableSet *seen = [NSMutableSet set];
    for (NSString *field in keys) {
        assert([keys[field] hasPrefix:@"MSIMEClientVoice"]);
        // Two fields sharing one default would make the second silently overwrite the first.
        assert(![seen containsObject:keys[field]]);
        [seen addObject:keys[field]];
    }
}

static void TestSharedSettingPrefersTheSharedStoreAndToleratesJunk()
{
    NSDictionary *saved = @{@"provider" : @"groq", @"model" : @"private-model"};

    // The Tauri page writes only the shared default, and it is the primary editor.
    assert([MSIMEVoiceProviderSharedSetting(saved, @"provider", @"openai", @"doubao") isEqual:@"openai"]);
    // A configuration saved by an older build is still honoured rather than dropped on first open.
    assert([MSIMEVoiceProviderSharedSetting(saved, @"provider", nil, @"doubao") isEqual:@"groq"]);
    // An empty shared value is not a choice; it is a default that was never written.
    assert([MSIMEVoiceProviderSharedSetting(saved, @"model", @"", @"fallback") isEqual:@"private-model"]);
    assert([MSIMEVoiceProviderSharedSetting(saved, @"endpoint", nil, @"fallback") isEqual:@"fallback"]);

    // dictionaryForKey: type-checks the container and nothing inside it. A number where a string belongs
    // used to reach -length and take the input method down on the next Control+Option+V, so both the leaf
    // and the container are checked rather than trusted.
    assert([MSIMEVoiceProviderSharedSetting(@{@"provider" : @7}, @"provider", nil, @"doubao") isEqual:@"doubao"]);
    assert([MSIMEVoiceProviderSharedSetting(nil, @"provider", nil, @"doubao") isEqual:@"doubao"]);
    assert([MSIMEVoiceProviderSharedSetting((NSDictionary *)@"not a dictionary", @"provider", nil, @"doubao")
        isEqual:@"doubao"]);
    assert([MSIMEVoiceProviderSharedSetting(saved, @"provider", @7, @"doubao") isEqual:@"groq"]);
}

int main()
{
    @autoreleasepool {
        TestEveryEditableFieldHasASharedKey();
        TestSharedSettingPrefersTheSharedStoreAndToleratesJunk();
    }
    std::puts("macOS voice provider settings keys passed.");
    return 0;
}
