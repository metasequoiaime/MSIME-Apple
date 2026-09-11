#import "../CloudAppearanceSettings.h"
#include <cassert>
int main() {
  @autoreleasepool {
    NSString *suite = [@"msime.synthetic." stringByAppendingString:NSUUID.UUID.UUIDString];
    NSUserDefaults *defaults = [[NSUserDefaults alloc] initWithSuiteName:suite];
    NSDictionary *initial = MSIMECloudAppearanceSnapshot(defaults);
    assert([initial[@"platform.macos.candidate_font_size"] isEqual:@18]);
    assert([initial[@"platform.macos.candidate_page_size"] isEqual:@9]);
    assert([initial[@"platform.macos.candidate_panel_style"] isEqual:@0]);
    assert(MSIMEValidateCloudAppearance(initial));
    NSMutableDictionary *values = [initial mutableCopy];
    values[@"platform.macos.candidate_panel_style"] = @1;
    values[@"platform.macos.candidate_font_size"] = @20;
    values[@"platform.macos.candidate_page_size"] = @7;
    assert(MSIMEApplyCloudAppearance(values, defaults));
    assert([MSIMECloudAppearanceSnapshot(defaults) isEqual:values]);
    NSDictionary *saved = [values copy];
    for (id invalid in @[@YES, @19, @18.5, @"18", NSNull.null]) {
      values[@"platform.macos.candidate_font_size"] = invalid;
      assert(!MSIMEApplyCloudAppearance(values, defaults));
      assert([MSIMECloudAppearanceSnapshot(defaults) isEqual:saved]);
    }
    values = [saved mutableCopy]; values[@"platform.macos.candidate_skin"] = @"../unsafe";
    assert(!MSIMEApplyCloudAppearance(values, defaults));
    values = [saved mutableCopy]; values[@"unexpected"] = @1;
    assert(!MSIMEApplyCloudAppearance(values, defaults));
    [defaults removePersistentDomainForName:suite];
  }
}
