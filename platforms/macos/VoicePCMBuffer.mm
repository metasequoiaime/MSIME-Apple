#import "VoicePCMBuffer.h"
#include <cmath>

@implementation MSIMEVoicePCMBuffer {
    AVAudioConverter *_converter;
    NSMutableData *_pcm;
    BOOL _finished;
    BOOL _failed;
    uint64_t _inputFrames;
    double _inputRate;
}
- (BOOL)fail:(NSError **)error {
    _failed = YES;
    _pcm = nil;
    _converter = nil;
    if (error) *error = [NSError errorWithDomain:@"app.msime.client.voice" code:3
        userInfo:@{NSLocalizedDescriptionKey: @"录音格式无效或超过 60 秒限制"}];
    return NO;
}
- (BOOL)convert:(AVAudioPCMBuffer *)input final:(BOOL)final error:(NSError **)error {
    __block BOOL supplied = NO;
    while (true) {
        AVAudioPCMBuffer *output = [[AVAudioPCMBuffer alloc] initWithPCMFormat:_converter.outputFormat frameCapacity:4096];
        NSError *conversionError = nil;
        AVAudioConverterOutputStatus status = [_converter convertToBuffer:output error:&conversionError
            withInputFromBlock:^AVAudioBuffer *(AVAudioPacketCount count, AVAudioConverterInputStatus *inputStatus) {
                (void)count;
                if (input && !supplied) {
                    supplied = YES;
                    *inputStatus = AVAudioConverterInputStatus_HaveData;
                    return input;
                }
                *inputStatus = final ? AVAudioConverterInputStatus_EndOfStream : AVAudioConverterInputStatus_NoDataNow;
                return nil;
            }];
        if (conversionError || status == AVAudioConverterOutputStatus_Error) return [self fail:error];
        if (output.frameLength) {
            const float *samples = output.floatChannelData[0];
            for (AVAudioFrameCount index = 0; index < output.frameLength; ++index) {
                if (!std::isfinite(samples[index]) || std::fabs(samples[index]) > 1.0f) return [self fail:error];
            }
            // The converter can append filter padding at end-of-stream. Input
            // duration is bounded before conversion; padding is not recorded audio.
            NSUInteger remaining = 16000 * 60 - _pcm.length / sizeof(float);
            [_pcm appendBytes:samples length:MIN(remaining, output.frameLength) * sizeof(float)];
        }
        if (status == AVAudioConverterOutputStatus_EndOfStream || status == AVAudioConverterOutputStatus_InputRanDry)
            return YES;
        if (!output.frameLength) return [self fail:error];
    }
}
- (BOOL)append:(AVAudioPCMBuffer *)buffer error:(NSError **)error {
    @synchronized(self) {
        if (_finished || _failed) return [self fail:error];
        AVAudioFormat *format = buffer.format;
        if (!buffer || !std::isfinite(format.sampleRate) || format.sampleRate < 8000 ||
            format.sampleRate > 192000 || format.channelCount < 1 || format.channelCount > 8)
            return [self fail:error];
        if (!_converter) {
            AVAudioFormat *target = [[AVAudioFormat alloc] initStandardFormatWithSampleRate:16000 channels:1];
            _converter = [[AVAudioConverter alloc] initFromFormat:format toFormat:target];
            if (!_converter) return [self fail:error];
            _converter.primeMethod = AVAudioConverterPrimeMethod_None;
            _pcm = [NSMutableData data];
            _inputRate = format.sampleRate;
        } else if (![_converter.inputFormat isEqual:format]) {
            return [self fail:error];
        }
        if (!buffer.frameLength) return YES;
        if (_inputFrames + buffer.frameLength > _inputRate * 60) return [self fail:error];
        _inputFrames += buffer.frameLength;
        return [self convert:buffer final:NO error:error];
    }
}
- (NSData *)finishWithError:(NSError **)error {
    @synchronized(self) {
        if (_failed) { [self fail:error]; return nil; }
        if (!_finished && _converter && ![self convert:nil final:YES error:error]) return nil;
        if (_inputRate > 0) {
            NSUInteger frames = (NSUInteger)std::llround(_inputFrames * 16000.0 / _inputRate);
            if (_pcm.length > frames * sizeof(float)) _pcm.length = frames * sizeof(float);
        }
        _finished = YES;
        _converter = nil;
        return [_pcm copy] ?: NSData.data;
    }
}
- (void)cancel {
    @synchronized(self) {
        _failed = YES;
        _pcm = nil;
        _converter = nil;
    }
}
@end
