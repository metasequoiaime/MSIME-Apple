#pragma once

#import <Carbon/Carbon.h>
#import <Foundation/Foundation.h>

using MetasequoiaInputSourceRegistrar = OSStatus (*)(CFURLRef location);
using MetasequoiaInputSourceLister = CFArrayRef (*)(CFDictionaryRef properties, Boolean includeAllInstalled);
using MetasequoiaInputSourcePropertyGetter = void *(*)(TISInputSourceRef inputSource, CFStringRef propertyKey);
using MetasequoiaInputSourceEnabler = OSStatus (*)(TISInputSourceRef inputSource);

bool MetasequoiaShouldRegisterInputSource(int argc, const char *argv[]);
OSStatus MetasequoiaRegisterInputSource(NSURL *bundleURL, MetasequoiaInputSourceRegistrar registrar);
OSStatus MetasequoiaRegisterAndEnableInputSources(NSURL *bundleURL, NSString *bundleIdentifier,
                                                  MetasequoiaInputSourceRegistrar registrar,
                                                  MetasequoiaInputSourceLister lister,
                                                  MetasequoiaInputSourcePropertyGetter propertyGetter,
                                                  MetasequoiaInputSourceEnabler enabler);
