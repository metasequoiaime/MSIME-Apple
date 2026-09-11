// Include the implementation so origin scoping is exercised without accessing a real Keychain.
#import "../VoiceSettings.h"
#include <cstdio>
#include <cstdlib>

namespace
{
void Require(bool value, const char *message)
{
    if (!value)
    {
        std::fprintf(stderr, "%s\n", message);
        std::exit(1);
    }
}
} // namespace
int main()
{
    @autoreleasepool
    {
        MetasequoiaVoiceSettings *settings = [MetasequoiaVoiceSettings new];
        settings.provider = @"cloud";
        settings.endpoint = @"https://example.test/v1/audio/transcriptions";
        settings.model = @"fixture-model";
        settings.token = @"fixture-token";
        settings.modelPath = @"";
        settings.polishEnabled = NO;
        settings.polishEndpoint = @"";
        settings.polishModel = @"";
        settings.polishToken = @"";
        Require([settings validate:nil], "valid cloud configuration rejected");
        for (NSString *invalid in @[
                 @"http://example.test/asr", @"https:///", @"https://user:password@example.test/asr",
                 @"https://example.test/asr#fragment", @"file:///tmp/asr"
             ])
        {
            settings.endpoint = invalid;
            NSError *error = nil;
            Require(![settings validate:&error] && error != nil, "unsafe endpoint accepted");
        }
        settings.endpoint = @"https://example.test/asr";
        settings.token = @"";
        Require(![settings validate:nil], "missing ASR token accepted");
        settings.token = @"fixture-token";
        settings.polishEnabled = YES;
        Require(![settings validate:nil], "incomplete opt-in polish accepted");
        settings.polishEndpoint = @"https://polish.test/v1/chat/completions";
        settings.polishModel = @"fixture-model";
        settings.polishToken = @"fixture-token";
        Require([settings validate:nil], "valid polish rejected");
        settings.polishEnabled = NO;
        settings.provider = @"local";
        settings.token = @"";
        settings.modelPath = @"/nonexistent/msime-whisper-model.bin";
        Require(![settings validate:nil], "missing local model accepted");
        settings.modelPath = NSTemporaryDirectory();
        Require(![settings validate:nil], "directory accepted as model");
        NSString *path = [NSTemporaryDirectory() stringByAppendingPathComponent:NSUUID.UUID.UUIDString];
        Require([@"model fixture" writeToFile:path atomically:YES encoding:NSUTF8StringEncoding error:nil],
                "model fixture creation failed");
        settings.modelPath = path;
        Require([settings validate:nil], "local mode requires unused cloud credentials");
        [[NSFileManager defaultManager] removeItemAtPath:path error:nil];
        settings.provider = @"unknown";
        Require(![settings validate:nil], "unknown provider accepted");

    }
    return 0;
}
