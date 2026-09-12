#import "InputSourceRegistration.h"
#include <cstring>

@implementation MSIMEInputSourceMonitor {
    NSNotificationCenter *_center;
    NSString *_identifier;
    MSIMEInputSourceCopier _copier;
    MSIMEInputSourcePropertyGetter _getter;
    void (^_action)(void);
}
- (instancetype)initWithCenter:(NSNotificationCenter *)center bundleIdentifier:(NSString *)identifier
                    copySource:(MSIMEInputSourceCopier)copier propertyGetter:(MSIMEInputSourcePropertyGetter)getter
                    switchedAway:(void (^)(void))action {
    self = [super init];
    if (self) {
        _center = center; _identifier = [identifier copy]; _copier = copier; _getter = getter; _action = [action copy];
        if (!center || !identifier.length || !copier || !getter || !action) return nil;
        NSString *name = (__bridge NSString *)kTISNotifySelectedKeyboardInputSourceChanged;
        if ([center isKindOfClass:NSDistributedNotificationCenter.class])
            [(NSDistributedNotificationCenter *)center addObserver:self selector:@selector(sourceChanged:) name:name object:nil suspensionBehavior:NSNotificationSuspensionBehaviorDeliverImmediately];
        else [center addObserver:self selector:@selector(sourceChanged:) name:name object:nil];
    }
    return self;
}
- (void)sourceChanged:(NSNotification *)notification {
    (void)notification;
    if (!NSThread.isMainThread) {
        __weak MSIMEInputSourceMonitor *weakSelf = self;
        dispatch_async(dispatch_get_main_queue(), ^{ [weakSelf sourceChanged:nil]; });
        return;
    }
    if (!_center) return;
    // Query current state on delivery; delayed notifications carry no authority.
    TISInputSourceRef source = _copier();
    if (!source) return;
    auto stringProperty = [&](CFStringRef key) -> NSString * {
        void *value = _getter(source, key);
        return value && CFGetTypeID(value) == CFStringGetTypeID() ? (__bridge NSString *)value : nil;
    };
    NSString *bundle = stringProperty(kTISPropertyBundleID);
    NSString *identifier = stringProperty(kTISPropertyInputSourceID);
    // Some keyboard layouts have no bundle identifier. A missing or malformed
    // source is unknown, not evidence that the user switched input methods.
    BOOL away = bundle.length ? ![bundle isEqual:_identifier] :
        (identifier.length && ![identifier isEqual:_identifier] &&
         ![identifier hasPrefix:[_identifier stringByAppendingString:@"."]]);
    CFRelease(source);
    if (away) _action();
}
- (void)stop { [_center removeObserver:self]; _center = nil; }
- (void)dealloc { [self stop]; }
@end

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
