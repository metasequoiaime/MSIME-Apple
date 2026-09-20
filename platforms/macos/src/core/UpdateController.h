#pragma once

#import <AppKit/AppKit.h>

NS_ASSUME_NONNULL_BEGIN

@protocol MetasequoiaUpdateDriver <NSObject>
@property(nonatomic, readonly) BOOL canCheckForUpdates;
@property(nonatomic, readonly) BOOL automaticallyChecksForUpdates;
- (void)checkForUpdates:(nullable id)sender;
@end

typedef void (^MetasequoiaUpdateActivationHandler)(void);

// Whether Sparkle can be started in this process at all. It needs an application bundle - a feed URL, a
// version, a code signature - and started anywhere else it reports the misconfiguration with a modal
// alert, which in an input method means the user's typing stops behind a dialog they never asked for.
// A pure function so the decision can be tested without starting an updater.
static inline BOOL MSIMEUpdateHostCanStartSparkle(NSString *_Nullable identifier, NSString *_Nullable path,
                                                  NSString *_Nullable feedURL)
{
    return identifier.length > 0 && [path.pathExtension isEqualToString:@"app"] && feedURL.length > 0;
}

@interface MetasequoiaUpdateController : NSObject
+ (instancetype)sharedController;
- (instancetype)initWithDriver:(id<MetasequoiaUpdateDriver>)driver
             activationHandler:(MetasequoiaUpdateActivationHandler)activationHandler;
@property(nonatomic, readonly) BOOL canCheckForUpdates;
@property(nonatomic, readonly) BOOL automaticallyChecksForUpdates;
- (void)checkForUpdates:(nullable id)sender;
@end
#define MSIMEUpdateController MetasequoiaUpdateController

NS_ASSUME_NONNULL_END
