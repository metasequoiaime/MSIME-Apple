#pragma once
#import <Foundation/Foundation.h>
#import <CoreAudio/CoreAudio.h>
#import <AudioToolbox/AudioToolbox.h>
#include <vector>

// Keep device selection testable without enumerating or opening real hardware.
struct MSIMEVoiceCaptureDeviceAPI {
    decltype(&AudioObjectGetPropertyData) get = AudioObjectGetPropertyData;
    decltype(&AudioObjectGetPropertyDataSize) size = AudioObjectGetPropertyDataSize;
    decltype(&AudioUnitSetProperty) setUnit = AudioUnitSetProperty;
    decltype(&AudioUnitGetProperty) getUnit = AudioUnitGetProperty;
};

/// A stable CoreAudio capture-device identity suitable for preferences.  The
/// UID is intentionally kept separate from the display name: names can be
/// shared by two interfaces and can change when a device is renamed.
struct MSIMEVoiceCaptureDeviceInfo {
    NSString *uid;
    NSString *name;
    BOOL isDefault;
};

struct MSIMEVoiceCaptureDeviceListAPI {
    decltype(&AudioObjectGetPropertyData) get = AudioObjectGetPropertyData;
    decltype(&AudioObjectGetPropertyDataSize) size = AudioObjectGetPropertyDataSize;
};

/// Enumerate input-capable devices without opening them.  The first item is
/// always the current system default, followed by a deterministic name/UID
/// order so a popup does not jump when CoreAudio returns devices differently.
static inline NSArray<NSDictionary *> *MSIMEListVoiceCaptureDevices(
    const MSIMEVoiceCaptureDeviceListAPI &api = {}) {
    AudioObjectPropertyAddress devicesAddress = { kAudioHardwarePropertyDevices,
        kAudioObjectPropertyScopeGlobal, kAudioObjectPropertyElementMain };
    UInt32 bytes = 0;
    if (api.size(kAudioObjectSystemObject, &devicesAddress, 0, nullptr, &bytes) != noErr ||
        bytes == 0 || bytes % sizeof(AudioDeviceID) != 0) return @[];
    NSMutableArray<NSDictionary *> *devices = [NSMutableArray array];
    const NSUInteger count = bytes / sizeof(AudioDeviceID);
    std::vector<AudioDeviceID> ids(count);
    if (api.get(kAudioObjectSystemObject, &devicesAddress, 0, nullptr, &bytes, ids.data()) != noErr ||
        bytes != count * sizeof(AudioDeviceID)) return @[];

    AudioDeviceID defaultID = kAudioObjectUnknown;
    AudioObjectPropertyAddress defaultAddress = { kAudioHardwarePropertyDefaultInputDevice,
        kAudioObjectPropertyScopeGlobal, kAudioObjectPropertyElementMain };
    UInt32 defaultBytes = sizeof(defaultID);
    (void)api.get(kAudioObjectSystemObject, &defaultAddress, 0, nullptr, &defaultBytes, &defaultID);

    for (AudioDeviceID device : ids) {
        AudioObjectPropertyAddress streamsAddress = { kAudioDevicePropertyStreams,
            kAudioDevicePropertyScopeInput, kAudioObjectPropertyElementMain };
        UInt32 streamBytes = 0;
        if (api.size(device, &streamsAddress, 0, nullptr, &streamBytes) != noErr ||
            streamBytes < sizeof(AudioStreamID) || streamBytes % sizeof(AudioStreamID) != 0) continue;
        AudioObjectPropertyAddress uidAddress = { kAudioDevicePropertyDeviceUID,
            kAudioObjectPropertyScopeGlobal, kAudioObjectPropertyElementMain };
        CFStringRef uidValue = nullptr;
        UInt32 uidBytes = sizeof(uidValue);
        if (api.get(device, &uidAddress, 0, nullptr, &uidBytes, &uidValue) != noErr ||
            uidBytes != sizeof(uidValue) || !uidValue) continue;
        NSString *uid = [(__bridge NSString *)uidValue copy];
        if (!uid.length) continue;
        AudioObjectPropertyAddress nameAddress = { kAudioObjectPropertyName,
            kAudioObjectPropertyScopeGlobal, kAudioObjectPropertyElementMain };
        CFStringRef nameValue = nullptr;
        UInt32 nameBytes = sizeof(nameValue);
        NSString *name = nil;
        if (api.get(device, &nameAddress, 0, nullptr, &nameBytes, &nameValue) == noErr &&
            nameBytes == sizeof(nameValue) && nameValue) name = [(__bridge NSString *)nameValue copy];
        if (!name.length) name = @"未命名录音设备";
        [devices addObject:@{ @"uid": uid, @"name": name,
                              @"default": @(device == defaultID) }];
    }
    [devices sortUsingComparator:^NSComparisonResult(NSDictionary *left, NSDictionary *right) {
        BOOL leftDefault = [left[@"default"] boolValue], rightDefault = [right[@"default"] boolValue];
        if (leftDefault != rightDefault) return leftDefault ? NSOrderedAscending : NSOrderedDescending;
        NSComparisonResult name = [left[@"name"] localizedStandardCompare:right[@"name"]];
        return name == NSOrderedSame ? [left[@"uid"] compare:right[@"uid"]] : name;
    }];
    return devices;
}

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
