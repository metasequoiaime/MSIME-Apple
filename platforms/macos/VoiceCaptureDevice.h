#pragma once
#import <Foundation/Foundation.h>
#import <CoreAudio/CoreAudio.h>
#import <AudioToolbox/AudioToolbox.h>

// Keep device selection testable without enumerating or opening real hardware.
struct MSIMEVoiceCaptureDeviceAPI {
    decltype(&AudioObjectGetPropertyData) get = AudioObjectGetPropertyData;
    decltype(&AudioObjectGetPropertyDataSize) size = AudioObjectGetPropertyDataSize;
    decltype(&AudioUnitSetProperty) setUnit = AudioUnitSetProperty;
    decltype(&AudioUnitGetProperty) getUnit = AudioUnitGetProperty;
};

static inline BOOL MSIMEConfigureVoiceCaptureDevice(NSString *uid, AudioUnit unit,
    NSError **error, const MSIMEVoiceCaptureDeviceAPI &api = {}) {
    // Only the absence of an explicit selection opts into the system default.
    if (!uid.length) return YES;
    auto fail = [&](NSInteger code) {
        if (error) *error = [NSError errorWithDomain:@"app.msime.client.voice" code:code
            userInfo:@{NSLocalizedDescriptionKey:@"所选麦克风不可用，请重新选择录音设备"}];
        return NO;
    };
    if (!unit) return fail(20);
    AudioObjectPropertyAddress address = { kAudioHardwarePropertyTranslateUIDToDevice,
        kAudioObjectPropertyScopeGlobal, kAudioObjectPropertyElementMain };
    CFStringRef requested = (__bridge CFStringRef)uid;
    AudioDeviceID device = kAudioObjectUnknown;
    UInt32 bytes = sizeof(device);
    if (api.get(kAudioObjectSystemObject, &address, sizeof(requested), &requested, &bytes, &device) != noErr ||
        bytes != sizeof(device) || device == kAudioObjectUnknown) return fail(21);
    // Reject output-only devices before touching the input audio unit.
    address = { kAudioDevicePropertyStreams, kAudioDevicePropertyScopeInput, kAudioObjectPropertyElementMain };
    bytes = 0;
    if (api.size(device, &address, 0, nullptr, &bytes) != noErr ||
        bytes < sizeof(AudioStreamID) || bytes % sizeof(AudioStreamID)) return fail(22);
    if (api.setUnit(unit, kAudioOutputUnitProperty_CurrentDevice, kAudioUnitScope_Global,
        0, &device, sizeof(device)) != noErr) return fail(23);
    AudioDeviceID actual = kAudioObjectUnknown;
    bytes = sizeof(actual);
    if (api.getUnit(unit, kAudioOutputUnitProperty_CurrentDevice, kAudioUnitScope_Global,
        0, &actual, &bytes) != noErr || bytes != sizeof(actual) || actual != device) return fail(24);
    return YES;
}
