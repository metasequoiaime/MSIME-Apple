#import "../../src/voice/VoiceInputLevel.h"
#include <cassert>
#include <limits>
#include <vector>

int main() {
    using msime::voice::input_level;
    @autoreleasepool {
        float silence[] = {0, 0, 0, 0};
        float noise[] = {0.003f, -0.003f, 0.004f, -0.004f};
        float speech[] = {0.03f, -0.03f, 0.03f, -0.03f};
        assert(input_level(nullptr, 1) == 0 && input_level(speech, 0) == 0);
        assert(input_level(silence, 4) == 0 && input_level(noise, 4) == 0);
        const float expected = std::pow((0.03f - 0.004f) * 14, 0.55f);
        assert(std::fabs(input_level(speech, 4) - expected) < 1e-6f && expected > 0.5f);
        float loud[] = {-1, 1, 2, -2};
        assert(input_level(loud, 4) == 1);
        std::vector<float> impulse(1024, 0); impulse[0] = 1;
        assert(input_level(impulse.data(), impulse.size()) < 0.7f); // Not a peak meter.
        for (float invalid : {std::numeric_limits<float>::infinity(), std::numeric_limits<float>::quiet_NaN()}) {
            float broken[] = {invalid, 0.5f}; assert(input_level(broken, 2) == 0);
        }
        for (BOOL interleaved : {NO, YES}) {
            for (AVAudioCommonFormat type : {AVAudioPCMFormatFloat32, AVAudioPCMFormatInt16, AVAudioPCMFormatInt32}) {
                AVAudioFormat *format = [[AVAudioFormat alloc] initWithCommonFormat:type sampleRate:48000 channels:2 interleaved:interleaved];
                AVAudioPCMBuffer *buffer = [[AVAudioPCMBuffer alloc] initWithPCMFormat:format frameCapacity:4];
                buffer.frameLength = 4;
                for (NSUInteger channel = 0; channel < 2; ++channel) {
                    for (NSUInteger frame = 0; frame < 4; ++frame) {
                        const auto index = frame * buffer.stride;
                        const float sample = channel ? -0.03125f : 0.03125f;
                        if (type == AVAudioPCMFormatFloat32) buffer.floatChannelData[channel][index] = sample;
                        if (type == AVAudioPCMFormatInt16) buffer.int16ChannelData[channel][index] = static_cast<int16_t>(sample * 32768);
                        if (type == AVAudioPCMFormatInt32) buffer.int32ChannelData[channel][index] = static_cast<int32_t>(sample * 2147483648.0);
                    }
                }
                const float reference[] = {0.03125f};
                assert(std::fabs(MSIMEVoiceInputLevel(buffer) - input_level(reference, 1)) < 1e-6f);
                buffer.frameLength = 0; assert(MSIMEVoiceInputLevel(buffer) == 0);
            }
        }
        assert(MSIMEVoiceInputLevel(nil) == 0);
    }
}
