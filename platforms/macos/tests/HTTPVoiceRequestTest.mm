#import "../HTTPVoiceRequest.h"
#include <cassert>

static void Wait(BOOL (^done)(void)) {
    NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:8];
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
        // Optional polish must not hold an already recognized transcript for 30s.
        options[@"polish_endpoint"] = [base stringByAppendingString:@"/polish-timeout"];
        request = [[MSIMEHTTPVoiceRequest alloc] initWithOptions:options error:nil];
        done = NO;
        const NSTimeInterval started = NSProcessInfo.processInfo.systemUptime;
        assert([request recognizePCM:valid completion:^(NSString *text, NSError *error) {
            assert(NSThread.isMainThread && !error && [text isEqual:@"synthetic transcript"]); done = YES;
        } error:nil]);
        Wait(^BOOL { return done; });
        const NSTimeInterval elapsed = NSProcessInfo.processInfo.systemUptime - started;
        assert(elapsed >= 2.5 && elapsed < 5);
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
    }
}
