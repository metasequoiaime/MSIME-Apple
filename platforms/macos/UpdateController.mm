#import "UpdateController.h"

@implementation MSIMEUpdateController
+ (instancetype)sharedController {
    static MSIMEUpdateController *controller;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ controller = [self new]; });
    return controller;
}
- (BOOL)canCheckForUpdates { return YES; }
- (void)checkForUpdates:(id)sender {
    (void)sender;
    [[NSWorkspace sharedWorkspace] openURL:[NSURL URLWithString:@"https://github.com/metasequoiaime/MSIME-Client/releases"]];
}
@end
