#pragma once
#import <AppKit/AppKit.h>

FOUNDATION_EXPORT NSNotificationName const MSIMEStandalonePreferencesDidCloseNotification;

/// Native preferences entry point; pages are added incrementally to this controller.
@interface MSIMEPreferencesWindowController : NSWindowController <NSWindowDelegate>
+ (instancetype)sharedController;
+ (NSString *)storedCandidateSkin;
+ (void)setStoredCandidateSkin:(NSString *)skinId;
- (void)showAndActivate;
- (void)showAndActivateForStandaloneLaunch;
- (NSDictionary<NSString *, id> *)cloudSettingsSnapshot;
- (BOOL)validateCloudSettingsSnapshot:(NSDictionary<NSString *, id> *)values;
- (BOOL)applyCloudSettingsSnapshot:(NSDictionary<NSString *, id> *)values;
+ (NSDictionary<NSString *, id> *)cloudSettingsSnapshot;
+ (NSNumber *)validateCloudSettingsSnapshot:(NSDictionary<NSString *, id> *)values;
+ (NSNumber *)applyCloudSettingsSnapshot:(NSDictionary<NSString *, id> *)values;
@end
#define MetasequoiaPreferencesWindowController MSIMEPreferencesWindowController
