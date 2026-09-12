#import "PreferencesWindowController.h"
#import "AppearancePreferences.h"
#import "CandidateSkinAppearance.h"
#import "CloudAppearanceSettings.h"

static NSString *const MSIMESchemeKey = @"MetasequoiaImeScheme";
static NSString *const MSIMEShuangpinSchemaKey = @"MetasequoiaImeShuangpinSchema";

@implementation MSIMEPreferencesWindowController
+ (NSDictionary *)cloudSettingsSnapshot { return MSIMECloudAppearanceSnapshot(NSUserDefaults.standardUserDefaults); }
+ (NSNumber *)validateCloudSettingsSnapshot:(NSDictionary *)values { return @(MSIMEValidateCloudAppearance(values)); }
+ (NSNumber *)applyCloudSettingsSnapshot:(NSDictionary *)values {
    if (!MSIMEApplyCloudAppearance(values, NSUserDefaults.standardUserDefaults)) return @NO;
    [[MSIMEAppearancePreferences sharedPreferences] reloadSkins];
    [[NSNotificationCenter defaultCenter] postNotificationName:MSIMEAppearanceDidChangeNotification object:nil];
    return @YES;
}
+ (NSString *)storedCandidateSkin { return MetasequoiaStoredCandidateSkin(); }
+ (void)setStoredCandidateSkin:(NSString *)skinId { MetasequoiaSetStoredCandidateSkin(skinId); }
+ (instancetype)sharedController {
    static MSIMEPreferencesWindowController *controller;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ controller = [[self alloc] initWithWindow:nil]; });
    return controller;
}
- (void)showAndActivate {
    [[MSIMEAppearancePreferences sharedPreferences] showWindow:nil];
    [NSApp activateIgnoringOtherApps:YES];
}
- (NSDictionary *)cloudSettingsSnapshot { return [self.class cloudSettingsSnapshot]; }
- (BOOL)validateCloudSettingsSnapshot:(NSDictionary *)values { return [[self.class validateCloudSettingsSnapshot:values] boolValue]; }
- (BOOL)applyCloudSettingsSnapshot:(NSDictionary *)values { return [[self.class applyCloudSettingsSnapshot:values] boolValue]; }
@end
