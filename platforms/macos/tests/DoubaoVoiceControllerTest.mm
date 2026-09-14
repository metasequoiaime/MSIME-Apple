#import "../InputController.mm"
#include <cassert>

@interface DoubaoRequestFixture : NSObject
@property(copy) MSIMEDoubaoResult result;
@property NSMutableData *audio;
@property NSUInteger finishes;
@property NSUInteger cancellations;
@property BOOL failStart;
@property BOOL failAppend;
- (BOOL)startWithResult:(MSIMEDoubaoResult)result error:(NSError **)error;
- (BOOL)appendPCM:(NSData *)pcm error:(NSError **)error;
- (BOOL)finishWithError:(NSError **)error;
- (void)cancel;
@end
@implementation DoubaoRequestFixture
- (BOOL)startWithResult:(MSIMEDoubaoResult)result error:(NSError **)error {
    (void)error; self.result = result; self.audio = [NSMutableData data]; return !self.failStart;
}
- (BOOL)appendPCM:(NSData *)pcm error:(NSError **)error {
    (void)error; if (self.failAppend) return NO; [self.audio appendData:pcm]; return YES;
}
- (BOOL)finishWithError:(NSError **)error { (void)error; ++self.finishes; return YES; }
- (void)cancel { ++self.cancellations; }
@end

@interface DoubaoCaptureFixture : MSIMEVoiceInputService
@property(copy) MSIMEVoicePCMChunk chunk;
@property BOOL failStart;
@property NSUInteger finishes;
@end
@implementation DoubaoCaptureFixture
- (AVAuthorizationStatus)microphoneAuthorizationStatus { return AVAuthorizationStatusAuthorized; }
- (SFSpeechRecognizerAuthorizationStatus)speechAuthorizationStatus { assert(false && "Doubao must not request Speech permission"); return SFSpeechRecognizerAuthorizationStatusDenied; }
- (BOOL)startPCMStreaming:(MSIMEVoicePCMChunk)handler deviceUID:(NSString *)device error:(NSError **)error {
    (void)device; (void)error; self.chunk = handler; return !self.failStart;
}
- (NSData *)finishPCMStreamingWithError:(NSError **)error {
    (void)error; ++self.finishes; return [NSMutableData dataWithLength:16];
}
@end

@interface DoubaoPresentationFixture : NSObject
- (void)setListening:(BOOL)listening;
- (void)setInputLevel:(float)level;
- (void)restore;
- (void)playStartCue;
@end
@implementation DoubaoPresentationFixture
- (void)setListening:(BOOL)listening { (void)listening; }
- (void)setInputLevel:(float)level { (void)level; }
- (void)restore {}
- (void)playStartCue {}
@end

@interface DoubaoTextFixture : NSObject <MSIMETextClient>
@property(copy) NSString *marked;
@property NSMutableArray *commits;
@end
@implementation DoubaoTextFixture
- (void)insertText:(id)text replacementRange:(NSRange)range {
    (void)range; if (!self.commits) self.commits = [NSMutableArray array]; [self.commits addObject:text]; self.marked = @"";
}
- (void)setMarkedText:(id)text selectionRange:(NSRange)selection replacementRange:(NSRange)replacement {
    (void)selection; (void)replacement; self.marked = text;
}
@end

@interface DoubaoPolishFixture : NSObject
@property(copy) void (^completion)(NSString *, NSError *);
@property NSUInteger submissions;
@property NSUInteger cancellations;
- (BOOL)polishText:(NSString *)text completion:(void (^)(NSString *, NSError *))completion error:(NSError **)error;
- (void)cancel;
@end
@implementation DoubaoPolishFixture
- (BOOL)polishText:(NSString *)text completion:(void (^)(NSString *, NSError *))completion error:(NSError **)error {
    (void)text; (void)error; ++self.submissions; self.completion = completion; return YES;
}
- (void)cancel { ++self.cancellations; }
@end

