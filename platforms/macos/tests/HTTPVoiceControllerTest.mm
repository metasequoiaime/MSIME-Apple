#import "../InputController.mm"
#import "VoiceCueFixture.h"
#import "VoiceMeterFixture.h"
#include <cassert>

@interface HTTPRequestFixture : NSObject
@property(copy) void (^polishingHandler)(void);
@property(copy) void (^completion)(NSString *, NSError *);
@property NSUInteger cancellations;
@property BOOL submitted;
- (BOOL)recognizePCM:(NSData *)pcm completion:(void (^)(NSString *, NSError *))completion error:(NSError **)error;
- (void)cancel;
@end
@implementation HTTPRequestFixture
- (BOOL)recognizePCM:(NSData *)pcm completion:(void (^)(NSString *, NSError *))completion error:(NSError **)error {
    (void)error; assert(pcm.length == 640); self.submitted = YES; self.completion = completion; return YES;
}
- (void)cancel { ++self.cancellations; }
@end
@interface HTTPCaptureFixture : NSObject
@property(copy) MSIMEVoiceAudioBuffer bufferHandler;
@property NSTimeInterval capturedSeconds;
@property(getter=isActive) BOOL active;
@property BOOL failStart;
@property NSUInteger cancellations;
@property(copy) void (^failure)(NSError *);
- (BOOL)startPCMRecording:(MSIMEVoiceAudioBuffer)handler deviceUID:(NSString *)device failure:(void (^)(NSError *))failure error:(NSError **)error;
- (NSData *)finishPCMRecordingWithError:(NSError **)error;
- (BOOL)cancelWithError:(NSError **)error;
@end
@implementation HTTPCaptureFixture
- (NSTimeInterval)recordedDuration { return self.capturedSeconds; }
- (BOOL)startPCMRecording:(MSIMEVoiceAudioBuffer)handler deviceUID:(NSString *)device failure:(void (^)(NSError *))failure error:(NSError **)error {
    (void)device; (void)error; self.bufferHandler = handler; self.failure = failure; self.active = !self.failStart; return self.active;
}
- (NSData *)finishPCMRecordingWithError:(NSError **)error { (void)error; return [NSMutableData dataWithLength:640]; }
- (BOOL)cancelWithError:(NSError **)error { (void)error; self.active = NO; ++self.cancellations; return YES; }
@end
@interface HTTPHostFixture : NSObject
@property NSUInteger submissions;
- (NSDictionary *)applyVoiceText:(NSString *)text generation:(uint64_t)generation error:(NSError **)error;
@end
@implementation HTTPHostFixture
- (NSDictionary *)applyVoiceText:(NSString *)text generation:(uint64_t)generation error:(NSError **)error {
    (void)error; assert(NSThread.isMainThread && generation == 42 && [text isEqual:@"synthetic"]);
    ++self.submissions; return @{@"commit": text};
}
@end
@interface HTTPControllerFixture : MSIMEInputController
@property HTTPRequestFixture *requestFixture;
@property NSUInteger applies;
@property NSUInteger imkCommits;
@property NSUInteger externalCommits;
@property MSIMEVoiceCommitOutcome commitOutcome;
@property(copy) NSString *commitMode;
@end
@implementation HTTPControllerFixture
- (MSIMEHTTPVoiceRequest *)makeHTTPVoiceRequest:(NSDictionary *)options error:(NSError **)error {
    (void)options; (void)error; self.requestFixture = [HTTPRequestFixture new]; return (id)self.requestFixture;
}
- (void)apply:(NSDictionary *)result { if (result[@"commit"]) ++self.imkCommits; ++self.applies; }
- (MSIMEVoiceCommitOutcome)postVoiceText:(NSString *)text route:(const MSIMEVoiceCommitRoute &)route {
    assert([text isEqual:@"synthetic"]); self.commitMode = route.mode;
    ++self.externalCommits; return self.commitOutcome;
}
@end

