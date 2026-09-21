// Switching to Japanese has to leave a way back to the Chinese scheme the user was on.
//
// The scheme the user returns to is carried in `last_chinese_scheme`, which every other host writes
// when the scheme changes. This window sets the scheme itself, Japanese included, so it has to write
// it too - otherwise the way back points at whatever a different surface last recorded, and a 五笔
// user comes back to 全拼.
#import "../../src/settings/AppearancePreferences.h"
#import <Foundation/Foundation.h>
#include <cassert>

int main(void)
{
    @autoreleasepool {
        NSString *suite = [@"MSIME.SchemeRoundTripTest." stringByAppendingString:NSUUID.UUID.UUIDString];
        NSUserDefaults *defaults = [[NSUserDefaults alloc] initWithSuiteName:suite];
        MSIMEAppearancePreferences *preferences = [[MSIMEAppearancePreferences alloc] initWithDefaults:defaults];

        preferences.inputScheme = @"wubi";
        NSDictionary *merged = [preferences sharedPreferencesByMerging:@{}];
        assert([merged[@"scheme"] isEqual:@"wubi"]);
        assert([merged[@"last_chinese_scheme"] isEqual:@"wubi"]);

        // Japanese is not a Chinese scheme, so it must not overwrite the way back. The value in the
        // document being merged into is the one that survives.
        preferences.inputScheme = @"japanese";
        merged = [preferences sharedPreferencesByMerging:@{@"last_chinese_scheme": @"wubi"}];
        assert([merged[@"scheme"] isEqual:@"japanese"]);
        assert([merged[@"last_chinese_scheme"] isEqual:@"wubi"]);

        // Coming back records the scheme that was returned to, so the next excursion goes back there.
        preferences.inputScheme = @"shuangpin";
        merged = [preferences sharedPreferencesByMerging:@{@"last_chinese_scheme": @"wubi"}];
        assert([merged[@"scheme"] isEqual:@"shuangpin"]);
        assert([merged[@"last_chinese_scheme"] isEqual:@"shuangpin"]);

        preferences.inputScheme = @"quanpin";
        merged = [preferences sharedPreferencesByMerging:@{}];
        assert([merged[@"last_chinese_scheme"] isEqual:@"quanpin"]);

        [defaults removePersistentDomainForName:suite];
    }
    return 0;
}
