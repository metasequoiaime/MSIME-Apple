#import "../AppearancePreferences.h"
#include <cassert>

int main() {
    @autoreleasepool {
        NSString *suite = [@"MSIME.ToolbarVisibilityTest." stringByAppendingString:NSUUID.UUID.UUIDString];
        NSUserDefaults *defaults = [[NSUserDefaults alloc] initWithSuiteName:suite];
        MSIMEAppearancePreferences *preferences = [[MSIMEAppearancePreferences alloc] initWithDefaults:defaults];
        __block NSUInteger notifications = 0;
        id token = [NSNotificationCenter.defaultCenter addObserverForName:MSIMEAppearanceDidChangeNotification object:preferences queue:nil usingBlock:^(NSNotification *note) { (void)note; ++notifications; }];
        assert(preferences.floatingToolbarEnabled);
        [preferences applySharedToolbarVisibility:NO];
        assert(!preferences.floatingToolbarEnabled && notifications == 0);
        assert([defaults objectForKey:@"MSIMEClientFloatingToolbarEnabled"] == nil);
        NSDictionary *merged = [preferences sharedPreferencesByMerging:@{}];
        assert(![merged[@"floating_toolbar"][@"enabled"] boolValue]);
        [preferences applySharedToolbarVisibility:YES];
        assert(preferences.floatingToolbarEnabled && notifications == 0);
        preferences.floatingToolbarEnabled = NO;
        assert(!preferences.floatingToolbarEnabled && notifications == 1);
        [preferences applySharedToolbarVisibility:YES];
        assert(preferences.floatingToolbarEnabled && notifications == 1);
        [NSNotificationCenter.defaultCenter removeObserver:token];
        [defaults removePersistentDomainForName:suite];
    }
}
