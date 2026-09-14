#import "../VoiceDeactivation.h"
#include <cassert>

@interface VoiceFixture : NSObject
@property(getter=isActive) BOOL active;
@property NSUInteger cancellations;
- (BOOL)cancelWithError:(NSError **)error;
@end
@implementation VoiceFixture
- (BOOL)cancelWithError:(NSError **)error {
    (void)error;
    assert(NSThread.isMainThread);
    self.active = NO; ++self.cancellations; return YES;
}
@end
@interface PresentationFixture : NSObject
@property NSUInteger restorations;
@property BOOL listening;
- (void)restore;
@end
@implementation PresentationFixture
- (void)restore { assert(NSThread.isMainThread); ++self.restorations; }
@end
@interface SessionFixture : NSObject
@property dispatch_semaphore_t completed;
@property NSString *path;
@property uint64_t generation;
@property NSUInteger cancellations;
- (BOOL)voiceProviderCancelSocket:(NSString *)path generation:(uint64_t)generation error:(NSError **)error;
@end
@implementation SessionFixture
- (BOOL)voiceProviderCancelSocket:(NSString *)path generation:(uint64_t)generation error:(NSError **)error {
    (void)error;
    assert(!NSThread.isMainThread);
    self.path = path; self.generation = generation; ++self.cancellations;
    dispatch_semaphore_signal(self.completed); return YES;
}
@end
int main() {
    @autoreleasepool {
        VoiceFixture *voice = [VoiceFixture new]; voice.active = YES;
        PresentationFixture *presentation = [PresentationFixture new]; presentation.listening = YES;
        SessionFixture *session = [SessionFixture new]; session.completed = dispatch_semaphore_create(0);
        MSIMEDeactivateVoice((id)voice, (id)session, (id)presentation, (id)presentation, @"/tmp/synthetic-voice.sock", 42);
        assert(!voice.active && voice.cancellations == 1);
        assert(!presentation.listening && presentation.restorations == 1);
        assert(dispatch_semaphore_wait(session.completed, dispatch_time(DISPATCH_TIME_NOW, NSEC_PER_SEC)) == 0);
        assert(session.generation == 42 && [session.path isEqual:@"/tmp/synthetic-voice.sock"]);
        assert(session.cancellations == 1);
        // Repeated cleanup must not enqueue another provider cancellation.
        MSIMEDeactivateVoice((id)voice, (id)session, (id)presentation, (id)presentation, @"/tmp/synthetic-voice.sock", 43);
        assert(dispatch_semaphore_wait(session.completed, dispatch_time(DISPATCH_TIME_NOW, 10000000)) != 0);
        voice.active = YES;
        MSIMEDeactivateVoice((id)voice, (id)session, (id)presentation, (id)presentation, nil, 44);
        assert(!voice.active && voice.cancellations == 3);
        assert(dispatch_semaphore_wait(session.completed, dispatch_time(DISPATCH_TIME_NOW, 10000000)) != 0);
        MSIMEDeactivateVoice(nil, nil, nil, nil, nil, 0);
    }
}
