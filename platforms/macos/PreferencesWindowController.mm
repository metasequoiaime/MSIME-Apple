#import "PreferencesWindowController.h"
#import "AppearancePreferences.h"

static NSString *const MSIMESchemeKey = @"MetasequoiaImeScheme";
static NSString *const MSIMEShuangpinSchemaKey = @"MetasequoiaImeShuangpinSchema";

@implementation MSIMEPreferencesWindowController
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
- (NSDictionary<NSString *, id> *)cloudSettingsSnapshot { return @{ @"candidate_skin": [[NSUserDefaults standardUserDefaults] objectForKey:@"MSIMEClientCandidateSkin"] ?: @"default", @"candidate_layout": [[NSUserDefaults standardUserDefaults] objectForKey:@"MSIMEClientCandidatePanelStyle"] ?: @"vertical", @"candidate_font_size": @([[NSUserDefaults standardUserDefaults] integerForKey:@"MSIMEClientCandidateFontSize"] ?: 18), @"candidate_page_size": @([[NSUserDefaults standardUserDefaults] integerForKey:@"MSIMEClientCandidatePageSize"] ?: 5) }; }
- (BOOL)validateCloudSettingsSnapshot:(NSDictionary<NSString *,id> *)values { return [values isKindOfClass:NSDictionary.class] && [values[@"candidate_layout"] isKindOfClass:NSString.class] && [values[@"candidate_font_size"] integerValue] >= 8 && [values[@"candidate_font_size"] integerValue] <= 72 && [values[@"candidate_page_size"] integerValue] >= 1 && [values[@"candidate_page_size"] integerValue] <= 20; }
- (BOOL)applyCloudSettingsSnapshot:(NSDictionary<NSString *,id> *)values { if (![self validateCloudSettingsSnapshot:values]) return NO; NSUserDefaults *d = NSUserDefaults.standardUserDefaults; [d setObject:values[@"candidate_layout"] forKey:@"MSIMEClientCandidatePanelStyle"]; [d setInteger:[values[@"candidate_font_size"] integerValue] forKey:@"MSIMEClientCandidateFontSize"]; [d setInteger:[values[@"candidate_page_size"] integerValue] forKey:@"MSIMEClientCandidatePageSize"]; [d synchronize]; [[NSNotificationCenter defaultCenter] postNotificationName:MSIMEAppearanceDidChangeNotification object:nil]; return YES; }
@end
