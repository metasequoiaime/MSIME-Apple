#import "../VoiceInputService.h"
#import "../VoicePCMBuffer.h"
#include <cassert>
#include <cmath>
#include <limits>
#include <atomic>
#include <chrono>
#include <thread>

static AVAudioPCMBuffer *Audio(double rate, AVAudioFrameCount frames) {
    AVAudioFormat *format = [[AVAudioFormat alloc] initStandardFormatWithSampleRate:rate channels:2];
    AVAudioPCMBuffer *buffer = [[AVAudioPCMBuffer alloc] initWithPCMFormat:format frameCapacity:frames];
    buffer.frameLength = frames;
    for (NSUInteger channel = 0; channel < 2; ++channel)
        for (NSUInteger i = 0; i < frames; ++i) buffer.floatChannelData[channel][i] = 0.125f;
    return buffer;
}
@interface PCMStreamCapture : MSIMEVoiceInputService
@property(copy) MSIMEVoiceAudioBuffer capture;
@property(copy) NSString *device;
@property BOOL failStart;
@property NSUInteger stops;
@end
@implementation PCMStreamCapture
- (BOOL)startMicrophoneCapture:(MSIMEVoiceAudioBuffer)handler deviceUID:(NSString *)device error:(NSError **)error {
    (void)error; self.capture = handler; self.device = device; return !self.failStart;
}
- (void)stopMicrophoneCapture { self.capture = nil; ++self.stops; }
@end
int main() {
    @autoreleasepool {
        for (NSNumber *rate in @[@16000, @44100, @48000, @96000]) {
            MSIMEVoicePCMBuffer *recording = [MSIMEVoicePCMBuffer new];
            NSMutableData *streamed = [NSMutableData data];
            AVAudioPCMBuffer *chunk = Audio(rate.doubleValue, 137);
            for (NSUInteger i = 0; i < 101; ++i) {
                assert([recording append:chunk error:nil]);
                NSData *next = [recording drainWithError:nil];
                assert(next);
                [streamed appendData:next];
                assert(streamed.length / sizeof(float) <= std::floor((i + 1) * 137 * 16000.0 / rate.doubleValue));
                assert([recording drainWithError:nil].length == 0);
            }
            assert(streamed.length > 0); // Data is available before finish.
            NSData *whole = [recording finishWithError:nil];
            [streamed appendData:[recording drainWithError:nil]];
            assert([streamed isEqual:whole] && [recording drainWithError:nil].length == 0);
            assert([[recording finishWithError:nil] isEqual:whole]);
            [recording cancel];
            assert(![recording drainWithError:nil]);
        }
        PCMStreamCapture *service = [PCMStreamCapture new];
        AVAudioPCMBuffer *chunk = Audio(48000, 4800);
        NSMutableData *streamed = [NSMutableData data];
        __block NSUInteger callbacks = 0;
        MSIMEVoicePCMChunk handler = ^(NSData *pcm, NSError *error) {
            assert(pcm.length && !error); [streamed appendData:pcm]; ++callbacks;
        };
        assert([service startPCMStreaming:handler deviceUID:@"synthetic-device" error:nil]);
        assert([service.device isEqual:@"synthetic-device"]);
        assert(![service startPCMStreaming:handler deviceUID:nil error:nil]);
        MSIMEVoiceAudioBuffer old = service.capture;
        old(chunk);
        assert(callbacks == 1 && streamed.length > 0);
        NSData *tail = [service finishPCMStreamingWithError:nil];
        assert(tail && service.stops == 1);
        [streamed appendData:tail];
        MSIMEVoicePCMBuffer *whole = [MSIMEVoicePCMBuffer new];
        assert([whole append:chunk error:nil]);
        assert([streamed isEqual:[whole finishWithError:nil]]);
        assert(![service finishPCMStreamingWithError:nil]);
        assert([service startPCMStreaming:handler deviceUID:nil error:nil]);
        old(chunk);
        assert(callbacks == 1);
        old = service.capture;
        assert([service cancelWithError:nil]);
        old(chunk);
        assert(callbacks == 1 && ![service finishPCMStreamingWithError:nil]);
        __block NSUInteger failures = 0;
        assert([service startPCMStreaming:^(NSData *pcm, NSError *error) {
            assert(!pcm && error); ++failures;
        } deviceUID:nil error:nil]);
        AVAudioPCMBuffer *bad = Audio(48000, 4800);
        bad.floatChannelData[0][10] = std::numeric_limits<float>::quiet_NaN();
        service.capture(bad); service.capture(bad);
        assert(failures == 1 && ![service finishPCMStreamingWithError:nil]);
        service.failStart = YES;
        assert(![service startPCMStreaming:handler deviceUID:nil error:nil]);
        service.capture(chunk);
        assert(callbacks == 1 && ![service finishPCMStreamingWithError:nil]);
        service.failStart = NO;
        assert([service startPCMStreaming:handler deviceUID:nil error:nil]);
        assert([service finishPCMStreamingWithError:nil].length == 0);
        __weak PCMStreamCapture *released;
        @autoreleasepool {
            PCMStreamCapture *temporary = [PCMStreamCapture new];
            released = temporary;
            assert([temporary startPCMStreaming:handler deviceUID:nil error:nil]);
            old = temporary.capture;
            temporary = nil;
        }
        assert(!released);
        old(chunk);
        assert(callbacks == 1);
        // Finish must wait for a block already drained but still being delivered.
        dispatch_semaphore_t entered = dispatch_semaphore_create(0);
        dispatch_semaphore_t release = dispatch_semaphore_create(0);
        NSMutableData *concurrent = [NSMutableData data];
        std::atomic_bool deliveryReleased{false};
        assert([service startPCMStreaming:^(NSData *pcm, NSError *error) {
            assert(pcm && !error);
            dispatch_semaphore_signal(entered);
            dispatch_semaphore_wait(release, DISPATCH_TIME_FOREVER);
            [concurrent appendData:pcm];
        } deviceUID:nil error:nil]);
        MSIMEVoiceAudioBuffer tap = service.capture;
        std::thread producer([&] { @autoreleasepool { tap(chunk); } });
        assert(dispatch_semaphore_wait(entered, dispatch_time(DISPATCH_TIME_NOW, NSEC_PER_SEC)) == 0);
        std::thread releaser([&] {
            std::this_thread::sleep_for(std::chrono::milliseconds(30));
            deliveryReleased.store(true);
            dispatch_semaphore_signal(release);
        });
        NSData *concurrentTail = [service finishPCMStreamingWithError:nil];
        assert(deliveryReleased.load());
        producer.join(); releaser.join();
        assert(concurrentTail);
        [concurrent appendData:concurrentTail];
        assert([concurrent isEqual:[whole finishWithError:nil]]);
    }
}
