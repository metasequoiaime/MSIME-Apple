#import "../../src/voice/VoicePCMBuffer.h"
#include "../../../../shared/voice/VoiceProviders.h"
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
            // Reaching the limit stops the recording taking audio but never fails it: what was captured up to the limit is still submitted. The limit falls inside the second buffer, so the tail of that buffer is cut as well.
            MSIMEVoicePCMBuffer *limit = [[MSIMEVoicePCMBuffer alloc] initWithSampleLimit:24000];
            AVAudioPCMBuffer *oneSecond = Fixture(rate.doubleValue, 1, rate.unsignedIntValue);
            for (int second = 0; second < 5; ++second) assert([limit append:oneSecond error:nil]);
            NSData *capped = [limit finishWithError:nil];
            assert(capped.length == 24000 * sizeof(float));
            assert(std::fabs(((const float *)capped.bytes)[23999] - 0.25f) < 0.01f); // Recorded audio, not converter padding.
            assert([[limit finishWithError:nil] isEqual:capped]);
        }
        // A batch recording is no longer cut at 60 s. It keeps the MSIME-Windows batch upload budget, the 20 MiB of 16-bit WAV, less SiliconFlow's padding; past that it keeps accepting buffers and submits what fits.
        MSIMEVoicePCMBuffer *recording = [MSIMEVoicePCMBuffer new];
        AVAudioPCMBuffer *second = Fixture(16000, 1, 16000);
        const NSUInteger batchSeconds = msime::voice::batch_capture_sample_limit / 16000 + 2;
        for (NSUInteger index = 0; index < batchSeconds; ++index) assert([recording append:second error:nil]);
        NSData *batch = [recording finishWithError:nil];
        assert(batch.length == msime::voice::batch_capture_sample_limit * sizeof(float));
        assert(44 + 2 * (batch.length / sizeof(float)) + 2 * 3200 * 2 <= 20 * 1024 * 1024);
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
