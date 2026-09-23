#pragma once
#import <Foundation/Foundation.h>

// One batch recognition request: a frozen configuration and a cancellation token, taking the whole recording at once and delivering on the main queue; cancellation suppresses delivery. No audio capture. Most providers are reached over HTTP, which is where the name comes from - the on-device Whisper provider shares everything here except the transport, so it shares the class rather than duplicating it.
@interface MSIMEHTTPVoiceRequest : NSObject
// Optional main-queue phase notification, snapshotted at request start.
@property(copy) void (^polishingHandler)(void);
- (instancetype)init NS_UNAVAILABLE;
+ (instancetype)new NS_UNAVAILABLE;
- (instancetype)initWithOptions:(NSDictionary *)options error:(NSError **)error;
// Text-only optional polishing; no ASR provider or audio credentials required.
- (instancetype)initWithPolishOptions:(NSDictionary *)options error:(NSError **)error;
- (BOOL)polishText:(NSString *)text completion:(void (^)(NSString *, NSError *))completion error:(NSError **)error;
// The most 16 kHz samples recognizePCM: submits: the 20 MiB batch upload budget MSIME-Windows uses, or the 60 s the Engine's Whisper worker accepts on device. The host ends the recording once it has captured this much, so nothing the user says after that point is silently left out.
@property(nonatomic, readonly) NSUInteger sampleLimit;
- (BOOL)recognizePCM:(NSData *)pcm completion:(void (^)(NSString *, NSError *))completion error:(NSError **)error;
- (void)cancel;
@end
