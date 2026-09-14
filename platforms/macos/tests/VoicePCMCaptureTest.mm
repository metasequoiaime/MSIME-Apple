#import "../VoiceInputService.h"
#include <cassert>
#include <limits>

static void Drain() {
    __block BOOL done = NO;
    dispatch_async(dispatch_get_main_queue(), ^{ done = YES; });
    while (!done) [NSRunLoop.currentRunLoop runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.001]];
}

@interface SyntheticCapture : MSIMEVoiceInputService
@property(copy) MSIMEVoiceAudioBuffer capture;
@property(copy) NSString *device;
@property BOOL failStart;
@property NSUInteger stops;
@end
@implementation SyntheticCapture
- (BOOL)startMicrophoneCapture:(MSIMEVoiceAudioBuffer)handler deviceUID:(NSString *)device error:(NSError **)error {
    (void)error;
    self.capture = handler; self.device = device;
    return !self.failStart;
}
- (void)stopMicrophoneCapture { ++self.stops; self.capture = nil; }
@end
int main() {
    @autoreleasepool {
        AVAudioFormat *format = [[AVAudioFormat alloc] initStandardFormatWithSampleRate:48000 channels:1];
        AVAudioPCMBuffer *buffer = [[AVAudioPCMBuffer alloc] initWithPCMFormat:format frameCapacity:4800];
        buffer.frameLength = 4800;
        for (NSUInteger i = 0; i < 4800; ++i) buffer.floatChannelData[0][i] = 0.125f;
        SyntheticCapture *service = [SyntheticCapture new];
        __block NSUInteger callbacks = 0;
        MSIMEVoiceAudioBuffer observe = ^(AVAudioPCMBuffer *value) { assert(value == buffer); ++callbacks; };
        assert([service startPCMRecording:observe deviceUID:@"synthetic-device" error:nil]);
        assert([service.device isEqual:@"synthetic-device"]);
        assert(![service startPCMRecording:observe deviceUID:nil error:nil]);
        MSIMEVoiceAudioBuffer old = service.capture;
        old(buffer);
        NSData *pcm = [service finishPCMRecordingWithError:nil];
        assert(pcm.length == 1600 * sizeof(float) && callbacks == 1 && service.stops == 1);
        assert(![service finishPCMRecordingWithError:nil]);
        assert([service startPCMRecording:observe deviceUID:nil error:nil]);
        old(buffer); // Late audio must neither alter the successor nor notify its UI.
        assert(callbacks == 1);
        service.capture(buffer);
        assert([[service finishPCMRecordingWithError:nil] isEqual:pcm]);
        assert([service startPCMRecording:observe deviceUID:nil error:nil]);
        old = service.capture;
        old(buffer);
        assert([service cancelWithError:nil]);
        old(buffer);
        assert(callbacks == 3 && ![service finishPCMRecordingWithError:nil]);
        service.failStart = YES;
        assert(![service startPCMRecording:observe deviceUID:nil error:nil]);
        assert(![service finishPCMRecordingWithError:nil]);
        service.failStart = NO;
        assert([service startPCMRecording:observe deviceUID:nil error:nil]);
        assert([service finishPCMRecordingWithError:nil].length == 0);
        __block NSUInteger failures = 0;
        void (^failure)(NSError *) = ^(NSError *error) { assert(NSThread.isMainThread && error); ++failures; };
        assert([service startPCMRecording:observe deviceUID:nil failure:failure error:nil]);
        buffer.floatChannelData[0][0] = std::numeric_limits<float>::quiet_NaN();
        old = service.capture;
        NSUInteger stopped = service.stops;
        old(buffer); old(buffer);
        assert(failures == 0 && service.stops == stopped);
        Drain();
        assert(failures == 1 && service.stops == stopped + 1 && ![service finishPCMRecordingWithError:nil]);
        assert([service startPCMRecording:observe deviceUID:nil failure:failure error:nil]);
        service.capture(buffer); // Queue an error, then replace the recording.
        assert([service cancelWithError:nil]);
        assert([service startPCMRecording:observe deviceUID:nil failure:failure error:nil]);
        stopped = service.stops;
        Drain();
        assert(failures == 1 && service.stops == stopped);
        buffer.floatChannelData[0][0] = 0.125f;
        for (NSUInteger i = 0; i < 601; ++i) service.capture(buffer);
        Drain();
        assert(failures == 2 && service.stops == stopped + 1);
    }
}
