#import "../src/voice/VoiceProviderSocket.h"

#include <stdexcept>

namespace {
void require(bool condition, const char *message) {
    if (!condition) throw std::runtime_error(message);
}
}

int main() {
    @autoreleasepool {
        NSFileManager *files = NSFileManager.defaultManager;
        NSString *root = [NSTemporaryDirectory() stringByAppendingPathComponent:@"msime-voice-provider-socket-test"];
        [files createDirectoryAtPath:root withIntermediateDirectories:YES attributes:nil error:nil];
        NSString *configured = [root stringByAppendingPathComponent:@"configured.sock"];
        NSString *fallback = [root stringByAppendingPathComponent:@"fallback.sock"];
        NSString *optionsPath = [root stringByAppendingPathComponent:@"runtime-options.json"];
        [files createFileAtPath:configured contents:[NSData data] attributes:nil];
        [files createFileAtPath:fallback contents:[NSData data] attributes:nil];
        NSData *options = [NSJSONSerialization dataWithJSONObject:@{ @"voice_provider_socket": configured } options:0 error:nil];
        [options writeToFile:optionsPath atomically:YES];

        require([MSIMEVoiceProviderSocketFromConfiguration(
                    @{ @"voice_provider_socket": configured },
                    @{ @"MSIME_VOICE_PROVIDER_SOCKET": fallback }, files) isEqual:configured],
                "runtime options did not take precedence");
        require([MSIMEVoiceProviderSocketFromConfiguration(
                    @{}, @{ @"MSIME_VOICE_PROVIDER_SOCKET": fallback }, files) isEqual:fallback],
                "environment fallback was not selected");
        require(MSIMEVoiceProviderSocketFromConfiguration(
                    @{ @"voice_provider_socket": @"relative.sock" },
                    @{ @"MSIME_VOICE_PROVIDER_SOCKET": @"relative.sock" }, files) == nil,
                "relative provider path was accepted");
        require(MSIMEVoiceProviderSocketFromConfiguration(
                    @{ @"voice_provider_socket": @"/tmp/missing-msime-voice.sock" },
                    @{}, files) == nil,
                "missing provider path was advertised");
        require([MSIMEVoiceProviderSocketFromOptionsPath(optionsPath, @{}, files) isEqual:configured],
                "explicit host options path was not read");
        [files removeItemAtPath:root error:nil];
    }
    return 0;
}