@interface HTTPOverlayFixture : NSObject
@property float lastLevel;
@property NSUInteger levelUpdates;
@property(copy) void (^actionHandler)(BOOL);
@property BOOL dismissed;
@property NSUInteger phase;
@property NSUInteger failure;
@property NSUInteger failures;
@end
@implementation HTTPOverlayFixture
- (void)setInputLevel:(float)level { self.lastLevel = level; ++self.levelUpdates; }
- (void)dismissProcessing { self.dismissed = YES; }
- (void)setListening:(BOOL)listening { self.phase = listening ? 1 : 0; self.failure = 0; }
- (void)showFailure:(MSIMEVoiceFailure)failure { self.failure = failure; self.phase = 4; ++self.failures; }
- (void)dismissFailure { if (self.failure) [self setListening:NO]; }
- (void)setProcessing:(BOOL)polishing { self.phase = polishing ? 3 : 2; }
@end

int main() {
    @autoreleasepool {
        HTTPControllerFixture *controller = [HTTPControllerFixture alloc];
        HTTPOverlayFixture *overlay = [HTTPOverlayFixture new];
        [controller setValue:overlay forKey:@"voiceOverlay"];
        MSIMEVoiceCueFixture *cues = [MSIMEVoiceCueFixture new];
        [controller setValue:cues forKey:@"voiceCuePlayer"];
        NSUserDefaults *defaults = NSUserDefaults.standardUserDefaults;
        NSDictionary *oldArguments = [defaults volatileDomainForName:NSArgumentDomain];
        [defaults setVolatileDomain:@{@"MSIMEClientVoiceSoundEnabled": @YES, @"MSIMEClientVoiceStartSound": @YES, @"MSIMEClientVoiceEndSound": @YES} forName:NSArgumentDomain];
        HTTPCaptureFixture *capture = [HTTPCaptureFixture new];
        capture.capturedSeconds = 0.25;
        HTTPHostFixture *session = [HTTPHostFixture new];
        NSObject *client = [NSObject new];
        [controller setValue:capture forKey:@"voiceService"];
        [controller setValue:session forKey:@"session"];
        [controller setValue:client forKey:@"activeClient"];
        [controller setValue:@42 forKey:@"voiceGeneration"];
        assert([controller startHTTPVoiceInputWithOptions:@{}]);
        assert(cues.starts == 1 && cues.stops == 0);
        MSIMEVoiceAudioBuffer oldMeter = capture.bufferHandler;
        oldMeter(MSIMEVoiceMeterFixtureBuffer()); MSIMEVoiceMeterFixturePump();
        assert(overlay.lastLevel > 0.5f && overlay.lastLevel < 0.7f && overlay.levelUpdates == 1);
        for (NSString *field in @[@"activeClient", @"session", @"voiceGeneration"]) {
            id original = [controller valueForKey:field];
            [controller setValue:[field isEqual:@"voiceGeneration"] ? @43 : [NSObject new] forKey:field];
            oldMeter(MSIMEVoiceMeterFixtureBuffer()); MSIMEVoiceMeterFixturePump();
            assert(overlay.levelUpdates == 1);
            [controller setValue:original forKey:field];
        }
        [controller finishVoiceInputForDisable];
        oldMeter(MSIMEVoiceMeterFixtureBuffer()); MSIMEVoiceMeterFixturePump();
        assert(overlay.levelUpdates == 1); // A queued meter cannot change processing presentation.
        [controller finishVoiceInputForDisable];
        assert(controller.requestFixture.submitted && !controller.requestFixture.cancellations);
        assert(overlay.phase == 2);
        controller.requestFixture.polishingHandler();
        assert(overlay.phase == 3);
        controller.requestFixture.completion(@"synthetic", nil);
        controller.requestFixture.completion = nil;
        assert(session.submissions == 1 && controller.applies == 1 && !capture.active);
        controller.requestFixture.polishingHandler();
        assert(overlay.phase == 0);
        assert(cues.starts == 1 && cues.stops == 1);
        // Exercise all controller identity checks with deliberately late results.
        for (NSString *field in @[@"activeClient", @"session", @"voiceGeneration"]) {
            assert([controller startHTTPVoiceInputWithOptions:@{}]);
            [controller finishHTTPVoiceInput];
            id original = [controller valueForKey:field];
            [controller setValue:[field isEqual:@"voiceGeneration"] ? @43 : [NSObject new] forKey:field];
            capture.bufferHandler(MSIMEVoiceMeterFixtureBuffer()); MSIMEVoiceMeterFixturePump();
            assert(overlay.levelUpdates == 1);
            controller.requestFixture.polishingHandler();
            assert(overlay.phase == 2);
            controller.requestFixture.completion(@"synthetic", nil);
            controller.requestFixture.completion = nil;
            [controller setValue:original forKey:field];
            assert(session.submissions == 1 && controller.applies == 1);
        }
        assert([controller startHTTPVoiceInputWithOptions:@{}]);
        [controller finishHTTPVoiceInput];
        HTTPRequestFixture *old = controller.requestFixture;
        [controller finishHTTPVoiceInput]; // A second stop while processing cancels.
        assert(old.cancellations == 1);
        assert([controller startHTTPVoiceInputWithOptions:@{}]);
        old.completion(@"synthetic", nil); old.completion = nil;
        old.polishingHandler();
        assert(overlay.phase == 0);
        assert(capture.active && controller.requestFixture.cancellations == 0);
        [controller cancelHTTPVoiceInput];
        capture.failStart = YES;
        const auto beforeFailure = cues.starts;
        assert(![controller startHTTPVoiceInputWithOptions:@{}]);
        assert(overlay.failure == MSIMEVoiceFailureCapture);
        assert(cues.starts == beforeFailure && cues.stops == beforeFailure);
        assert(controller.requestFixture.cancellations == 1);
        capture.failStart = NO;
        assert([controller startHTTPVoiceInputWithOptions:@{}]);
        void (^oldFailure)(NSError *) = capture.failure;
        oldFailure([NSError errorWithDomain:@"synthetic" code:1 userInfo:nil]);
        assert(!capture.active && controller.requestFixture.cancellations == 1 && !controller.requestFixture.submitted);
        assert(overlay.failure == MSIMEVoiceFailureCapture);
        assert([controller startHTTPVoiceInputWithOptions:@{}]);
        oldFailure([NSError errorWithDomain:@"synthetic" code:1 userInfo:nil]);
        assert(capture.active && controller.requestFixture.cancellations == 0);
        [controller cancelHTTPVoiceInput];
        assert(cues.starts == cues.stops);
        const NSUInteger beforeErrors = overlay.failures;
        assert([controller startHTTPVoiceInputWithOptions:@{}]);
        [controller finishHTTPVoiceInput];
        controller.requestFixture.completion(nil, [NSError errorWithDomain:@"synthetic" code:1
            userInfo:@{NSLocalizedDescriptionKey:@"synthetic detail must not be presented"}]);
        assert(overlay.failure == MSIMEVoiceFailureProvider && overlay.failures == beforeErrors + 1 && !capture.active);
        controller.requestFixture.completion(nil, nil);
        assert(overlay.failures == beforeErrors + 1);
        assert([controller startHTTPVoiceInputWithOptions:@{}]);
        [controller finishHTTPVoiceInput];
        controller.requestFixture.completion(@"", nil);
        assert(overlay.failure == MSIMEVoiceFailureNoSpeech && !capture.active);
        assert([controller startHTTPVoiceInputWithOptions:@{}]);
        [controller finishHTTPVoiceInput];
        [controller setValue:[NSObject new] forKey:@"activeClient"];
        const NSUInteger beforeStale = overlay.failures;
        controller.requestFixture.completion(nil, [NSError errorWithDomain:@"synthetic" code:1 userInfo:nil]);
        assert(overlay.failures == beforeStale && !capture.active);
        [controller setValue:client forKey:@"activeClient"];
        // Overlay confirmation stops capture once, then only dismisses processing.
        assert([controller startHTTPVoiceInputWithOptions:@{}]);
        void (^oldAction)(BOOL) = overlay.actionHandler;
        overlay.actionHandler(NO);
        assert(controller.requestFixture.submitted && !controller.requestFixture.cancellations);
        overlay.actionHandler(NO);
        assert(overlay.dismissed && capture.active && !controller.requestFixture.cancellations);
        NSUInteger beforeConfirm = session.submissions;
        controller.requestFixture.completion(@"synthetic", nil);
        assert(session.submissions == beforeConfirm + 1 && !capture.active);
        assert([controller startHTTPVoiceInputWithOptions:@{}]);
        oldAction(YES); oldAction(NO);
        assert(capture.active && !controller.requestFixture.submitted && !controller.requestFixture.cancellations);
        // Focus, session and generation mismatches make both buttons inert.
        for (NSString *field in @[@"activeClient", @"session", @"voiceGeneration"]) {
            id original = [controller valueForKey:field];
            [controller setValue:[field isEqual:@"voiceGeneration"] ? @43 : [NSObject new] forKey:field];
            overlay.actionHandler(YES); overlay.actionHandler(NO);
            assert(capture.active && !controller.requestFixture.submitted);
            [controller setValue:original forKey:field];
        }
        overlay.actionHandler(NO);
        HTTPRequestFixture *cancelled = controller.requestFixture;
        overlay.actionHandler(YES);
        cancelled.completion(@"synthetic", nil); cancelled.completion = nil;
        assert(!capture.active && session.submissions == beforeConfirm + 1);
        const NSUInteger beforeShort = session.submissions, beforeShortFailures = overlay.failures;
        for (NSNumber *duration in @[@0, @0.2499375]) {
            capture.capturedSeconds = duration.doubleValue;
            assert([controller startHTTPVoiceInputWithOptions:@{}]);
            overlay.actionHandler(NO);
            assert(!capture.active && !controller.requestFixture.submitted && controller.requestFixture.cancellations == 1);
            assert(session.submissions == beforeShort && overlay.failures == beforeShortFailures);
        }
        capture.capturedSeconds = 0.25;
        assert([controller startHTTPVoiceInputWithOptions:@{}]);
        [controller finishHTTPVoiceInput]; assert(controller.requestFixture.submitted);
        controller.requestFixture.completion(@"synthetic", nil);
        assert(session.submissions == beforeShort + 1 && cues.starts == cues.stops);
        for (NSString *mode in @[@"sendinput", @"ctrl_v"]) {
            for (auto outcome : {MSIMEVoiceCommitOutcome::posted, MSIMEVoiceCommitOutcome::unavailable, MSIMEVoiceCommitOutcome::stale}) {
                controller.commitOutcome = outcome;
                const NSUInteger external = controller.externalCommits, imk = controller.imkCommits;
                NSMutableDictionary *options = [@{@"commit_mode": mode} mutableCopy];
                assert([controller startHTTPVoiceInputWithOptions:options]);
                options[@"commit_mode"] = @"tsf";
                [controller finishHTTPVoiceInput];
                controller.requestFixture.completion(@"synthetic", nil);
                controller.requestFixture.completion(@"synthetic", nil);
                assert(controller.externalCommits == external + 1 && [controller.commitMode isEqual:mode]);
                assert(controller.imkCommits == imk + (outcome == MSIMEVoiceCommitOutcome::unavailable ? 1 : 0));
            }
        }
        [defaults setVolatileDomain:oldArguments forName:NSArgumentDomain];
    }
}
