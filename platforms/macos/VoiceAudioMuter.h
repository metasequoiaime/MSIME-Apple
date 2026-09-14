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
#endif
- (BOOL)mute:(NSError **)error;
- (void)restore;
@end
