#pragma once
#import <AppKit/AppKit.h>
@class MSIMEDesktopInputSession;

@protocol MSIMEDesktopCloudClipboardProvider
- (NSProgress *)request:(NSDictionary *)request completion:(void (^)(NSDictionary *))completion;
@end

@interface MSIMEDesktopCloudClipboardSession : NSObject
- (instancetype)initWithProvider:(id<MSIMEDesktopCloudClipboardProvider>)provider;
@property(nonatomic, readonly, copy) NSDictionary<NSString *, NSString *> *launchEnvironment;
- (void)authorizePID:(pid_t)pid stillValid:(BOOL (^)(void))valid;
- (void)stop;
@end

void MSIMEOpenDesktopCloudClipboard(NSString *optionsPath, NSWorkspace *workspace, dispatch_block_t fallback);
void MSIMEOpenDesktopCloudClipboardWithInput(NSString *optionsPath, NSWorkspace *workspace,
    MSIMEDesktopInputSession *inputSession, dispatch_block_t fallback);
