#import "UpdateController.h"

#import <Sparkle/Sparkle.h>

// Sparkle needs an application bundle: a feed URL, a version, a code signature. Started anywhere else it reports the misconfiguration with a modal alert, which in an input method process means the user's typing stops behind a dialog they never asked for. Answer "no updates available from here" instead.
@interface MetasequoiaUnavailableUpdateDriver : NSObject <MetasequoiaUpdateDriver>
@end

@implementation MetasequoiaUnavailableUpdateDriver

- (BOOL)canCheckForUpdates
{
    return NO;
}

- (BOOL)automaticallyChecksForUpdates
{
    return NO;
}

- (void)checkForUpdates:(id)sender
{
    (void)sender;
}

@end

@interface MetasequoiaSparkleUpdateDriver : NSObject <MetasequoiaUpdateDriver>
@property(nonatomic, readonly) SPUStandardUpdaterController *updaterController;
@end

@implementation MetasequoiaSparkleUpdateDriver

- (instancetype)init
{
    self = [super init];
    if (self != nil)
    {
        _updaterController = [[SPUStandardUpdaterController alloc] initWithStartingUpdater:YES
                                                                           updaterDelegate:nil
                                                                        userDriverDelegate:nil];
    }
    return self;
}

- (BOOL)canCheckForUpdates
{
    return self.updaterController.updater.canCheckForUpdates;
}

- (BOOL)automaticallyChecksForUpdates
{
    return self.updaterController.updater.automaticallyChecksForUpdates;
}

- (void)checkForUpdates:(id)sender
{
    [self.updaterController checkForUpdates:sender];
}

@end

@interface MetasequoiaUpdateController ()
@property(nonatomic) id<MetasequoiaUpdateDriver> driver;
@property(nonatomic, copy) MetasequoiaUpdateActivationHandler activationHandler;
@end

@implementation MetasequoiaUpdateController

+ (instancetype)sharedController
{
    static MetasequoiaUpdateController *controller = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
      NSBundle *host = NSBundle.mainBundle;
      id<MetasequoiaUpdateDriver> driver =
          MSIMEUpdateHostCanStartSparkle(host.bundleIdentifier, host.bundlePath,
                                         [host objectForInfoDictionaryKey:@"SUFeedURL"])
              ? (id<MetasequoiaUpdateDriver>)[[MetasequoiaSparkleUpdateDriver alloc] init]
              : (id<MetasequoiaUpdateDriver>)[[MetasequoiaUnavailableUpdateDriver alloc] init];
      controller =
          [[MetasequoiaUpdateController alloc] initWithDriver:driver
                                            activationHandler:^{
                                              [NSApp setActivationPolicy:NSApplicationActivationPolicyAccessory];
                                              [NSApp activateIgnoringOtherApps:YES];
                                            }];
    });
    return controller;
}

- (instancetype)initWithDriver:(id<MetasequoiaUpdateDriver>)driver
             activationHandler:(MetasequoiaUpdateActivationHandler)activationHandler
{
    self = [super init];
    if (self != nil)
    {
        _driver = driver;
        _activationHandler = [activationHandler copy];
    }
    return self;
}

- (BOOL)canCheckForUpdates
{
    return self.driver.canCheckForUpdates;
}

- (BOOL)automaticallyChecksForUpdates
{
    return self.driver.automaticallyChecksForUpdates;
}

- (void)checkForUpdates:(id)sender
{
    self.activationHandler();
    [self.driver checkForUpdates:sender];
}

@end
