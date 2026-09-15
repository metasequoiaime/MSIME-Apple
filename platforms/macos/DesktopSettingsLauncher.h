#pragma once

#import <AppKit/AppKit.h>
#import "RuntimeOptions.h"

enum class MSIMEDesktopSettingsPage { Appearance, Voice, Translation, AI, Skin };

static inline void MSIMEOpenDesktopRouteWithContext(NSString *route, NSString *optionsPath,
    NSDictionary<NSString *, NSString *> *environment, NSWorkspace *workspace,
    void (^launched)(NSRunningApplication *), dispatch_block_t fallback) {
    if (optionsPath && !optionsPath.isAbsolutePath) { fallback(); return; }
    NSURL *url = [workspace URLForApplicationWithBundleIdentifier:@"app.msime.client.preview"];
    if (!url) { fallback(); return; }
    NSWorkspaceOpenConfiguration *configuration = [NSWorkspaceOpenConfiguration configuration];
    configuration.arguments = @[[NSString stringWithFormat:@"--route=%@", route]];
    // The shared keyboard must leave the editor foreground, just like the
    // native nonactivating NSPanel. Settings pages still activate normally.
    configuration.activates = ![route isEqualToString:@"keyboard"];
    // LaunchServices does not reliably inherit the input method's environment.
    // Pass the selected file path and optional native session identity, never
    // file contents, credentials, or text being composed.
    NSMutableDictionary *launchEnvironment = [NSMutableDictionary dictionaryWithDictionary:environment ?: @{}];
    if (optionsPath) launchEnvironment[@"MSIME_CLIENT_HOST_OPTIONS"] = optionsPath;
    if (launchEnvironment.count) configuration.environment = launchEnvironment;
    configuration.createsNewApplicationInstance = YES;
    [workspace openApplicationAtURL:url configuration:configuration
                 completionHandler:^(NSRunningApplication *application, NSError *error) {
        if (error || !application) dispatch_async(dispatch_get_main_queue(), fallback);
        else if (launched) dispatch_async(dispatch_get_main_queue(), ^{ launched(application); });
    }];
}

static inline void MSIMEOpenDesktopRouteWithOptions(NSString *route, NSString *optionsPath,
                                                   NSWorkspace *workspace, dispatch_block_t fallback) {
    MSIMEOpenDesktopRouteWithContext(route, optionsPath, nil, workspace, nil, fallback);
}

static inline void MSIMEOpenDesktopRoute(NSString *route, NSWorkspace *workspace,
                                        dispatch_block_t fallback) {
    MSIMEOpenDesktopRouteWithOptions(route, MSIMERuntimeOptionsPath(), workspace, fallback);
}

// The update entry is a shared About page on desktop. Native Sparkle remains
// the platform fallback when the Tauri shell is not installed or cannot launch.
static inline void MSIMEOpenDesktopUpdateSettings(NSWorkspace *workspace,
                                                  dispatch_block_t fallback) {
    MSIMEOpenDesktopRoute(@"settings:about", workspace, fallback);
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
        case MSIMEDesktopSettingsPage::Skin: route = @"settings:skin"; break;
    }
    MSIMEOpenDesktopRoute(route, workspace, fallback);
}
