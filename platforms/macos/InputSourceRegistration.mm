#import "InputSourceRegistration.h"

#include <cstring>

bool MetasequoiaShouldRegisterInputSource(int argc, const char *argv[])
{
    return argc == 2 && argv != nullptr && argv[1] != nullptr && std::strcmp(argv[1], "--register-input-source") == 0;
}

OSStatus MetasequoiaRegisterInputSource(NSURL *bundleURL, MetasequoiaInputSourceRegistrar registrar)
{
    if (bundleURL == nil || registrar == nullptr)
    {
        return paramErr;
    }
    return registrar((__bridge CFURLRef)bundleURL);
}

OSStatus MetasequoiaRegisterAndEnableInputSources(NSURL *bundleURL, NSString *bundleIdentifier,
                                                  MetasequoiaInputSourceRegistrar registrar,
                                                  MetasequoiaInputSourceLister lister,
                                                  MetasequoiaInputSourcePropertyGetter propertyGetter,
                                                  MetasequoiaInputSourceEnabler enabler)
{
    if (bundleIdentifier.length == 0 || lister == nullptr || propertyGetter == nullptr || enabler == nullptr)
    {
        return paramErr;
    }
    OSStatus status = MetasequoiaRegisterInputSource(bundleURL, registrar);
    if (status != noErr)
    {
        return status;
    }

    NSDictionary *filter = @{
        (__bridge NSString *)kTISPropertyBundleID : bundleIdentifier,
        (__bridge NSString *)kTISPropertyInputSourceIsEnableCapable : @YES,
    };
    CFArrayRef sources = lister((__bridge CFDictionaryRef)filter, true);
    if (sources == nullptr || CFArrayGetCount(sources) == 0)
    {
        if (sources != nullptr)
        {
            CFRelease(sources);
        }
        return fnfErr;
    }

    bool enabledParent = false;
    CFIndex sourceCount = CFArrayGetCount(sources);
    for (CFIndex index = 0; index < sourceCount; ++index)
    {
        TISInputSourceRef source = (TISInputSourceRef)CFArrayGetValueAtIndex(sources, index);
        void *property = propertyGetter(source, kTISPropertyInputSourceID);
        if (property == nullptr || CFGetTypeID(property) != CFStringGetTypeID() ||
            ![(__bridge NSString *)property isEqualToString:bundleIdentifier])
        {
            continue;
        }
        status = enabler(source);
        if (status != noErr)
        {
            CFRelease(sources);
            return status;
        }
        enabledParent = true;
    }
    if (!enabledParent)
    {
        CFRelease(sources);
        return fnfErr;
    }

    for (CFIndex index = 0; index < sourceCount; ++index)
    {
        TISInputSourceRef source = (TISInputSourceRef)CFArrayGetValueAtIndex(sources, index);
        void *property = propertyGetter(source, kTISPropertyInputSourceID);
        if (property != nullptr && CFGetTypeID(property) == CFStringGetTypeID() &&
            [(__bridge NSString *)property isEqualToString:bundleIdentifier])
        {
            continue;
        }
        status = enabler(source);
        if (status != noErr)
        {
            CFRelease(sources);
            return status;
        }
    }
    CFRelease(sources);
    return noErr;
}
