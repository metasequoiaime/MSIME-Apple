#import "../../src/voice/HTTPVoiceRequest.h"
#include "../../../../shared/voice/VoiceProviders.h"
#include <cassert>

static void Wait(BOOL (^done)(void)) {
    // Room for the deliberately slow fixture responses; the loop leaves as soon as the work is done.
    NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:20];
    while (!done() && deadline.timeIntervalSinceNow > 0)
        [NSRunLoop.currentRunLoop runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.001]];
    assert(done());
}
int main(int argc, char **argv) {
    @autoreleasepool {
        assert(argc == 2);
        NSString *base = @(argv[1]);
        NSMutableString *model = [@"fixture-model" mutableCopy];
        NSMutableDictionary *options = [@{@"asr_provider": @"openai", @"asr_model": model,
            @"asr_endpoint": [base stringByAppendingString:@"/asr"], @"asr_token": @"fixture-token",
            @"language": @"en-us", @"polish_enabled": @YES, @"polish_provider": @"openai",
            @"polish_endpoint": [base stringByAppendingString:@"/polish"], @"polish_model": @"fixture-model",
            @"polish_token": @"fixture-token", @"polish_prompt_id": @"custom_2",
            @"polish_prompt_custom_2": @"synthetic prompt"} mutableCopy];
        MSIMEHTTPVoiceRequest *request = [[MSIMEHTTPVoiceRequest alloc] initWithOptions:options error:nil];
        assert(request);
        [model setString:@"changed-after-snapshot"];
        options[@"asr_token"] = @"changed-after-snapshot";
        float samples[160] = {};
        NSMutableData *pcm = [NSMutableData dataWithBytes:samples length:sizeof(samples)];
        __block BOOL done = NO;
        __block NSUInteger polishing = 0;
        request.polishingHandler = ^{ assert(NSThread.isMainThread && !done); ++polishing; };
        assert([request recognizePCM:pcm completion:^(NSString *text, NSError *error) {
            assert(NSThread.isMainThread && !error && [text isEqual:@"synthetic polished"]); done = YES;
        } error:nil]);
        request.polishingHandler = ^{ assert(false && "phase handler must be frozen at start"); };
        [pcm setLength:0];
        Wait(^BOOL { return done; });
        assert(polishing == 1);
        assert(![request recognizePCM:pcm completion:^(NSString *, NSError *) {} error:nil]);
        options[@"asr_model"] = @"fixture-model"; options[@"asr_token"] = @"fixture-token";
        options[@"polish_endpoint"] = [base stringByAppendingString:@"/polish-failure"];
        request = [[MSIMEHTTPVoiceRequest alloc] initWithOptions:options error:nil];
        done = NO;
        NSData *valid = [NSData dataWithBytes:samples length:sizeof(samples)];
        assert([request recognizePCM:valid completion:^(NSString *text, NSError *error) {
            assert(!error && [text isEqual:@"synthetic transcript"]); done = YES;
        } error:nil]);
        Wait(^BOOL { return done; });
        // Polish sits in the same path as the transcript, so a slow service delays the text itself. Six
        // seconds is inside the budget this host asks for and the cleaned answer is used: the alternative
        // is sending the transcript to the provider and binning the reply, which is what a budget the
        // service cannot meet amounts to. The reference host makes the same trade.
        options[@"polish_endpoint"] = [base stringByAppendingString:@"/polish-timeout"];
        request = [[MSIMEHTTPVoiceRequest alloc] initWithOptions:options error:nil];
        done = NO;
        const NSTimeInterval started = NSProcessInfo.processInfo.systemUptime;
        assert([request recognizePCM:valid completion:^(NSString *text, NSError *error) {
            assert(NSThread.isMainThread && !error && [text isEqual:@"synthetic polished"]); done = YES;
        } error:nil]);
        Wait(^BOOL { return done; });
        const NSTimeInterval elapsed = NSProcessInfo.processInfo.systemUptime - started;
        assert(elapsed >= 5.5);
        // A recording past the old 60 s cut is uploaded, and one past the batch budget is sent up to it rather than refused: MSIME-Windows caps a batch upload at 20 MiB of 16-bit WAV, not at a duration.
        NSMutableDictionary *longOptions = [options mutableCopy];
        longOptions[@"asr_endpoint"] = [base stringByAppendingString:@"/asr-long"];
        longOptions[@"polish_enabled"] = @NO;
        request = [[MSIMEHTTPVoiceRequest alloc] initWithOptions:longOptions error:nil];
        assert(request.sampleLimit == msime::voice::batch_capture_sample_limit); // The host ends the recording here.
        NSMutableData *longPCM = [NSMutableData dataWithLength:(msime::voice::batch_capture_sample_limit + 16000) * sizeof(float)];
        __block NSString *longText = nil;
        assert([request recognizePCM:longPCM completion:^(NSString *text, NSError *error) {
            assert(!error); longText = text;
        } error:nil]);
        Wait(^BOOL { return longText != nil; });
        NSString *longExpected = [NSString stringWithFormat:@"synthetic long %zu", msime::voice::batch_capture_sample_limit];
        assert([longText isEqual:longExpected]);
        // A rejected request shows the provider's own message, as MSIME-Windows does, and a SiliconFlow 5xx its trace id; the generic description stays for anything that reads only that.
        NSMutableDictionary *deniedOptions = [longOptions mutableCopy];
        deniedOptions[@"asr_endpoint"] = [base stringByAppendingString:@"/asr-denied"];
        NSMutableDictionary *traceOptions = [longOptions mutableCopy];
        traceOptions[@"asr_provider"] = @"siliconflow";
        traceOptions[@"asr_endpoint"] = [base stringByAppendingString:@"/asr-trace"];
        for (NSArray *expectation in @[
            @[deniedOptions, @"语音识别失败：Incorrect synthetic key"],
            @[traceOptions, @"语音识别失败：HTTP 500。这是硅基流动服务端内部错误，模型名 fixture-model 本身是官方支持的。 追踪 ID：synthetic-trace。"]]) {
            request = [[MSIMEHTTPVoiceRequest alloc] initWithOptions:expectation[0] error:nil];
            __block NSError *rejection = nil;
            assert([request recognizePCM:valid completion:^(NSString *text, NSError *error) {
                assert(!text && error); rejection = error;
            } error:nil]);
            Wait(^BOOL { return rejection != nil; });
            assert([rejection.userInfo[NSLocalizedFailureReasonErrorKey] isEqual:expectation[1]]);
            assert([rejection.localizedDescription isEqual:@"语音请求失败，请检查识别服务设置"]);
            assert(![rejection.userInfo.description containsString:@"fixture-token"]);
        }
        request = [[MSIMEHTTPVoiceRequest alloc] initWithOptions:options error:nil];
        [request cancel];
        assert(![request recognizePCM:valid completion:^(NSString *, NSError *) { assert(false); } error:nil]);
        options[@"asr_endpoint"] = @"http://example.invalid/asr";
        assert(![[MSIMEHTTPVoiceRequest alloc] initWithOptions:options error:nil]);
        options[@"asr_endpoint"] = [base stringByAppendingString:@"/asr"];
        options[@"asr_token"] = @"invalid\nheader";
        assert(![[MSIMEHTTPVoiceRequest alloc] initWithOptions:options error:nil]);
        options[@"asr_token"] = @"fixture-token"; options[@"asr_provider"] = @"doubao";
        assert(![[MSIMEHTTPVoiceRequest alloc] initWithOptions:options error:nil]);

        // The on-device provider is accepted on its model file alone: no endpoint, no token. What it must
        // not accept is a model that is missing, a directory, or a relative path, because each of those
        // fails only once the user is holding the shortcut and waiting for text.
        NSMutableDictionary *local = [@{@"asr_provider": @"local", @"language": @"zh-cn"} mutableCopy];
        NSString *directory = [NSTemporaryDirectory() stringByAppendingPathComponent:NSUUID.UUID.UUIDString];
        assert([NSFileManager.defaultManager createDirectoryAtPath:directory withIntermediateDirectories:YES
                                                        attributes:nil error:nil]);
        NSString *file = [directory stringByAppendingPathComponent:@"ggml-model.bin"];
        assert([NSFileManager.defaultManager createFileAtPath:file contents:NSData.data attributes:nil]);
        for (NSString *rejected in @[@"", @"ggml-model.bin", directory,
                                     [directory stringByAppendingPathComponent:@"absent.bin"]]) {
            local[@"asr_model_path"] = rejected;
            assert(![[MSIMEHTTPVoiceRequest alloc] initWithOptions:local error:nil]);
        }
        local[@"asr_model_path"] = file;
        MSIMEHTTPVoiceRequest *localRequest = [[MSIMEHTTPVoiceRequest alloc] initWithOptions:local error:nil];
        // A build without the recognizer must refuse the provider rather than quietly recognising elsewhere.
        assert((localRequest != nil) == msime::voice::local_asr_available());
        assert(!localRequest || localRequest.sampleLimit == msime::voice::local_asr_sample_limit);
        assert([NSFileManager.defaultManager removeItemAtPath:directory error:nil]);
    }
}
