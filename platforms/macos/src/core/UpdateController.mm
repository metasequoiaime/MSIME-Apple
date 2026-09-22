#import "UpdateController.h"

#import <Sparkle/Sparkle.h>

static NSString *const MetasequoiaReleasePageURL = @"https://github.com/metasequoiaime/msime/releases";

// Sparkle needs an application bundle: a feed URL, a version, a code signature. Started anywhere else
// it reports the misconfiguration with a modal alert, which in an input method process means the user's
// typing stops behind a dialog they never asked for. Non-application processes therefore stay inert;
// application bundles without a feed use the explicit release-page driver below.
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

@interface MetasequoiaReleasePageUpdateDriver ()
@property(nonatomic, readonly) NSURL *releaseURL;
@property(nonatomic, copy, readonly) MetasequoiaUpdateReleaseConfirmation confirmation;
@property(nonatomic, copy, readonly) MetasequoiaUpdateReleaseOpener opener;
@property(nonatomic, copy, readonly) MetasequoiaUpdateReleaseFailure failure;
@end

@implementation MetasequoiaReleasePageUpdateDriver

- (instancetype)initWithReleaseURL:(NSURL *)releaseURL
                       confirmation:(MetasequoiaUpdateReleaseConfirmation)confirmation
                             opener:(MetasequoiaUpdateReleaseOpener)opener
                            failure:(MetasequoiaUpdateReleaseFailure)failure
{
    self = [super init];
    if (self != nil)
    {
        _releaseURL = releaseURL;
        _confirmation = [confirmation copy];
        _opener = [opener copy];
        _failure = [failure copy];
        if (!releaseURL || !confirmation || !opener || !failure) return nil;
    }
    return self;
}

- (BOOL)canCheckForUpdates { return YES; }
- (BOOL)automaticallyChecksForUpdates { return NO; }

- (void)checkForUpdates:(id)sender
{
    (void)sender;
    if (self.confirmation(self.releaseURL) != NSAlertFirstButtonReturn) return;
    if (!self.opener(self.releaseURL)) self.failure();
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
      MetasequoiaUpdateRoute route = MSIMEUpdateRouteForHost(
          host.bundleIdentifier, host.bundlePath, [host objectForInfoDictionaryKey:@"SUFeedURL"]);
      id<MetasequoiaUpdateDriver> driver = nil;
      if (route == MetasequoiaUpdateRouteSparkle)
      {
          driver = [[MetasequoiaSparkleUpdateDriver alloc] init];
      }
      else if (route == MetasequoiaUpdateRouteReleasePage)
      {
          NSURL *releaseURL = [NSURL URLWithString:MetasequoiaReleasePageURL];
          driver = [[MetasequoiaReleasePageUpdateDriver alloc]
              initWithReleaseURL:releaseURL
                   confirmation:^NSModalResponse(NSURL *url) {
                     (void)url;
                     NSAlert *alert = [NSAlert new];
                     alert.messageText = @"此构建未配置应用内更新";
                     alert.informativeText = @"无法使用 Sparkle 自动检查。可以前往水杉输入法的官方发布页查看可用版本。";
                     [alert addButtonWithTitle:@"前往发布页"];
                     [alert addButtonWithTitle:@"取消"];
                     return [alert runModal];
                   }
                         opener:^BOOL(NSURL *url) {
                           return [NSWorkspace.sharedWorkspace openURL:url];
                         }
                        failure:^{
                          NSAlert *alert = [NSAlert new];
                          alert.alertStyle = NSAlertStyleCritical;
                          alert.messageText = @"无法打开发布页";
                          alert.informativeText = @"请稍后重试，或在浏览器中访问 github.com/metasequoiaime/msime/releases。";
                          [alert runModal];
                        }];
      }
      else
      {
          driver = [[MetasequoiaUnavailableUpdateDriver alloc] init];
      }
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
