#pragma once
#import <Carbon/Carbon.h>
#import <Foundation/Foundation.h>

using MSIMEInputSourceRegistrar = OSStatus (*)(CFURLRef);
using MSIMEInputSourceLister = CFArrayRef (*)(CFDictionaryRef, Boolean);
using MSIMEInputSourcePropertyGetter = void *(*)(TISInputSourceRef, CFStringRef);
using MSIMEInputSourceEnabler = OSStatus (*)(TISInputSourceRef);

bool MSIMEShouldRegisterInputSource(int argc, const char *argv[]);
OSStatus MSIMERegisterInputSource(NSURL *bundleURL, MSIMEInputSourceRegistrar registrar);
OSStatus MSIMERegisterAndEnableInputSources(NSURL *bundleURL, NSString *bundleIdentifier,
                                            MSIMEInputSourceRegistrar registrar,
                                            MSIMEInputSourceLister lister,
                                            MSIMEInputSourcePropertyGetter propertyGetter,
                                            MSIMEInputSourceEnabler enabler);
