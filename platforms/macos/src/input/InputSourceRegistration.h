#pragma once
#import <AppKit/AppKit.h>
#import <Carbon/Carbon.h>
#import <Foundation/Foundation.h>

using MSIMEInputSourceRegistrar = OSStatus (*)(CFURLRef);
using MSIMEInputSourceLister = CFArrayRef (*)(CFDictionaryRef, Boolean);
using MSIMEInputSourcePropertyGetter = void *(*)(TISInputSourceRef, CFStringRef);
using MSIMEInputSourceEnabler = OSStatus (*)(TISInputSourceRef);
using MSIMEInputSourceCopier = TISInputSourceRef (*)(void);

@interface MSIMEInputSourceMonitor : NSObject
- (instancetype)initWithCenter:(NSNotificationCenter *)center bundleIdentifier:(NSString *)identifier
                    copySource:(MSIMEInputSourceCopier)copier propertyGetter:(MSIMEInputSourcePropertyGetter)getter
                    switchedAway:(void (^)(void))action;
- (void)stop;
@end

bool MSIMEShouldRegisterInputSource(int argc, const char *argv[]);
OSStatus MSIMERegisterInputSource(NSURL *bundleURL, MSIMEInputSourceRegistrar registrar);
OSStatus MSIMERegisterAndEnableInputSources(NSURL *bundleURL, NSString *bundleIdentifier,
                                            MSIMEInputSourceRegistrar registrar,
                                            MSIMEInputSourceLister lister,
                                            MSIMEInputSourcePropertyGetter propertyGetter,
                                            MSIMEInputSourceEnabler enabler);
/// Starts a separate non-activating helper instance of the current input method
/// to re-register its source. Completion is always delivered on the main thread.
void MSIMELaunchInputSourceReregistration(NSURL *bundleURL, NSWorkspace *workspace,
                                          void (^completion)(BOOL launched));
