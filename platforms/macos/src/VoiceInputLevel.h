#pragma once
#import <AVFoundation/AVFoundation.h>
#include "../../../shared/voice/InputLevel.h"

inline float MSIMEVoiceInputLevel(AVAudioPCMBuffer *buffer) {
    if (!buffer) return 0;
    const auto channels = buffer.format.channelCount;
    const auto frames = buffer.frameLength;
    const auto stride = buffer.stride;
    if (buffer.floatChannelData)
        return msime::voice::input_level(buffer.floatChannelData, channels, frames, stride);
    if (buffer.int16ChannelData)
        return msime::voice::input_level(buffer.int16ChannelData, channels, frames, stride, 1.0 / 32768);
    if (buffer.int32ChannelData)
        return msime::voice::input_level(buffer.int32ChannelData, channels, frames, stride, 1.0 / 2147483648);
    return 0;
}