@interface DoubaoControllerFixture : MSIMEInputController
@property DoubaoRequestFixture *fixture;
@property BOOL failRequest;
@property BOOL usePolishFixture;
@property DoubaoPolishFixture *polishFixture;
@end
@implementation DoubaoControllerFixture
- (MSIMEHTTPVoiceRequest *)makeDoubaoPolishRequest:(NSDictionary *)options {
    if (!self.usePolishFixture) return [super makeDoubaoPolishRequest:options];
    self.polishFixture = [DoubaoPolishFixture new]; return (id)self.polishFixture;
}
- (MSIMEDoubaoVoiceRequest *)makeDoubaoVoiceRequest:(NSDictionary *)options error:(NSError **)error {
    (void)options; (void)error; self.fixture = [DoubaoRequestFixture new]; self.fixture.failStart = self.failRequest; return (id)self.fixture;
}
- (void)apply:(NSDictionary *)transition {
    MSIMEApplyTransition(transition, [self valueForKey:@"activeClient"]);
}
@end

static BOOL Start(DoubaoControllerFixture *controller, DoubaoCaptureFixture *capture, MSIMEClientSession *session, BOOL stream) {
    uint64_t generation = 0;
    assert([capture startWithSession:session generation:&generation error:nil] && generation);
    [controller setValue:@(generation) forKey:@"voiceGeneration"];
    return [controller startDoubaoVoiceInputWithOptions:@{@"stream": @(stream)}];
}
static void Pump(void) {
    [NSRunLoop.currentRunLoop runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.03]];
}

