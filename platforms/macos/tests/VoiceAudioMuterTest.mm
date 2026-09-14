#import "../VoiceAudioMuter.h"
#include <cassert>
#include <map>

namespace {
AudioDeviceID selected;
std::map<AudioDeviceID, UInt32> muted;
NSUInteger reads, writes;
BOOL failRead, failWrite, shortRead;
OSStatus Get(AudioObjectID object, const AudioObjectPropertyAddress *address,
    UInt32 qualifierSize, const void *qualifier, UInt32 *size, void *data) {
    assert(!qualifierSize && !qualifier && *size == sizeof(UInt32));
    ++reads;
    if (failRead) return kAudioHardwareUnspecifiedError;
    if (address->mSelector == kAudioHardwarePropertyDefaultOutputDevice) {
        assert(object == kAudioObjectSystemObject && address->mScope == kAudioObjectPropertyScopeGlobal);
        *static_cast<UInt32 *>(data) = selected;
    } else {
        assert(address->mSelector == kAudioDevicePropertyMute && address->mScope == kAudioDevicePropertyScopeOutput);
        *static_cast<UInt32 *>(data) = muted.at(object);
    }
    assert(address->mElement == kAudioObjectPropertyElementMain);
    if (shortRead) *size = 1;
    return noErr;
}
OSStatus Set(AudioObjectID object, const AudioObjectPropertyAddress *address,
    UInt32 qualifierSize, const void *qualifier, UInt32 size, const void *data) {
    assert(!qualifierSize && !qualifier && size == sizeof(UInt32));
    assert(address->mSelector == kAudioDevicePropertyMute && address->mScope == kAudioDevicePropertyScopeOutput);
    assert(address->mElement == kAudioObjectPropertyElementMain);
    ++writes;
    if (failWrite) return kAudioHardwareUnspecifiedError;
    muted.at(object) = *static_cast<const UInt32 *>(data);
    return noErr;
}
void Reset() {
    selected = 100; muted = {{100, 0}, {200, 0}};
    reads = writes = 0; failRead = failWrite = shortRead = NO;
}
}
int main() {
    @autoreleasepool {
        Reset();
        MSIMEVoiceAudioMuter *muter = [[MSIMEVoiceAudioMuter alloc] initWithAudioAPI:{Get, Set}];
        [muter restore]; assert(!reads && !writes);
        assert([muter mute:nil] && muted[100] == 1 && writes == 1);
        selected = 200;
        const NSUInteger beforeRepeat = reads;
        assert([muter mute:nil] && reads == beforeRepeat && writes == 1);
        [muter restore]; assert(muted[100] == 0 && muted[200] == 0 && writes == 2);
        [muter restore]; assert(writes == 2);
        selected = 100; muted[100] = 1;
        assert([muter mute:nil] && writes == 2);
        [muter restore]; assert(muted[100] == 1 && writes == 2);
        muted[100] = 0;
        assert([muter mute:nil]);
        muted[100] = 0;
        NSUInteger beforeRestore = writes;
        [muter restore]; assert(writes == beforeRestore);
        assert([muter mute:nil]);
        failWrite = YES;
        [muter restore]; assert(muted[100] == 1);
        selected = 200;
        assert([muter mute:nil] && muted[200] == 0);
        failWrite = NO;
        [muter restore]; assert(muted[100] == 0 && muted[200] == 0);
        selected = 100;
        assert([muter mute:nil]);
        failRead = YES; [muter restore]; assert(muted[100] == 1);
        failRead = NO; shortRead = YES; [muter restore]; assert(muted[100] == 1);
        shortRead = NO; [muter restore]; assert(muted[100] == 0);
        for (NSUInteger failure = 0; failure < 5; ++failure) {
            Reset();
            if (failure == 0) failRead = YES;
            if (failure == 1) selected = kAudioObjectUnknown;
            if (failure == 2) shortRead = YES;
            if (failure == 3) muted[100] = 2;
            if (failure == 4) failWrite = YES;
            NSError *error = nil;
            assert(![muter mute:&error] && error.code == 10);
            beforeRestore = writes;
            failRead = failWrite = shortRead = NO; selected = 100; muted[100] = 0;
            [muter restore]; assert(writes == beforeRestore);
            assert([muter mute:nil]); [muter restore]; assert(muted[100] == 0);
        }
        assert([muter mute:nil]);
        muter = nil;
        assert(muted[100] == 0);
    }
    return 0;
}
