#pragma once
#import <AVFoundation/AVFoundation.h>
#include <cstring>
inline NSData *MSIMEVoiceMeterFixturePCM() {
    const float samples[] = {0.03f, -0.03f, 0.03f, -0.03f, 0.03f, -0.03f, 0.03f, -0.03f};
    return [NSData dataWithBytes:samples length:sizeof(samples)];
}
inline AVAudioPCMBuffer *MSIMEVoiceMeterFixtureBuffer() {
    AVAudioFormat *format = [[AVAudioFormat alloc] initStandardFormatWithSampleRate:16000 channels:1];
    AVAudioPCMBuffer *buffer = [[AVAudioPCMBuffer alloc] initWithPCMFormat:format frameCapacity:8];
    buffer.frameLength = 8;
    NSData *pcm = MSIMEVoiceMeterFixturePCM();
    std::memcpy(buffer.floatChannelData[0], pcm.bytes, pcm.length);
    return buffer;
}
inline void MSIMEVoiceMeterFixturePump() {
    [NSRunLoop.currentRunLoop runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.03]];
}
