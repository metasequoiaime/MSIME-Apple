#pragma once
#import <Foundation/Foundation.h>

// One request owns a frozen configuration and cancellation token. Completion is
// delivered on the main queue; cancellation suppresses delivery. No audio capture.
@interface MSIMEHTTPVoiceRequest : NSObject
// Optional main-queue phase notification, snapshotted at request start.
@property(copy) void (^polishingHandler)(void);
- (instancetype)init NS_UNAVAILABLE;
+ (instancetype)new NS_UNAVAILABLE;
- (instancetype)initWithOptions:(NSDictionary *)options error:(NSError **)error;
// Text-only optional polishing; no ASR provider or audio credentials required.
- (instancetype)initWithPolishOptions:(NSDictionary *)options error:(NSError **)error;
- (BOOL)polishText:(NSString *)text completion:(void (^)(NSString *, NSError *))completion error:(NSError **)error;
- (BOOL)recognizePCM:(NSData *)pcm completion:(void (^)(NSString *, NSError *))completion error:(NSError **)error;
- (void)cancel;
@end
