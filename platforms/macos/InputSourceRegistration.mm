#import "InputSourceRegistration.h"
#include <cstring>

bool MSIMEShouldRegisterInputSource(int argc, const char *argv[]) {
    return argc == 2 && argv && argv[1] && std::strcmp(argv[1], "--register-input-source") == 0;
}

OSStatus MSIMERegisterInputSource(NSURL *bundleURL, MSIMEInputSourceRegistrar registrar) {
    if (!bundleURL || !registrar) return paramErr;
    return registrar((__bridge CFURLRef)bundleURL);
}

OSStatus MSIMERegisterAndEnableInputSources(NSURL *bundleURL, NSString *bundleIdentifier,
                                            MSIMEInputSourceRegistrar registrar,
                                            MSIMEInputSourceLister lister,
                                            MSIMEInputSourcePropertyGetter propertyGetter,
                                            MSIMEInputSourceEnabler enabler) {
    if (!bundleIdentifier.length || !lister || !propertyGetter || !enabler) return paramErr;
    OSStatus status = MSIMERegisterInputSource(bundleURL, registrar);
    if (status != noErr) return status;
    NSDictionary *filter = @{(__bridge NSString *)kTISPropertyBundleID: bundleIdentifier,
                             (__bridge NSString *)kTISPropertyInputSourceIsEnableCapable: @YES};
    CFArrayRef sources = lister((__bridge CFDictionaryRef)filter, true);
    if (!sources || CFArrayGetCount(sources) == 0) { if (sources) CFRelease(sources); return fnfErr; }
    bool enabled = false;
    for (CFIndex i = 0; i < CFArrayGetCount(sources); ++i) {
        TISInputSourceRef source = (TISInputSourceRef)CFArrayGetValueAtIndex(sources, i);
        void *property = propertyGetter(source, kTISPropertyInputSourceID);
        if (property && CFGetTypeID(property) == CFStringGetTypeID() &&
            [(__bridge NSString *)property isEqualToString:bundleIdentifier]) {
            status = enabler(source); if (status != noErr) { CFRelease(sources); return status; } enabled = true;
        }
    }
    if (!enabled) { CFRelease(sources); return fnfErr; }
    for (CFIndex i = 0; i < CFArrayGetCount(sources); ++i) {
        TISInputSourceRef source = (TISInputSourceRef)CFArrayGetValueAtIndex(sources, i);
        void *property = propertyGetter(source, kTISPropertyInputSourceID);
        if (!property || CFGetTypeID(property) != CFStringGetTypeID() ||
            ![(__bridge NSString *)property isEqualToString:bundleIdentifier]) {
            status = enabler(source); if (status != noErr) { CFRelease(sources); return status; }
        }
    }
    CFRelease(sources); return noErr;
}
