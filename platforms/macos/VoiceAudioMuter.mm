#import "VoiceAudioMuter.h"
@implementation MSIMEVoiceAudioMuter {
    MSIMEVoiceAudioAPI _api;
    NSString *_deviceUID;
    UInt32 _old;
    BOOL _changed;
}
- (instancetype)init { return [self initWithAudioAPI:{}]; }
- (instancetype)initWithAudioAPI:(MSIMEVoiceAudioAPI)api {
    self = [super init];
    if (self) _api = api;
    return self;
}
- (NSString *)deviceUID:(AudioDeviceID)device {
    AudioObjectPropertyAddress address = {kAudioDevicePropertyDeviceUID,
        kAudioObjectPropertyScopeGlobal, kAudioObjectPropertyElementMain};
    CFStringRef value = nullptr;
    UInt32 bytes = sizeof(value);
    OSStatus status = _api.get(device, &address, 0, nullptr, &bytes, &value);
    id result = CFBridgingRelease(value);
    if (status != noErr || bytes != sizeof(value) || ![result isKindOfClass:NSString.class] ||
        ![result length] || [result length] > 4096) return nil;
    return [result copy];
}
- (BOOL)mute:(NSError **)error {
    // Repeated starts must not replace the original device or mute snapshot.
    if (_changed) return YES;
    auto fail = [&] {
        if (error) *error = [NSError errorWithDomain:@"app.msime.client.voice" code:10
            userInfo:@{NSLocalizedDescriptionKey:@"无法静音系统音频"}];
        return NO;
    };
    AudioDeviceID device = kAudioObjectUnknown;
    AudioObjectPropertyAddress address = {kAudioHardwarePropertyDefaultOutputDevice,
        kAudioObjectPropertyScopeGlobal, kAudioObjectPropertyElementMain};
    UInt32 bytes = sizeof(device);
    if (!_api.get || !_api.set ||
        _api.get(kAudioObjectSystemObject, &address, 0, nullptr, &bytes, &device) != noErr ||
        bytes != sizeof(device) || device == kAudioObjectUnknown) return fail();
    address = {kAudioDevicePropertyMute, kAudioDevicePropertyScopeOutput, kAudioObjectPropertyElementMain};
    UInt32 previous = 0;
    bytes = sizeof(previous);
    if (_api.get(device, &address, 0, nullptr, &bytes, &previous) != noErr ||
        bytes != sizeof(previous) || previous > 1) return fail();
    // Do not take ownership of a mute that was already enabled by the user.
    if (previous) return YES;
    NSString *uid = [self deviceUID:device];
    if (!uid) return fail();
    UInt32 muted = 1;
    if (_api.set(device, &address, 0, nullptr, sizeof(muted), &muted) != noErr) return fail();
    _deviceUID = uid; _old = previous; _changed = YES;
    return YES;
}
- (void)restore {
    if (!_changed) return;
    // Numeric IDs can be reused after disconnect. Resolve only the owned UID.
    AudioObjectPropertyAddress address = {kAudioHardwarePropertyTranslateUIDToDevice,
        kAudioObjectPropertyScopeGlobal, kAudioObjectPropertyElementMain};
    CFStringRef uid = (__bridge CFStringRef)_deviceUID;
    AudioDeviceID device = kAudioObjectUnknown;
    UInt32 bytes = sizeof(device);
    if (_api.get(kAudioObjectSystemObject, &address, sizeof(uid), &uid, &bytes, &device) != noErr ||
        bytes != sizeof(device) || device == kAudioObjectUnknown ||
        ![[self deviceUID:device] isEqual:_deviceUID]) return;
    address = {kAudioDevicePropertyMute,
        kAudioObjectPropertyScopeOutput, kAudioObjectPropertyElementMain};
    UInt32 current = 0;
    bytes = sizeof(current);
    if (_api.get(device, &address, 0, nullptr, &bytes, &current) != noErr ||
        bytes != sizeof(current) || current > 1) return;
    // The user may already have unmuted it. Never resolve the new default here.
    if (current != _old && _api.set(device, &address, 0, nullptr, sizeof(_old), &_old) != noErr) return;
    // Failed reads/writes retain the original snapshot for the next cleanup.
    _changed = NO; _deviceUID = nil;
}
- (void)dealloc { [self restore]; }
@end
