#pragma once
#import <AVFoundation/AVFoundation.h>

// Native capture adaptation only: 16 kHz mono float PCM for the shared Engine
// provider. All access is serialized; no files, credentials or transcripts.
@interface MSIMEVoicePCMBuffer : NSObject
- (BOOL)append:(AVAudioPCMBuffer *)buffer error:(NSError **)error;
- (NSData *)finishWithError:(NSError **)error;
// Return each converted sample at most once. Before finish, withhold any
// converter padding beyond the captured input duration. Finish still returns
// the complete recording for existing HTTP callers; drain then returns its tail.
- (NSData *)drainWithError:(NSError **)error;
- (void)cancel;
@end
