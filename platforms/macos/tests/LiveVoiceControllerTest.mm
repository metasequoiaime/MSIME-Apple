#import "../InputController.mm"
#import "VoiceCueFixture.h"
#include <cassert>

@interface LiveCaptureFixture : MSIMEVoiceInputService
@property(copy) void (^transcript)(NSString *, BOOL);
@property NSUInteger captureStops;
@property NSUInteger transcriptionStops;
@property BOOL needsMicrophonePermission;
@property BOOL failCapture;
@property(copy) void (^permission)(BOOL);
@end
@implementation LiveCaptureFixture
- (AVAuthorizationStatus)microphoneAuthorizationStatus { return self.needsMicrophonePermission ? AVAuthorizationStatusNotDetermined : AVAuthorizationStatusAuthorized; }
- (void)requestMicrophonePermission:(void (^)(BOOL))completion { self.permission = completion; }
- (SFSpeechRecognizerAuthorizationStatus)speechAuthorizationStatus { return SFSpeechRecognizerAuthorizationStatusAuthorized; }
- (BOOL)startTranscriptionWithLanguage:(NSString *)language textHandler:(void (^)(NSString *, BOOL))handler error:(NSError **)error {
    (void)language; (void)error; self.transcript = handler; return YES;
}
- (BOOL)startMicrophoneCapture:(MSIMEVoiceAudioBuffer)handler deviceUID:(NSString *)device error:(NSError **)error {
    (void)handler; (void)device; (void)error; return !self.failCapture;
}
- (void)stopMicrophoneCapture { ++self.captureStops; }
- (void)stopTranscription { ++self.transcriptionStops; }
@end
@interface LiveTextFixture : NSObject <MSIMETextClient>
@property(copy) NSString *marked;
@property NSMutableArray *commits;
@end
@implementation LiveTextFixture
- (void)insertText:(id)text replacementRange:(NSRange)range {
    (void)range; if (!self.commits) self.commits = [NSMutableArray array]; [self.commits addObject:text]; self.marked = @"";
}
- (void)setMarkedText:(id)text selectionRange:(NSRange)selection replacementRange:(NSRange)replacement {
    (void)selection; (void)replacement; self.marked = text;
}
@end
@interface LivePresentationFixture : NSObject
- (void)setListening:(BOOL)listening;
- (void)restore;
@end
@implementation LivePresentationFixture
- (void)setListening:(BOOL)listening { (void)listening; }
- (void)restore {}
@end
@interface LiveControllerFixture : MSIMEInputController
@end
@implementation LiveControllerFixture
- (void)ensureAppearance {}
- (void)apply:(NSDictionary *)transition { MSIMEApplyTransition(transition, [self valueForKey:@"activeClient"]); }
@end
@interface LiveHostFixture : MSIMEClientSession
@property(atomic) NSUInteger providerStops;
@property(atomic) NSUInteger providerCancels;
@property(atomic) BOOL providerStarted;
@property(atomic, copy) MSIMEVoiceProviderUpdate providerUpdate;
@property(atomic, copy) MSIMEVoiceProviderPhase providerPhase;
@property dispatch_semaphore_t providerDone;
@end
@implementation LiveHostFixture
- (BOOL)voiceProviderStream:(NSDictionary *)query socket:(NSString *)socket update:(MSIMEVoiceProviderUpdate)update phase:(MSIMEVoiceProviderPhase)phase error:(NSError **)error {
    (void)error;
    assert([socket isEqual:@"/tmp/synthetic-live.sock"] && [query[@"generation"] unsignedLongLongValue]);
    self.providerUpdate = update; self.providerPhase = phase;
    phase(0); phase(0); // Duplicate recording notifications must not replay cues.
    self.providerStarted = YES;
    assert(dispatch_semaphore_wait(self.providerDone, dispatch_time(DISPATCH_TIME_NOW, 5 * NSEC_PER_SEC)) == 0);
    return YES;
}
- (BOOL)voiceProviderStopSocket:(NSString *)socket generation:(uint64_t)generation error:(NSError **)error {
    (void)error; assert([socket isEqual:@"/tmp/synthetic-live.sock"] && generation); self.providerStops += 1; return YES;
}
- (BOOL)voiceProviderCancelSocket:(NSString *)socket generation:(uint64_t)generation error:(NSError **)error {
    (void)error; assert([socket isEqual:@"/tmp/synthetic-live.sock"] && generation); self.providerCancels += 1;
    if (self.providerDone) dispatch_semaphore_signal(self.providerDone);
    return YES;
}
@end
int main(int argc, char **) {
    @autoreleasepool {
        NSString *root = [NSTemporaryDirectory() stringByAppendingPathComponent:NSUUID.UUID.UUIDString];
        NSMutableDictionary *options = [@{@"api_version": @1, @"preferences": @{@"scheme": @"quanpin", @"learning": @NO, @"candidate_page_size": @5, @"chinese_punctuation": @YES}} mutableCopy];
        for (NSString *name in @[@"resources", @"user_data", @"cache", @"dictionaries"]) {
            NSString *path = [root stringByAppendingPathComponent:name];
            assert([NSFileManager.defaultManager createDirectoryAtPath:path withIntermediateDirectories:YES attributes:nil error:nil]); options[name] = path;
        }
        LiveHostFixture *session = [[LiveHostFixture alloc] initWithOptions:options error:nil]; assert(session);
        LiveControllerFixture *controller = [LiveControllerFixture alloc];
        LiveCaptureFixture *capture = [LiveCaptureFixture new];
        LiveTextFixture *client = [LiveTextFixture new];
        LivePresentationFixture *presentation = [LivePresentationFixture new];
        MSIMEVoiceCueFixture *cues = [MSIMEVoiceCueFixture new];
        [controller setValue:session forKey:@"session"]; [controller setValue:client forKey:@"activeClient"];
        [controller setValue:capture forKey:@"voiceService"];
        for (NSString *key in @[@"voiceOverlay", @"voiceAudioMuter"]) [controller setValue:presentation forKey:key];
        [controller setValue:cues forKey:@"voiceCuePlayer"];
        NSUserDefaults *defaults = NSUserDefaults.standardUserDefaults;
        NSDictionary *old = [defaults volatileDomainForName:NSArgumentDomain];
        NSMutableDictionary *voiceArguments = [@{@"MSIMEClientVoiceEnabled": @YES, @"MSIMEClientVoiceASRProvider": @"system", @"MSIMEClientVoiceSoundEnabled": @YES, @"MSIMEClientVoiceStartSound": @YES, @"MSIMEClientVoiceEndSound": @YES, @"MSIMEClientVoiceMuteSystemAudio": @NO, @"MSIMEClientVoiceStreamInlinePreedit": @YES, @"MSIMEClientVoiceHotkeyRightAlt": @YES, @"MSIMEClientVoiceHotkeyHoldSpace": @YES} mutableCopy];
        [defaults setVolatileDomain:voiceArguments forName:NSArgumentDomain];
        if (argc == 2) {
            session.providerDone = dispatch_semaphore_create(0);
            [controller toggleVoiceInput:nil];
            NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:3];
            while (!session.providerStarted && deadline.timeIntervalSinceNow > 0)
                [NSRunLoop.currentRunLoop runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.01]];
            assert(session.providerStarted && !capture.transcript);
            session.providerUpdate(@"socket partial", NO);
            [NSRunLoop.currentRunLoop runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.03]];
            assert(cues.starts == 1 && cues.stops == 0);
            assert([client.marked isEqual:@"socket partial"] && !client.commits.count);
            [controller finishVoiceInputForDisable];
            [controller finishVoiceInputForDisable];
            session.providerPhase(1); session.providerPhase(2); session.providerPhase(0);
            session.providerUpdate(@"socket final", YES);
            while ((capture.active || !session.providerStops || !session.providerCancels) && deadline.timeIntervalSinceNow > 0)
                [NSRunLoop.currentRunLoop runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.01]];
            assert(!capture.active && session.providerStops == 1 && session.providerCancels == 1);
            assert(client.commits.count == 1 && [client.commits[0] isEqual:@"socket final"]);
            assert(cues.starts == 1 && cues.stops == 1);
            [defaults setVolatileDomain:old forName:NSArgumentDomain];
            assert([session closeWithError:nil]); assert([NSFileManager.defaultManager removeItemAtPath:root error:nil]);
            return 0;
        }
        [controller toggleVoiceInput:nil]; assert(capture.active);
        assert(cues.starts == 1 && cues.stops == 0);
        void (^first)(NSString *, BOOL) = capture.transcript;
        first(@"synthetic partial", NO);
        assert(client.commits.count == 0 && [client.marked isEqual:@"synthetic partial"]);
        NSUInteger cancelled = capture.transcriptionStops;
        [controller toggleVoiceInput:nil];
        assert(capture.active && capture.captureStops && capture.transcriptionStops == cancelled);
        first(@"synthetic final", YES);
        assert(!capture.active && client.commits.count == 1 && [client.commits[0] isEqual:@"synthetic final"]);
        first(@"duplicate", YES); assert(client.commits.count == 1);
        assert(cues.starts == 1 && cues.stops == 1);
        [controller toggleVoiceInput:nil];
        first(@"old callback", YES); assert(capture.active && client.commits.count == 1);
        capture.transcript(@"cancelled partial", NO);
        [controller voiceProviderSettingsChanged:nil]; assert(!capture.active && !client.marked.length);
        [controller toggleVoiceInput:nil];
        [controller setValue:[LiveTextFixture new] forKey:@"activeClient"];
        capture.transcript(@"wrong focus", YES); assert(client.commits.count == 1);
        [controller setValue:client forKey:@"activeClient"];
        [controller toggleVoiceInput:nil]; capture.transcript(@"", YES); assert(!capture.active);
        [controller toggleVoiceInput:nil]; [controller toggleVoiceInput:nil]; [controller toggleVoiceInput:nil]; assert(!capture.active);
        uint64_t generation = 0;
        assert([capture startWithSession:session generation:&generation error:nil]);
        [controller setValue:@(generation) forKey:@"voiceGeneration"];
        id token = [controller beginLiveVoiceWithOptions:@{@"stream": @NO} socket:@"/tmp/synthetic-live.sock"];
        [controller applyLiveVoiceText:@"hidden partial" final:NO token:token]; assert(!client.marked.length);
        [controller finishLiveVoiceInput]; assert(capture.active);
        [controller applyLiveVoiceText:@"socket final" final:YES token:token];
        assert(client.commits.count == 2 && [client.commits.lastObject isEqual:@"socket final"]);
        NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:3];
        while ((!session.providerStops || !session.providerCancels) && deadline.timeIntervalSinceNow > 0)
            [NSRunLoop.currentRunLoop runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.01]];
        assert(session.providerStops == 1 && session.providerCancels == 1);
        auto key = [](unsigned short code, NSEventModifierFlags flags, NSEventType type) {
            return [NSEvent keyEventWithType:type location:NSZeroPoint modifierFlags:flags timestamp:1 windowNumber:0 context:nil characters:@"" charactersIgnoringModifiers:@"" isARepeat:NO keyCode:code];
        };
        const auto option = NSEventModifierFlagOption | NX_DEVICERALTKEYMASK;
        assert([controller handleEvent:key(61, option, NSEventTypeFlagsChanged) client:client]);
        assert(capture.active);
        assert([controller handleEvent:key(49, option, NSEventTypeKeyDown) client:client]);
        assert([controller handleEvent:key(61, 0, NSEventTypeFlagsChanged) client:client]);
        assert([controller handleEvent:key(49, 0, NSEventTypeKeyUp) client:client]);
        assert(capture.active && ![[controller valueForKey:@"liveVoiceProcessing"] boolValue]);
        assert([controller handleEvent:key(61, option, NSEventTypeFlagsChanged) client:client]);
        assert([controller handleEvent:key(61, 0, NSEventTypeFlagsChanged) client:client]);
        assert(capture.active && [[controller valueForKey:@"liveVoiceProcessing"] boolValue]);
        capture.transcript(@"locked final", YES);
        assert(!capture.active && client.commits.count == 3 && [client.commits.lastObject isEqual:@"locked final"]);
        assert([controller handleEvent:key(61, option, NSEventTypeFlagsChanged) client:client]);
        [controller cancelLiveVoiceInput];
        [controller toggleVoiceInput:nil]; // A separately started recording owns a new generation.
        assert([controller handleEvent:key(61, 0, NSEventTypeFlagsChanged) client:client]);
        assert(capture.active && ![[controller valueForKey:@"liveVoiceProcessing"] boolValue]);
        [controller cancelLiveVoiceInput];
        capture.needsMicrophonePermission = YES;
        assert([controller handleEvent:key(61, option, NSEventTypeFlagsChanged) client:client]);
        assert(capture.permission && !capture.active);
        assert([controller handleEvent:key(61, 0, NSEventTypeFlagsChanged) client:client]);
        capture.needsMicrophonePermission = NO;
        capture.permission(YES);
        assert(!capture.active);
        // Disabling stops capture but finishes the in-flight recognition, as on
        // Windows. Use volatile preferences so no real settings are written.
        [controller toggleVoiceInput:nil]; assert(capture.active);
        void (^disabledResult)(NSString *, BOOL) = capture.transcript;
        disabledResult(@"synthetic disabled partial", NO);
        voiceArguments[@"MSIMEClientVoiceEnabled"] = @NO;
        [defaults setVolatileDomain:voiceArguments forName:NSArgumentDomain];
        [NSApplication sharedApplication];
        [controller applySharedToolbarPreferences:@{}];
        assert(capture.active && [[controller valueForKey:@"liveVoiceProcessing"] boolValue]);
        const auto disabledCaptureStops = capture.captureStops;
        [controller applySharedToolbarPreferences:@{}];
        [controller toggleVoiceInput:nil];
        assert(capture.active && capture.captureStops == disabledCaptureStops);
        disabledResult(@"synthetic disabled final", YES);
        disabledResult(@"synthetic duplicate disabled final", YES);
        assert(!capture.active && !client.marked.length && client.commits.count == 4);
        [controller toggleVoiceInput:nil]; assert(!capture.active);
        assert(![controller handleEvent:key(61, option, NSEventTypeFlagsChanged) client:client]);
        assert(![controller handleEvent:key(61, 0, NSEventTypeFlagsChanged) client:client]);
        assert(![controller handleEvent:key(101, NSEventModifierFlagControl, NSEventTypeKeyDown) client:client]);
        assert(!capture.active);
        voiceArguments[@"MSIMEClientVoiceEnabled"] = @YES;
        [defaults setVolatileDomain:voiceArguments forName:NSArgumentDomain];
        // A previously requested permission must not override a later disable.
        capture.needsMicrophonePermission = YES;
        capture.permission = nil;
        [controller toggleVoiceInput:nil]; assert(capture.permission);
        voiceArguments[@"MSIMEClientVoiceEnabled"] = @NO;
        [defaults setVolatileDomain:voiceArguments forName:NSArgumentDomain];
        capture.needsMicrophonePermission = NO;
        capture.permission(YES); assert(!capture.active);
        voiceArguments[@"MSIMEClientVoiceEnabled"] = @YES;
        [defaults setVolatileDomain:voiceArguments forName:NSArgumentDomain];
        [controller setValue:nil forKey:@"activeClient"];
        [controller toggleVoiceInput:nil]; assert(!capture.active);
        [controller setValue:client forKey:@"activeClient"];
        assert([controller handleEvent:key(61, option, NSEventTypeFlagsChanged) client:client]);
        assert(capture.active);
        [controller cancelLiveVoiceInput];
        assert([controller handleEvent:key(61, 0, NSEventTypeFlagsChanged) client:client]);
        voiceArguments[@"MSIMEClientVoiceHotkeyRightAlt"] = @NO;
        voiceArguments[@"MSIMEClientVoiceHotkeyCtrlOption"] = @YES;
        [defaults setVolatileDomain:voiceArguments forName:NSArgumentDomain];
        const auto rightControl = NSEventModifierFlagControl | NX_DEVICERCTLKEYMASK;
        assert(![controller handleEvent:key(62, rightControl, NSEventTypeFlagsChanged) client:client]);
        assert([controller handleEvent:key(61, rightControl | option, NSEventTypeFlagsChanged) client:client]);
        assert(capture.active);
        [controller cancelLiveVoiceInput];
        const auto failureStarts = cues.starts, failureStops = cues.stops;
        capture.failCapture = YES;
        [controller toggleVoiceInput:nil];
        assert(!capture.active && cues.starts == failureStarts && cues.stops == failureStops);
        capture.failCapture = NO;
        // Exercise all shared sound switches at the actual capture entry/exit.
        for (NSNumber *master in @[@NO, @YES]) for (NSNumber *start in @[@NO, @YES]) for (NSNumber *end in @[@NO, @YES]) {
            voiceArguments[@"MSIMEClientVoiceSoundEnabled"] = master;
            voiceArguments[@"MSIMEClientVoiceStartSound"] = start;
            voiceArguments[@"MSIMEClientVoiceEndSound"] = end;
            [defaults setVolatileDomain:voiceArguments forName:NSArgumentDomain];
            const auto starts = cues.starts, stops = cues.stops;
            [controller toggleVoiceInput:nil]; assert(capture.active);
            [controller cancelLiveVoiceInput]; [controller cancelLiveVoiceInput];
            assert(cues.starts == starts + (master.boolValue && start.boolValue));
            assert(cues.stops == stops + (master.boolValue && end.boolValue));
        }
        [defaults setVolatileDomain:old forName:NSArgumentDomain];
        assert([session closeWithError:nil]); assert([NSFileManager.defaultManager removeItemAtPath:root error:nil]);
    }
}
