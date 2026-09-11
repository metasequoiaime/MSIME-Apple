#pragma once

#import <AppKit/AppKit.h>

NS_ASSUME_NONNULL_BEGIN

@protocol MetasequoiaUpdateDriver <NSObject>
@property(nonatomic, readonly) BOOL canCheckForUpdates;
@property(nonatomic, readonly) BOOL automaticallyChecksForUpdates;
- (void)checkForUpdates:(nullable id)sender;
@end

typedef void (^MetasequoiaUpdateActivationHandler)(void);

@interface MetasequoiaUpdateController : NSObject
+ (instancetype)sharedController;
- (instancetype)initWithDriver:(id<MetasequoiaUpdateDriver>)driver
             activationHandler:(MetasequoiaUpdateActivationHandler)activationHandler;
@property(nonatomic, readonly) BOOL canCheckForUpdates;
@property(nonatomic, readonly) BOOL automaticallyChecksForUpdates;
- (void)checkForUpdates:(nullable id)sender;
@end

NS_ASSUME_NONNULL_END
