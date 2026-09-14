#pragma once

#import <AppKit/AppKit.h>

enum class MSIMEDesktopSettingsPage { Appearance, Voice };

// These are settings categories from client-core, not input-panel routes.
static inline void MSIMEOpenDesktopSettings(MSIMEDesktopSettingsPage page,
                                           NSWorkspace *workspace,
                                           dispatch_block_t fallback) {
    NSURL *url = [workspace URLForApplicationWithBundleIdentifier:@"app.msime.client.preview"];
    if (!url) {
        fallback();
        return;
    }
    NSWorkspaceOpenConfiguration *configuration = [NSWorkspaceOpenConfiguration configuration];
    configuration.arguments = @[(page == MSIMEDesktopSettingsPage::Voice
        ? @"--route=settings:voice" : @"--route=settings:appearance")];
    // Launch Services ignores arguments when reusing a running application.
    // macOS currently has no Tauri single-instance route forwarding plugin.
    configuration.createsNewApplicationInstance = YES;
    [workspace openApplicationAtURL:url configuration:configuration
                 completionHandler:^(NSRunningApplication *application, NSError *error) {
        if (error || !application) {
            dispatch_async(dispatch_get_main_queue(), fallback);
        }
    }];
}
