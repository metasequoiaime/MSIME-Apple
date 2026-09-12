#import <AppKit/AppKit.h>
#import <InputMethodKit/InputMethodKit.h>

#import "InputSourceRegistration.h"
#import "PreferencesWindowController.h"
#import "UpdateController.h"
#import "CandidateAppearancePreferences.h"
#import "InputBehaviorPreferences.h"

#include <cstdio>

int main(int argc, const char *argv[])
{
    @autoreleasepool
    {
        if (MetasequoiaShouldRegisterInputSource(argc, argv))
        {
            NSURL *bundleURL = NSBundle.mainBundle.bundleURL;
            NSString *bundleIdentifier = NSBundle.mainBundle.bundleIdentifier;
            OSStatus status = MetasequoiaRegisterAndEnableInputSources(bundleURL, bundleIdentifier,
                                                                       TISRegisterInputSource, TISCreateInputSourceList,
                                                                       TISGetInputSourceProperty, TISEnableInputSource);
            if (status != noErr)
            {
                std::fprintf(stderr, "Input source registration or enable failed with OSStatus %d.\n", status);
                return 1;
            }
            std::fprintf(stdout, "Registered and enabled %s\n", bundleURL.fileSystemRepresentation);
            return 0;
        }

        NSApplication *application = [NSApplication sharedApplication];
        application.appearance = MetasequoiaForcedAppearance();
        void (^appearanceChanged)(NSNotification *) = ^(NSNotification *notification) {
          (void)notification;
          [NSUserDefaults.standardUserDefaults synchronize];
          application.appearance = MetasequoiaForcedAppearance();
        };
        id localAppearanceObserver =
            [NSNotificationCenter.defaultCenter addObserverForName:MetasequoiaAppearanceDidChange
                                                            object:nil
                                                             queue:NSOperationQueue.mainQueue
                                                        usingBlock:appearanceChanged];
        id distributedAppearanceObserver =
            [NSDistributedNotificationCenter.defaultCenter addObserverForName:MetasequoiaAppearanceDidChange
                                                                       object:nil
                                                                        queue:NSOperationQueue.mainQueue
                                                                   usingBlock:appearanceChanged];
        [application setActivationPolicy:NSApplicationActivationPolicyAccessory];
        if (MetasequoiaShouldShowPreferences(argc, argv))
        {
            id closeObserver = [[NSNotificationCenter defaultCenter]
                addObserverForName:MetasequoiaStandalonePreferencesDidCloseNotification
                            object:nil
                             queue:NSOperationQueue.mainQueue
                        usingBlock:^(NSNotification *notification) {
                          (void)notification;
                          [application terminate:nil];
                        }];
            [[MetasequoiaPreferencesWindowController sharedController] showAndActivateForStandaloneLaunch];
            [application run];
            [[NSNotificationCenter defaultCenter] removeObserver:closeObserver];
            [NSNotificationCenter.defaultCenter removeObserver:localAppearanceObserver];
            [NSDistributedNotificationCenter.defaultCenter removeObserver:distributedAppearanceObserver];
            return 0;
        }

        if (MetasequoiaInputBehavior()[@"defaultEnglish"] != nil)
            [MetasequoiaPreferencesWindowController
                setEnglishInputMode:MetasequoiaInputInteger(@"defaultEnglish", 0, 0, 1) != 0];
        NSBundle *bundle = [NSBundle mainBundle];
        NSString *connectionName = [bundle objectForInfoDictionaryKey:@"InputMethodConnectionName"];
        NSString *bundleIdentifier = bundle.bundleIdentifier;
        IMKServer *server = [[IMKServer alloc] initWithName:connectionName bundleIdentifier:bundleIdentifier];
        if (server == nil)
        {
            NSLog(@"Failed to initialize the Metasequoia InputMethodKit server.");
            return 1;
        }
        (void)[MetasequoiaUpdateController sharedController];
        [application run];
        [NSNotificationCenter.defaultCenter removeObserver:localAppearanceObserver];
        [NSDistributedNotificationCenter.defaultCenter removeObserver:distributedAppearanceObserver];
        (void)server;
    }
    return 0;
}
