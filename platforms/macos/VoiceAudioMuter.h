#pragma once
#import <Foundation/Foundation.h>
#ifdef __cplusplus
#import <CoreAudio/CoreAudio.h>
struct MSIMEVoiceAudioAPI {
    decltype(&AudioObjectGetPropertyData) get = AudioObjectGetPropertyData;
    decltype(&AudioObjectSetPropertyData) set = AudioObjectSetPropertyData;
};
#endif
@interface MSIMEVoiceAudioMuter : NSObject
// Main-thread lifecycle. Injection keeps tests away from real output devices.
#ifdef __cplusplus
- (instancetype)initWithAudioAPI:(MSIMEVoiceAudioAPI)api;
// nil keeps injected tests entirely in memory. Production uses a private directory.
- (instancetype)initWithAudioAPI:(MSIMEVoiceAudioAPI)api recoveryDirectory:(NSURL *)directory;
#endif
- (BOOL)mute:(NSError **)error;
- (void)restore;
@end
