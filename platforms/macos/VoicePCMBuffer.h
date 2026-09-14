#pragma once
#import <AVFoundation/AVFoundation.h>

// Native capture adaptation only: 16 kHz mono float PCM for the shared Engine
// provider. All access is serialized; no files, credentials or transcripts.
@interface MSIMEVoicePCMBuffer : NSObject
- (BOOL)append:(AVAudioPCMBuffer *)buffer error:(NSError **)error;
- (NSData *)finishWithError:(NSError **)error;
- (void)cancel;
@end
