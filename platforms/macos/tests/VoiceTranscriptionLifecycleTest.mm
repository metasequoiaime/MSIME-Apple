#import "../VoiceInputService.h"
#import <objc/runtime.h>
#include <cassert>

typedef void (^Reply)(SFSpeechRecognitionResult *, NSError *);
static NSMutableArray<Reply> *replies;
@interface FixtureTask : NSObject
@property BOOL cancelled;
- (void)cancel;
@end
@implementation FixtureTask
- (void)cancel { self.cancelled = YES; }
@end
static NSMutableArray<FixtureTask *> *tasks;
@interface FixtureResult : NSObject
@property BOOL isFinal;
- (id)bestTranscription;
- (NSString *)formattedString;
@end
@implementation FixtureResult
- (id)bestTranscription { return self; }
- (NSString *)formattedString { return @"synthetic fixture"; }
@end

static SFSpeechRecognizerAuthorizationStatus Authorized(id, SEL) {
    return SFSpeechRecognizerAuthorizationStatusAuthorized;
}
static id Recognize(id, SEL, id, Reply reply) {
    [replies addObject:[reply copy]];
    FixtureTask *task = [FixtureTask new];
    [tasks addObject:task];
    return task;
}
static void Drain() {
    __block BOOL done = NO;
    dispatch_async(dispatch_get_main_queue(), ^{ done = YES; });
    while (!done) [NSRunLoop.currentRunLoop runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.001]];
}
int main() {
    @autoreleasepool {
        replies = [NSMutableArray array]; tasks = [NSMutableArray array];
        Method auth = class_getClassMethod(SFSpeechRecognizer.class, @selector(authorizationStatus));
        Method recognize = class_getInstanceMethod(SFSpeechRecognizer.class, @selector(recognitionTaskWithRequest:resultHandler:));
        IMP oldAuth = method_setImplementation(auth, (IMP)Authorized);
        IMP oldRecognize = method_setImplementation(recognize, (IMP)Recognize);
        MSIMEVoiceInputService *service = [MSIMEVoiceInputService new];
        __block NSUInteger delivered = 0;
        void (^handler)(NSString *, BOOL) = ^(NSString *text, BOOL final) {
            (void)final;
            assert(NSThread.isMainThread);
            assert([text isEqual:@"synthetic fixture"]);
            ++delivered;
        };
        assert([service startTranscriptionWithLanguage:@"en-US" textHandler:handler error:nil]);
        assert([service startTranscriptionWithLanguage:@"en-US" textHandler:handler error:nil]);
        assert(tasks[0].cancelled);
        FixtureResult *result = [FixtureResult new]; result.isFinal = YES;
        replies[0]((id)result, nil);
        Drain();
        assert(delivered == 0 && !tasks[1].cancelled);
        replies[1]((id)result, nil);
        Drain();
        assert(delivered == 1 && tasks[1].cancelled);
        assert([service startTranscriptionWithLanguage:@"en-US" textHandler:handler error:nil]);
        [service stopTranscription];
        replies[2]((id)result, nil);
        Drain();
        assert(delivered == 1);
        // A final-result handler can synchronously start a successor.
        assert([service startTranscriptionWithLanguage:@"en-US" textHandler:^(NSString *, BOOL) {
            assert([service startTranscriptionWithLanguage:@"en-US" textHandler:handler error:nil]);
        } error:nil]);
        replies[3]((id)result, nil);
        Drain();
        assert(tasks.count == 5 && !tasks[4].cancelled);
        replies[3](nil, [NSError errorWithDomain:@"fixture" code:1 userInfo:nil]);
        Drain();
        assert(!tasks[4].cancelled);
        __block BOOL failed = NO;
        assert([service startTranscriptionWithLanguage:@"en-US" textHandler:^(NSString *text, BOOL final) {
            assert(NSThread.isMainThread && final && !text.length); failed = YES;
        } error:nil]);
        replies[5](nil, [NSError errorWithDomain:@"fixture" code:1 userInfo:nil]);
        Drain();
        assert(failed && tasks[5].cancelled);
        [service stopTranscription];
        [replies removeAllObjects];
        method_setImplementation(auth, oldAuth);
        method_setImplementation(recognize, oldRecognize);
    }
}
