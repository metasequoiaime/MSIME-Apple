#import "../InputSourceRegistration.h"

#include <stdexcept>
#include <vector>

@interface RegistrationWorkspace : NSWorkspace
@property(nonatomic) NSUInteger launches;
@property(nonatomic, strong) NSURL *launchedURL;
@property(nonatomic, strong) NSWorkspaceOpenConfiguration *configuration;
@property(nonatomic, copy) void (^completion)(NSRunningApplication *, NSError *);
@end

@implementation RegistrationWorkspace
- (void)openApplicationAtURL:(NSURL *)url configuration:(NSWorkspaceOpenConfiguration *)configuration
           completionHandler:(void (^)(NSRunningApplication *, NSError *))completion {
    ++self.launches;
    self.launchedURL = url;
    self.configuration = configuration;
    self.completion = completion;
}
@end

namespace
{
NSURL *registeredURL = nil;
CFArrayRef sourceList = nullptr;
NSString *listedBundleIdentifier = nil;
Boolean includedAllInstalled = false;
BOOL enableCapableOnly = NO;
std::vector<TISInputSourceRef> enabledSources;
TISInputSourceRef rejectedSource = nullptr;
TISInputSourceRef parentSource = reinterpret_cast<TISInputSourceRef>(0x101);
TISInputSourceRef modeSource = reinterpret_cast<TISInputSourceRef>(0x102);

void require(bool condition, const char *message)
{
    if (!condition)
    {
        throw std::runtime_error(message);
    }
}

OSStatus CaptureRegistration(CFURLRef location)
{
    registeredURL = (__bridge NSURL *)location;
    return noErr;
}

OSStatus RejectRegistration(CFURLRef location)
{
    (void)location;
    return -50;
}

CFArrayRef CopyInputSources(CFDictionaryRef properties, Boolean includeAllInstalled)
{
    NSDictionary *filter = (__bridge NSDictionary *)properties;
    listedBundleIdentifier = filter[(__bridge NSString *)kTISPropertyBundleID];
    enableCapableOnly = [filter[(__bridge NSString *)kTISPropertyInputSourceIsEnableCapable] boolValue];
    includedAllInstalled = includeAllInstalled;
    return sourceList == nullptr ? nullptr : (CFArrayRef)CFRetain(sourceList);
}

void *GetInputSourceProperty(TISInputSourceRef inputSource, CFStringRef propertyKey)
{
    if (propertyKey != kTISPropertyInputSourceID)
    {
        return nullptr;
    }
    CFStringRef identifier = inputSource == parentSource ? CFSTR("com.houko.inputmethod.MetasequoiaIME")
                                                         : CFSTR("com.houko.inputmethod.MetasequoiaIME.Hans");
    return const_cast<void *>(reinterpret_cast<const void *>(identifier));
}

OSStatus EnableInputSource(TISInputSourceRef inputSource)
{
    enabledSources.push_back(inputSource);
    return inputSource == rejectedSource ? -50 : noErr;
}
} // namespace