int main() {
    @autoreleasepool {
        NSString *root = [NSTemporaryDirectory() stringByAppendingPathComponent:NSUUID.UUID.UUIDString];
        NSMutableDictionary *options = [@{@"api_version": @1, @"preferences": @{@"scheme": @"quanpin", @"learning": @NO, @"candidate_page_size": @5, @"chinese_punctuation": @YES}} mutableCopy];
        for (NSString *name in @[@"resources", @"user_data", @"cache", @"dictionaries"]) {
            NSString *path = [root stringByAppendingPathComponent:name];
            assert([NSFileManager.defaultManager createDirectoryAtPath:path withIntermediateDirectories:YES attributes:nil error:nil]);
            options[name] = path;
        }
        MSIMEClientSession *session = [[MSIMEClientSession alloc] initWithOptions:options error:nil];
        assert(session);
        DoubaoControllerFixture *controller = [DoubaoControllerFixture alloc];
        DoubaoCaptureFixture *capture = [DoubaoCaptureFixture new];
        DoubaoTextFixture *client = [DoubaoTextFixture new];
        [controller setValue:session forKey:@"session"];
        [controller setValue:capture forKey:@"voiceService"];
        [controller setValue:client forKey:@"activeClient"];
        assert(Start(controller, capture, session, YES));
        DoubaoRequestFixture *request = controller.fixture;
        request.result(@"synthetic partial", NO, nil);
        assert([client.marked isEqual:@"synthetic partial"] && client.commits.count == 0);
        capture.chunk([NSMutableData dataWithLength:32], nil);
        [controller finishDoubaoVoiceInput];
        assert(request.audio.length == 48 && request.finishes == 1 && capture.finishes == 1);
        request.result(@"synthetic final", YES, nil);
        assert(client.commits.count == 1 && [client.commits[0] isEqual:@"synthetic final"] && !capture.active);
        request.result(@"duplicate", YES, nil);
        assert(client.commits.count == 1);
        assert(Start(controller, capture, session, NO));
        controller.fixture.result(@"hidden partial", NO, nil);
        assert(!client.marked.length);
        [controller cancelDoubaoVoiceInput];
        assert(Start(controller, capture, session, YES));
        request = controller.fixture;
        request.result(@"cancelled partial", NO, nil);
        [controller cancelDoubaoVoiceInput];
        assert(!client.marked.length && request.cancellations == 1);
        assert(Start(controller, capture, session, YES));
        request.result(@"late old final", YES, nil);
        assert(capture.active && client.commits.count == 1);
        [controller finishDoubaoVoiceInput];
        [controller finishDoubaoVoiceInput];
        assert(!capture.active && controller.fixture.finishes == 1);
        for (NSString *field in @[@"activeClient", @"session", @"voiceGeneration"]) {
            assert(Start(controller, capture, session, YES));
            id original = [controller valueForKey:field];
            [controller setValue:[field isEqual:@"voiceGeneration"] ? @99999 : [NSObject new] forKey:field];
            controller.fixture.result(@"stale focus", YES, nil);
            [controller setValue:original forKey:field];
            assert(client.commits.count == 1);
        }
        capture.failStart = YES;
        assert(!Start(controller, capture, session, YES) && !capture.active);
        capture.failStart = NO;
        controller.failRequest = YES;
        assert(!Start(controller, capture, session, YES) && !capture.active);
        controller.failRequest = NO;
        assert(Start(controller, capture, session, YES));
        controller.fixture.failAppend = YES;
        capture.chunk([NSMutableData dataWithLength:32], nil);
        Pump();
        assert(!capture.active);
        // Exercise the actual toggle route without touching persistent defaults.
        NSUserDefaults *defaults = NSUserDefaults.standardUserDefaults;
        NSDictionary *oldArguments = [defaults volatileDomainForName:NSArgumentDomain];
        [defaults setVolatileDomain:@{@"MSIMEClientVoiceASRProvider": @"doubao", @"MSIMEClientVoiceMuteSystemAudio": @NO} forName:NSArgumentDomain];
        DoubaoPresentationFixture *presentation = [DoubaoPresentationFixture new];
        [controller setValue:presentation forKey:@"voiceOverlay"];
        [controller setValue:presentation forKey:@"voiceAudioMuter"];
        [controller setValue:presentation forKey:@"voiceCuePlayer"];
        assert([controller usesNativeDoubaoVoice] && ![controller usesNativeHTTPVoice]);
        assert([session setFocused:YES error:nil]);
        assert([session typeASCII:'U' shift:YES error:nil]);
        for (const char *key = "4e2d"; *key; ++key) assert([session typeASCII:*key shift:NO error:nil]);
        [controller toggleVoiceInput:nil];
        assert(client.commits.count == 2 && [client.commits[1] isEqual:@"中"]);
        assert(!client.marked.length); // Engine composition finishes before voice presentation.
        assert(capture.active && [controller valueForKey:@"doubaoVoiceRequest"] == controller.fixture);
        [controller toggleVoiceInput:nil];
        assert(controller.fixture.finishes == 1);
        [controller voiceProviderSettingsChanged:nil];
        assert(!capture.active);
        [defaults setVolatileDomain:oldArguments forName:NSArgumentDomain];
        controller.usePolishFixture = YES;
        assert(Start(controller, capture, session, YES));
        controller.fixture.result(@"unpolished", YES, nil);
        controller.fixture.result(@"duplicate final", YES, nil);
        assert(client.commits.count == 2 && controller.polishFixture.submissions == 1);
        controller.polishFixture.completion(@"synthetic polished", nil);
        assert(client.commits.count == 3 && [client.commits.lastObject isEqual:@"synthetic polished"]);
        assert(Start(controller, capture, session, YES));
        controller.fixture.result(@"cancelled polish", YES, nil);
        DoubaoPolishFixture *oldPolish = controller.polishFixture;
        [controller cancelDoubaoVoiceInput];
        assert(oldPolish.cancellations == 1);
        assert(Start(controller, capture, session, YES));
        oldPolish.completion(@"late polish", nil);
        assert(capture.active && client.commits.count == 3);
        controller.fixture.result(@"focus moved", YES, nil);
        [controller setValue:[DoubaoTextFixture new] forKey:@"activeClient"];
        controller.polishFixture.completion(@"wrong focus", nil);
        assert(client.commits.count == 3);
        [controller setValue:client forKey:@"activeClient"];
        assert([session closeWithError:nil]);
        assert([NSFileManager.defaultManager removeItemAtPath:root error:nil]);
    }
}
