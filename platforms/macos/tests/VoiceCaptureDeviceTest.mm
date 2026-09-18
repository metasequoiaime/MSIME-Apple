#import "../src/VoiceCaptureDevice.h"
#include <cassert>
#include <cstring>

namespace CaptureFixture {
int failure = 0;
NSUInteger propertyReads = 0, sizes = 0, sets = 0, reads = 0;
OSStatus Get(AudioObjectID object, const AudioObjectPropertyAddress *address,
    UInt32 qualifierSize, const void *qualifier, UInt32 *bytes, void *data) {
    ++propertyReads;
    assert(object == kAudioObjectSystemObject && address->mSelector == kAudioHardwarePropertyTranslateUIDToDevice);
    assert(qualifierSize == sizeof(CFStringRef) && *bytes == sizeof(AudioDeviceID));
    assert([(__bridge NSString *)*static_cast<const CFStringRef *>(qualifier) isEqual:@"synthetic-input"]);
    *static_cast<AudioDeviceID *>(data) = failure == 2 ? kAudioObjectUnknown : 42;
    if (failure == 3) *bytes = 0;
    return failure == 1 ? -1 : noErr;
}
OSStatus Size(AudioObjectID object, const AudioObjectPropertyAddress *address,
    UInt32 qualifierSize, const void *qualifier, UInt32 *bytes) {
    ++sizes;
    assert(object == 42 && address->mSelector == kAudioDevicePropertyStreams && address->mScope == kAudioDevicePropertyScopeInput);
    assert(!qualifierSize && !qualifier);
    *bytes = failure == 5 ? 0 : failure == 6 ? 1 : sizeof(AudioStreamID);
    return failure == 4 ? -1 : noErr;
}
OSStatus SetUnit(AudioUnit unit, AudioUnitPropertyID property, AudioUnitScope scope,
    AudioUnitElement element, const void *data, UInt32 bytes) {
    ++sets;
    assert(unit && property == kAudioOutputUnitProperty_CurrentDevice && scope == kAudioUnitScope_Global && !element);
    assert(bytes == sizeof(AudioDeviceID) && *static_cast<const AudioDeviceID *>(data) == 42);
    return failure == 7 ? -1 : noErr;
}
OSStatus GetUnit(AudioUnit unit, AudioUnitPropertyID property, AudioUnitScope scope,
    AudioUnitElement element, void *data, UInt32 *bytes) {
    ++reads;
    assert(unit && property == kAudioOutputUnitProperty_CurrentDevice && scope == kAudioUnitScope_Global && !element);
    assert(*bytes == sizeof(AudioDeviceID));
    *static_cast<AudioDeviceID *>(data) = failure == 9 ? 43 : 42;
    if (failure == 10) *bytes = 0;
    return failure == 8 ? -1 : noErr;
}
}

namespace ListFixture {
OSStatus Size(AudioObjectID object, const AudioObjectPropertyAddress *address,
    UInt32 qualifierSize, const void *qualifier, UInt32 *bytes) {
    assert(!qualifierSize && !qualifier);
    if (object == kAudioObjectSystemObject) {
        assert(address->mSelector == kAudioHardwarePropertyDevices);
        *bytes = 4 * sizeof(AudioDeviceID);
        return noErr;
    }
    assert(address->mSelector == kAudioDevicePropertyStreams);
    assert(address->mScope == kAudioDevicePropertyScopeInput);
    *bytes = object == 12 ? 0 : sizeof(AudioStreamID);
    return noErr;
}
OSStatus Get(AudioObjectID object, const AudioObjectPropertyAddress *address,
    UInt32 qualifierSize, const void *qualifier, UInt32 *bytes, void *data) {
    assert(!qualifierSize && !qualifier);
    if (object == kAudioObjectSystemObject && address->mSelector == kAudioHardwarePropertyDevices) {
        assert(*bytes == 4 * sizeof(AudioDeviceID));
        AudioDeviceID ids[] = {11, 12, 13, 14};
        std::memcpy(data, ids, sizeof(ids));
        return noErr;
    }
    if (object == kAudioObjectSystemObject && address->mSelector == kAudioHardwarePropertyDefaultInputDevice) {
        assert(*bytes == sizeof(AudioDeviceID));
        *static_cast<AudioDeviceID *>(data) = 13;
        return noErr;
    }
    if (address->mSelector == kAudioDevicePropertyDeviceUID) {
        if (object == 14) return -1;
        assert(*bytes == sizeof(CFStringRef));
        *static_cast<CFStringRef *>(data) = object == 11 ? CFSTR("uid-alpha") : CFSTR("uid-default");
        return noErr;
    }
    assert(address->mSelector == kAudioObjectPropertyName && *bytes == sizeof(CFStringRef));
    *static_cast<CFStringRef *>(data) = object == 11 ? CFSTR("Alpha Mic") : CFSTR("Zulu Mic");
    return noErr;
}
}
int main() {
    using namespace CaptureFixture;
    @autoreleasepool {
        MSIMEVoiceCaptureDeviceAPI api{Get, CaptureFixture::Size, SetUnit, GetUnit};
        AudioUnit unit = reinterpret_cast<AudioUnit>(1); // Never dereferenced.
        assert(MSIMEConfigureVoiceCaptureDevice(nil, nullptr, nil, api));
        assert(MSIMEConfigureVoiceCaptureDevice(@"", nullptr, nil, api));
        assert(!propertyReads && !sizes && !sets && !reads);
        NSError *error = nil;
        assert(!MSIMEConfigureVoiceCaptureDevice(@"synthetic-input", nullptr, &error, api));
        assert(error.code == 20 && !propertyReads);
        for (failure = 1; failure <= 10; ++failure) {
            propertyReads = sizes = sets = reads = 0; error = nil;
            assert(!MSIMEConfigureVoiceCaptureDevice(@"synthetic-input", unit, &error, api));
            assert(error && ![error.description containsString:@"synthetic-input"]);
            assert(propertyReads == 1 && sizes == (failure > 3 ? 1 : 0));
            assert(sets == (failure > 6 ? 1 : 0) && reads == (failure > 7 ? 1 : 0));
        }
        failure = 0; propertyReads = sizes = sets = reads = 0; error = nil;
        assert(MSIMEConfigureVoiceCaptureDevice(@"synthetic-input", unit, &error, api));
        assert(!error && propertyReads == 1 && sizes == 1 && sets == 1 && reads == 1);
        failure = 1;
        assert(!MSIMEConfigureVoiceCaptureDevice(@"synthetic-input", unit, nil, api));

        MSIMEVoiceCaptureDeviceListAPI listAPI{ListFixture::Get, ListFixture::Size};
        NSArray<NSDictionary *> *devices = MSIMEListVoiceCaptureDevices(listAPI);
        assert(devices.count == 2); // Output-only and missing-UID devices are omitted.
        assert([devices[0][@"uid"] isEqual:@"uid-default"]);
        assert([devices[0][@"name"] isEqual:@"Zulu Mic"]);
        assert([devices[0][@"default"] isEqual:@YES]);
        assert([devices[1][@"uid"] isEqual:@"uid-alpha"]);
        assert([devices[1][@"default"] isEqual:@NO]);
    }
}