int main()
{
    @autoreleasepool
    {
        const char *registrationArguments[] = {"MetasequoiaIME", "--register-input-source"};
        const char *ordinaryArguments[] = {"MetasequoiaIME"};
        const char *unknownArguments[] = {"MetasequoiaIME", "--unknown"};
        require(MSIMEShouldRegisterInputSource(2, registrationArguments),
                "The registration command was not recognized.");
        const char *reregistrationArguments[] = {"MetasequoiaIME", "--reregister-input-source"};
        require(MSIMEShouldRegisterInputSource(2, reregistrationArguments),
                "The re-registration command was not recognized.");
        require(!MSIMEShouldRegisterInputSource(1, ordinaryArguments),
                "Ordinary InputMethodKit startup was treated as registration.");
        require(!MSIMEShouldRegisterInputSource(2, unknownArguments),
                "An unknown command was treated as registration.");

        NSURL *bundleURL = [NSURL fileURLWithPath:@"/tmp/MetasequoiaIME.app" isDirectory:YES];
        RegistrationWorkspace *workspace = [RegistrationWorkspace new];
        __block BOOL launchCompleted = NO;
        __block BOOL launchSucceeded = NO;
        MSIMELaunchInputSourceReregistration(bundleURL, workspace, ^(BOOL launched) {
            launchCompleted = YES;
            launchSucceeded = launched;
        });
        require(workspace.launches == 1 && [workspace.launchedURL isEqual:bundleURL],
                "Re-registration did not launch the current input method bundle.");
        require([workspace.configuration.arguments isEqual:@[@"--reregister-input-source"]] &&
                    !workspace.configuration.activates && workspace.configuration.createsNewApplicationInstance,
                "Re-registration used the wrong launch policy.");
        workspace.completion(NSRunningApplication.currentApplication, nil);
        require(launchCompleted && launchSucceeded, "A successful re-registration launch was not reported.");
        launchCompleted = NO;
        launchSucceeded = YES;
        workspace.completion(nil, [NSError errorWithDomain:@"SyntheticLaunchFailure" code:1 userInfo:nil]);
        require(launchCompleted && !launchSucceeded, "A failed re-registration launch was accepted.");
        launchCompleted = NO;
        MSIMELaunchInputSourceReregistration([NSURL URLWithString:@"https://invalid.example"], workspace,
                                             ^(BOOL launched) { launchCompleted = !launched; });
        require(launchCompleted && workspace.launches == 1, "A non-file bundle URL was launched.");

        require(MSIMERegisterInputSource(bundleURL, CaptureRegistration) == noErr,
                "A successful registration callback was reported as failed.");
        require([registeredURL isEqual:bundleURL], "Registration did not receive the installed bundle URL.");
        require(MSIMERegisterInputSource(bundleURL, RejectRegistration) == -50,
                "A registration callback failure was not preserved.");
        require(MSIMERegisterInputSource(nil, CaptureRegistration) == paramErr,
                "A missing bundle URL was accepted.");
        require(MSIMERegisterInputSource(bundleURL, nullptr) == paramErr,
                "A missing registration callback was accepted.");

        const void *sources[] = {parentSource, modeSource};
        sourceList = CFArrayCreate(nullptr, sources, 2, nullptr);
        NSString *bundleIdentifier = @"com.houko.inputmethod.MetasequoiaIME";
        require(MSIMERegisterAndEnableInputSources(bundleURL, bundleIdentifier, CaptureRegistration,
                                                         CopyInputSources, GetInputSourceProperty,
                                                         EnableInputSource) == noErr,
                "A registered input method was not enabled.");
        require([listedBundleIdentifier isEqualToString:bundleIdentifier] && enableCapableOnly && includedAllInstalled,
                "Input source discovery did not use the registered bundle identifier.");
        require(enabledSources.size() == 2 && enabledSources[0] == parentSource && enabledSources[1] == modeSource,
                "The parent input method was not enabled before its input mode.");

        enabledSources.clear();
        rejectedSource = modeSource;
        require(MSIMERegisterAndEnableInputSources(bundleURL, bundleIdentifier, CaptureRegistration,
                                                         CopyInputSources, GetInputSourceProperty,
                                                         EnableInputSource) == -50,
                "An input source enable failure was not preserved.");
        rejectedSource = nullptr;

        CFRelease(sourceList);
        sourceList = CFArrayCreate(nullptr, nullptr, 0, nullptr);
        require(MSIMERegisterAndEnableInputSources(bundleURL, bundleIdentifier, CaptureRegistration,
                                                         CopyInputSources, GetInputSourceProperty,
                                                         EnableInputSource) == fnfErr,
                "A registration with no discoverable input sources was accepted.");
        CFRelease(sourceList);
        sourceList = nullptr;

        const void *modeOnlySources[] = {modeSource};
        sourceList = CFArrayCreate(nullptr, modeOnlySources, 1, nullptr);
        enabledSources.clear();
        require(MSIMERegisterAndEnableInputSources(bundleURL, bundleIdentifier, CaptureRegistration,
                                                         CopyInputSources, GetInputSourceProperty,
                                                         EnableInputSource) == fnfErr,
                "An input mode without its enabled parent was accepted.");
        require(enabledSources.empty(), "An input mode was enabled before its parent was found.");
        CFRelease(sourceList);
        sourceList = nullptr;

        require(MSIMERegisterAndEnableInputSources(bundleURL, bundleIdentifier, RejectRegistration,
                                                         CopyInputSources, GetInputSourceProperty,
                                                         EnableInputSource) == -50,
                "A registration failure was not returned before discovery.");
        require(MSIMERegisterAndEnableInputSources(bundleURL, nil, CaptureRegistration, CopyInputSources,
                                                         GetInputSourceProperty, EnableInputSource) == paramErr,
                "A missing bundle identifier was accepted.");
        require(MSIMERegisterAndEnableInputSources(bundleURL, bundleIdentifier, CaptureRegistration, nullptr,
                                                         GetInputSourceProperty, EnableInputSource) == paramErr,
                "A missing input source lister was accepted.");
    }
    return 0;
}
