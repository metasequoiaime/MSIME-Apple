#include "../../../platforms/macos/VoiceCaptureDevice.h"

#include <cstddef>

extern "C" {
typedef void (*MSIMEVoiceCaptureDeviceCallback)(const char *uid, const char *name,
                                                bool is_default, void *context);

void msime_macos_list_voice_capture_devices(MSIMEVoiceCaptureDeviceCallback callback,
                                             void *context) {
    if (!callback) return;
    @autoreleasepool {
        for (NSDictionary *device in MSIMEListVoiceCaptureDevices()) {
            NSString *uid = device[@"uid"];
            NSString *name = device[@"name"];
            if (![uid isKindOfClass:NSString.class] ||
                ![name isKindOfClass:NSString.class] ||
                !uid.length || !name.length)
                continue;
            callback(uid.UTF8String, name.UTF8String,
                     [device[@"default"] boolValue], context);
        }
    }
}
}
