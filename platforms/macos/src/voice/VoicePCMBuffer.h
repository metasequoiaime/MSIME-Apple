#pragma once
#import <AVFoundation/AVFoundation.h>

// Native capture adaptation only: 16 kHz mono float PCM for the shared Engine provider. All access is serialized; no files, credentials or transcripts.
@interface MSIMEVoicePCMBuffer : NSObject
// A batch recording: keeps at most msime::voice::batch_capture_sample_limit output samples, the upload budget MSIME-Windows allows a batch provider.
- (instancetype)init;
// Keep at most `sampleLimit` 16 kHz samples. Audio arriving after the limit is dropped rather than failing the recording, so the host still submits everything captured up to it, like MSIME-Windows submits whatever it captured. NSUIntegerMax means no limit, for a stream that drains as it goes.
- (instancetype)initWithSampleLimit:(NSUInteger)sampleLimit NS_DESIGNATED_INITIALIZER;
- (BOOL)append:(AVAudioPCMBuffer *)buffer error:(NSError **)error;
// Every sample not yet drained. For a recording that is never drained, that is the complete recording.
- (NSData *)finishWithError:(NSError **)error;
// Return each converted sample at most once and release it, so a streamed recording holds only what has not been delivered yet. Before finish, withhold any converter padding beyond the captured input duration; after finish, drain returns the tail.
- (NSData *)drainWithError:(NSError **)error;
- (void)cancel;
@end
