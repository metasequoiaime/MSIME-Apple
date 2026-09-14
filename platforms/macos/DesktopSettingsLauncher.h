#pragma once

#import <AppKit/AppKit.h>
#import "RuntimeOptions.h"

enum class MSIMEDesktopSettingsPage { Appearance, Voice, Translation, AI };

static inline void MSIMEOpenDesktopRouteWithOptions(NSString *route, NSString *optionsPath,
                                                   NSWorkspace *workspace, dispatch_block_t fallback) {
    if (optionsPath && !optionsPath.isAbsolutePath) { fallback(); return; }
    NSURL *url = [workspace URLForApplicationWithBundleIdentifier:@"app.msime.client.preview"];
    if (!url) { fallback(); return; }
    NSWorkspaceOpenConfiguration *configuration = [NSWorkspaceOpenConfiguration configuration];
    configuration.arguments = @[[NSString stringWithFormat:@"--route=%@", route]];
    // The shared keyboard must leave the editor foreground, just like the
    // native nonactivating NSPanel. Settings pages still activate normally.
    configuration.activates = ![route isEqualToString:@"keyboard"];
    // LaunchServices does not reliably inherit the input method's environment.
    // Pass only the selected file path, never its credentials or input state.
    if (optionsPath) configuration.environment = @{@"MSIME_CLIENT_HOST_OPTIONS":optionsPath};
    configuration.createsNewApplicationInstance = YES;
    [workspace openApplicationAtURL:url configuration:configuration
                 completionHandler:^(NSRunningApplication *application, NSError *error) {
        if (error || !application) dispatch_async(dispatch_get_main_queue(), fallback);
    }];
}

static inline void MSIMEOpenDesktopRoute(NSString *route, NSWorkspace *workspace,
                                        dispatch_block_t fallback) {
    MSIMEOpenDesktopRouteWithOptions(route, MSIMERuntimeOptionsPath(), workspace, fallback);
}

// These are settings categories from client-core, not input-panel routes.
static inline void MSIMEOpenDesktopSettings(MSIMEDesktopSettingsPage page,
                                           NSWorkspace *workspace,
                                           dispatch_block_t fallback) {
    NSString *route = @"settings:appearance";
    switch (page) {
        case MSIMEDesktopSettingsPage::Appearance: break;
        case MSIMEDesktopSettingsPage::Voice: route = @"settings:voice"; break;
        // Translation controls live in the shared Input category.
        case MSIMEDesktopSettingsPage::Translation: route = @"settings:input"; break;
        case MSIMEDesktopSettingsPage::AI: route = @"settings:ai"; break;
    }
    MSIMEOpenDesktopRoute(route, workspace, fallback);
}
