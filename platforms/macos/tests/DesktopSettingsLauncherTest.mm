#import "../DesktopSettingsLauncher.h"
#include <cassert>

@interface TestWorkspace : NSWorkspace
@property BOOL installed;
@property NSUInteger launches;
@property(strong) NSWorkspaceOpenConfiguration *configuration;
@property(copy) void (^completion)(NSRunningApplication *, NSError *);
@end

@implementation TestWorkspace
- (NSURL *)URLForApplicationWithBundleIdentifier:(NSString *)identifier {
    assert([identifier isEqualToString:@"app.msime.client.preview"]);
    return self.installed ? [NSURL fileURLWithPath:@"/synthetic/Settings.app"] : nil;
}
- (void)openApplicationAtURL:(NSURL *)url configuration:(NSWorkspaceOpenConfiguration *)configuration
          completionHandler:(void (^)(NSRunningApplication *, NSError *))completion {
    assert([url.path isEqualToString:@"/synthetic/Settings.app"]);
    self.launches++;
    self.configuration = configuration;
    self.completion = completion;
}
@end

int main() {
    @autoreleasepool {
        TestWorkspace *workspace = [TestWorkspace new];
        __block NSUInteger fallbacks = 0;
        dispatch_block_t fallback = ^{ assert(NSThread.isMainThread); ++fallbacks; };
        MSIMEOpenDesktopSettings(MSIMEDesktopSettingsPage::Appearance, workspace, fallback);
        assert(fallbacks == 1 && workspace.launches == 0);
        workspace.installed = YES;
        MSIMEOpenDesktopSettings(MSIMEDesktopSettingsPage::Appearance, workspace, fallback);
        assert([workspace.configuration.arguments isEqual:@[@"--route=settings:appearance"]]);
        assert(workspace.configuration.createsNewApplicationInstance);
        workspace.completion(NSRunningApplication.currentApplication, nil);
        assert(fallbacks == 1);
        MSIMEOpenDesktopSettings(MSIMEDesktopSettingsPage::Voice, workspace, fallback);
        assert([workspace.configuration.arguments isEqual:@[@"--route=settings:voice"]]);
        assert(workspace.launches == 2);
        auto completion = workspace.completion;
        dispatch_async(dispatch_get_global_queue(QOS_CLASS_DEFAULT, 0), ^{
            completion(nil, [NSError errorWithDomain:@"SyntheticLaunchFailure" code:1 userInfo:nil]);
        });
        NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:2];
        while (fallbacks < 2 && deadline.timeIntervalSinceNow > 0)
            [NSRunLoop.currentRunLoop runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.01]];
        assert(fallbacks == 2);
        MSIMEOpenDesktopRoute(@"settings:help", workspace, fallback);
        assert([workspace.configuration.arguments isEqual:@[@"--route=settings:help"]]);
        assert(workspace.launches == 3);
        for (NSArray *entry in @[@[@((int)MSIMEDesktopSettingsPage::Translation), @"--route=settings:input"],
                                 @[@((int)MSIMEDesktopSettingsPage::AI), @"--route=settings:ai"]]) {
            MSIMEOpenDesktopSettings((MSIMEDesktopSettingsPage)[entry[0] intValue], workspace, fallback);
            assert([workspace.configuration.arguments isEqual:@[entry[1]]]);
            assert(workspace.configuration.createsNewApplicationInstance);
            workspace.completion(NSRunningApplication.currentApplication, nil);
            assert(fallbacks == 2);
        }
        assert(workspace.launches == 5);
    }
}
