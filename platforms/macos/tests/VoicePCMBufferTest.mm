#import "../src/VoicePCMBuffer.h"
#include <cassert>
#include <cmath>
#include <limits>
#include <cstdio>

static AVAudioPCMBuffer *Fixture(double rate, AVAudioChannelCount channels, AVAudioFrameCount frames) {
    AVAudioFormat *format = [[AVAudioFormat alloc] initStandardFormatWithSampleRate:rate channels:channels];
    AVAudioPCMBuffer *buffer = [[AVAudioPCMBuffer alloc] initWithPCMFormat:format frameCapacity:frames];
    buffer.frameLength = frames;
    for (AVAudioChannelCount channel = 0; channel < channels; ++channel)
        for (AVAudioFrameCount frame = 0; frame < frames; ++frame) buffer.floatChannelData[channel][frame] = 0.25f;
    return buffer;
}
int main() {
    @autoreleasepool {
        for (NSNumber *rate in @[@16000, @44100, @48000]) {
            MSIMEVoicePCMBuffer *recording = [MSIMEVoicePCMBuffer new];
            AVAudioPCMBuffer *chunk = Fixture(rate.doubleValue, 2, rate.unsignedIntValue / 100);
            for (int index = 0; index < 100; ++index) assert([recording append:chunk error:nil]);
            NSData *pcm = [recording finishWithError:nil];
            std::fprintf(stderr, "synthetic rate %.0f: %lu output frames\n", rate.doubleValue, (unsigned long)(pcm.length / sizeof(float)));
            assert(pcm && std::abs((long)(pcm.length / sizeof(float)) - 16000L) <= 1);
            const float *samples = (const float *)pcm.bytes;
            for (NSUInteger index = 100; index + 100 < pcm.length / sizeof(float); ++index)
                assert(std::fabs(samples[index] - 0.25f) < 0.01f);
            assert([[recording finishWithError:nil] isEqual:pcm]);
            MSIMEVoicePCMBuffer *whole = [MSIMEVoicePCMBuffer new];
            assert([whole append:Fixture(rate.doubleValue, 2, rate.unsignedIntValue) error:nil]);
            assert([[whole finishWithError:nil] isEqual:pcm]);
            MSIMEVoicePCMBuffer *limit = [MSIMEVoicePCMBuffer new];
            AVAudioPCMBuffer *oneSecond = Fixture(rate.doubleValue, 1, rate.unsignedIntValue);
            for (int second = 0; second < 60; ++second) assert([limit append:oneSecond error:nil]);
            assert([limit finishWithError:nil].length == 16000 * 60 * sizeof(float));
        }
        MSIMEVoicePCMBuffer *recording = [MSIMEVoicePCMBuffer new];
        AVAudioPCMBuffer *second = Fixture(16000, 1, 16000);
        for (int index = 0; index < 60; ++index) assert([recording append:second error:nil]);
        NSError *error = nil;
        assert(![recording append:second error:&error] && error);
        assert(![recording finishWithError:nil]); // Never upload a truncated recording.
        recording = [MSIMEVoicePCMBuffer new];
        assert([recording append:second error:nil]);
        [recording cancel];
        assert(![recording finishWithError:nil]);
        assert(![recording append:second error:nil]);
        recording = [MSIMEVoicePCMBuffer new];
        assert([recording append:second error:nil]);
        assert(![recording append:Fixture(48000, 1, 480) error:nil]);
        assert(![recording finishWithError:nil]);
        recording = [MSIMEVoicePCMBuffer new];
        second.floatChannelData[0][100] = std::numeric_limits<float>::quiet_NaN();
        assert(![recording append:second error:nil]);
        assert(![recording finishWithError:nil]);
        assert([[MSIMEVoicePCMBuffer new] finishWithError:nil].length == 0);
    }
}
