#pragma once
#import <AppKit/AppKit.h>

typedef void (^MSIMEPanelTextCompletion)(BOOL committed);
typedef void (^MSIMEPanelTextHandler)(NSString *text, double deadline, MSIMEPanelTextCompletion completion);

// One menu presentation, one confirmed submission. Never persists input.
@interface MSIMEDesktopInputSession : NSObject
- (instancetype)initWithTargetPID:(pid_t)pid launchTime:(double)launched handler:(MSIMEPanelTextHandler)handler;
@property(nonatomic, readonly, copy) NSDictionary<NSString *, NSString *> *launchEnvironment;
- (void)authorizePID:(pid_t)pid stillValid:(BOOL (^)(void))valid;
- (BOOL)isAuthorizedPeerAlive;
- (void)stop;
@end
