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
    assert(initial.count == 17);
    assert([initial[@"platform.macos.shuangpin_preedit_uses_raw"] isEqual:@YES]);
    for (NSString *key in @[@"autocorrect", @"helpcode", @"chinese_punctuation", @"input_mode_shortcut", @"floating_toolbar"])
      assert([initial[[@"platform.macos." stringByAppendingString:key]] isEqual:@YES]);
    for (NSString *key in @[@"english_input_mode", @"full_width_input", @"traditional_chinese_output", @"wubi_auto_commit_unique", @"shuangpin_keymap"])
      assert([initial[[@"platform.macos." stringByAppendingString:key]] isEqual:@NO]);
    NSMutableDictionary *values = [initial mutableCopy];
    values[@"platform.macos.candidate_panel_style"] = @1;
    values[@"platform.macos.candidate_font_size"] = @20;
    values[@"platform.macos.candidate_page_size"] = @7;
    values[@"platform.macos.input_scheme"] = @2;
    values[@"platform.macos.candidate_page_shortcut"] = @1;
    for (NSString *key in MSIMECloudBooleanPreferences()) {
      NSString *cloudKey = [@"platform.macos." stringByAppendingString:key];
      values[cloudKey] = @(![initial[cloudKey] boolValue]);
    }
    assert(MSIMEApplyCloudAppearance(values, defaults));
    assert([MSIMECloudAppearanceSnapshot(defaults) isEqual:values]);
    assert([[defaults stringForKey:@"MSIMEClientInputScheme"] isEqual:@"wubi"]);
    assert([defaults integerForKey:@"MSIMEClientCandidatePageShortcut"] == 1);
    assert([defaults boolForKey:@"MSIMEClientFullWidthInput"]);
    assert(![defaults boolForKey:@"MSIMEClientChinesePunctuation"]);
    NSDictionary *saved = [values copy];
    // Every size offered by the active native UI survives cloud export/import.
    for (NSInteger font = 12; font <= 32; ++font) {
      for (NSInteger page = 1; page <= 9; ++page) {
        [defaults setInteger:font forKey:@"MSIMEClientCandidateFontSize"];
        [defaults setInteger:page forKey:@"MSIMEClientCandidatePageSize"];
        NSDictionary *snapshot = MSIMECloudAppearanceSnapshot(defaults);
        assert([snapshot[@"platform.macos.candidate_font_size"] integerValue] == font);
        assert([snapshot[@"platform.macos.candidate_page_size"] integerValue] == page);
        [defaults setInteger:18 forKey:@"MSIMEClientCandidateFontSize"];
        [defaults setInteger:9 forKey:@"MSIMEClientCandidatePageSize"];
        assert(MSIMEApplyCloudAppearance(snapshot, defaults));
        assert([MSIMECloudAppearanceSnapshot(defaults) isEqual:snapshot]);
      }
    }
    assert(MSIMEApplyCloudAppearance(saved, defaults));
    for (NSString *key in MSIMECloudBooleanPreferences()) {
      for (id invalid in @[@1, @"true", NSNull.null]) {
        NSMutableDictionary *bad = [saved mutableCopy];
        bad[[@"platform.macos." stringByAppendingString:key]] = invalid;
        assert(!MSIMEApplyCloudAppearance(bad, defaults));
        assert([MSIMECloudAppearanceSnapshot(defaults) isEqual:saved]);
      }
    }
    for (NSString *key in @[@"platform.macos.input_scheme", @"platform.macos.candidate_page_shortcut"]) {
      for (id invalid in @[@YES, @3, @(-1), @1.5, @"1"]) {
        NSMutableDictionary *bad = [saved mutableCopy]; bad[key] = invalid;
        assert(!MSIMEApplyCloudAppearance(bad, defaults));
        assert([MSIMECloudAppearanceSnapshot(defaults) isEqual:saved]);
      }
    }
    for (id invalid in @[@YES, @11, @33, @18.5, @"18", NSNull.null]) {
      values[@"platform.macos.candidate_font_size"] = invalid;
      assert(!MSIMEApplyCloudAppearance(values, defaults));
      assert([MSIMECloudAppearanceSnapshot(defaults) isEqual:saved]);
    }
    for (id invalid in @[@YES, @0, @10, @1.5, @"5", NSNull.null]) {
      values = [saved mutableCopy];
      values[@"platform.macos.candidate_page_size"] = invalid;
      assert(!MSIMEApplyCloudAppearance(values, defaults));
      assert([MSIMECloudAppearanceSnapshot(defaults) isEqual:saved]);
    }
    for (id invalid in @[@YES, @0, @99, @12.5, @"12"]) {
      [defaults setObject:invalid forKey:@"MSIMEClientCandidateFontSize"];
      [defaults setObject:invalid forKey:@"MSIMEClientCandidatePageSize"];
      NSDictionary *snapshot = MSIMECloudAppearanceSnapshot(defaults);
      assert([snapshot[@"platform.macos.candidate_font_size"] isEqual:@18]);
      assert([snapshot[@"platform.macos.candidate_page_size"] isEqual:@9]);
      assert(MSIMEValidateCloudAppearance(snapshot));
    }
    assert(MSIMEApplyCloudAppearance(saved, defaults));
    values = [saved mutableCopy]; values[@"platform.macos.candidate_skin"] = @"../unsafe";
    assert(!MSIMEApplyCloudAppearance(values, defaults));
    values = [saved mutableCopy]; values[@"unexpected"] = @1;
    assert(!MSIMEApplyCloudAppearance(values, defaults));
    [defaults removePersistentDomainForName:suite];
  }
}
