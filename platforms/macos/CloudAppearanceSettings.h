#pragma once
#import <Foundation/Foundation.h>
#include "CandidateSkin.h"

static inline BOOL MSIMECloudAppearanceIntegerInRange(id value, NSInteger minimum, NSInteger maximum) {
    return [value isKindOfClass:NSNumber.class] && CFGetTypeID((__bridge CFTypeRef)value) != CFBooleanGetTypeID() &&
           [value doubleValue] == [value integerValue] && [value integerValue] >= minimum && [value integerValue] <= maximum;
}

// Cloud names follow MSIME-Apple develop 2b0250f4dd7012520392b310dfcc0288c3208a75.
// Defaults and storage keys follow the active client host, not the retained Apple host.
static inline NSDictionary *MSIMECloudBooleanPreferences() {
    return @{@"autocorrect": @[@"MSIMEClientAutocorrect", @YES],
             @"helpcode": @[@"MSIMEClientHelpcodeEnabled", @YES],
             @"chinese_punctuation": @[@"MSIMEClientChinesePunctuation", @YES],
             @"english_input_mode": @[@"MSIMEClientEnglishInputMode", @NO],
             @"input_mode_shortcut": @[@"MSIMEClientInputModeShortcut", @YES],
             @"full_width_input": @[@"MSIMEClientFullWidthInput", @NO],
             @"floating_toolbar": @[@"MSIMEClientFloatingToolbarEnabled", @YES],
             @"traditional_chinese_output": @[@"MSIMEClientTraditionalOutput", @NO],
             @"wubi_auto_commit_unique": @[@"MSIMEClientWubiAutoCommitUnique", @NO],
             @"shuangpin_keymap": @[@"MSIMEClientShuangpinKeymap", @NO],
             @"shuangpin_preedit_uses_raw": @[@"MSIMEClientShuangpinPreeditUsesRaw", @YES]};
}

static inline NSDictionary *MSIMECloudAppearanceSnapshot(NSUserDefaults *defaults) {
    id font = [defaults objectForKey:@"MSIMEClientCandidateFontSize"];
    id page = [defaults objectForKey:@"MSIMEClientCandidatePageSize"];
    NSString *skin = [defaults stringForKey:@"MSIMEClientCandidateSkin"];
    NSMutableDictionary *snapshot = [@{@"platform.macos.candidate_skin": @(msime::mac::NormalizeSkinId(skin.UTF8String ?: "").c_str()),
             @"platform.macos.candidate_panel_style": @([defaults integerForKey:@"MSIMEClientCandidatePanelStyle"] == 1 ? 1 : 0),
             @"platform.macos.candidate_font_size": MSIMECloudAppearanceIntegerInRange(font, 12, 32) ? font : @18,
             @"platform.macos.candidate_page_size": MSIMECloudAppearanceIntegerInRange(page, 1, 9) ? page : @9} mutableCopy];
    NSInteger shortcut = [defaults integerForKey:@"MSIMEClientCandidatePageShortcut"];
    snapshot[@"platform.macos.candidate_page_shortcut"] = @(shortcut == 1 || shortcut == 2 ? shortcut : 0);
    NSArray *schemes = @[@"quanpin", @"shuangpin", @"wubi"];
    NSUInteger scheme = [schemes indexOfObject:[defaults stringForKey:@"MSIMEClientInputScheme"] ?: @""];
    snapshot[@"platform.macos.input_scheme"] = @(scheme == NSNotFound ? 0 : scheme);
    NSDictionary *booleans = MSIMECloudBooleanPreferences();
    for (NSString *key in booleans) {
        NSArray *field = booleans[key];
        snapshot[[@"platform.macos." stringByAppendingString:key]] =
            [defaults objectForKey:field[0]] == nil ? field[1] : @([defaults boolForKey:field[0]]);
    }
    return snapshot;
}

static inline BOOL MSIMEValidateCloudAppearance(NSDictionary *values) {
    if (![values isKindOfClass:NSDictionary.class] || values.count != 6 + MSIMECloudBooleanPreferences().count) return NO;
    id skin = values[@"platform.macos.candidate_skin"];
    if (![skin isKindOfClass:NSString.class] || ![skin length] || [skin length] > 64) return NO;
    NSString *normalized = @(msime::mac::NormalizeSkinId([skin UTF8String]).c_str());
    if (![skin isEqual:normalized]) return NO;
    if (!MSIMECloudAppearanceIntegerInRange(values[@"platform.macos.candidate_font_size"], 12, 32) ||
        !MSIMECloudAppearanceIntegerInRange(values[@"platform.macos.candidate_page_size"], 1, 9)) return NO;
    NSDictionary *options = @{@"platform.macos.candidate_panel_style": @[@0,@1],
                              @"platform.macos.input_scheme": @[@0,@1,@2],
                              @"platform.macos.candidate_page_shortcut": @[@0,@1,@2]};
    for (NSString *key in options) {
        id value = values[key];
        if (![value isKindOfClass:NSNumber.class] || CFGetTypeID((__bridge CFTypeRef)value) == CFBooleanGetTypeID() ||
            ![options[key] containsObject:value]) return NO;
    }
    for (NSString *key in MSIMECloudBooleanPreferences()) {
        id value = values[[@"platform.macos." stringByAppendingString:key]];
        if (![value isKindOfClass:NSNumber.class] || CFGetTypeID((__bridge CFTypeRef)value) != CFBooleanGetTypeID()) return NO;
    }
    return YES;
}

static inline BOOL MSIMEApplyCloudAppearance(NSDictionary *values, NSUserDefaults *defaults) {
    if (!MSIMEValidateCloudAppearance(values)) return NO;
    [defaults setObject:values[@"platform.macos.candidate_skin"] forKey:@"MSIMEClientCandidateSkin"];
    [defaults setObject:values[@"platform.macos.candidate_panel_style"] forKey:@"MSIMEClientCandidatePanelStyle"];
    [defaults setObject:values[@"platform.macos.candidate_font_size"] forKey:@"MSIMEClientCandidateFontSize"];
    [defaults setObject:values[@"platform.macos.candidate_page_size"] forKey:@"MSIMEClientCandidatePageSize"];
    [defaults setObject:values[@"platform.macos.candidate_page_shortcut"] forKey:@"MSIMEClientCandidatePageShortcut"];
    [defaults setObject:@[@"quanpin", @"shuangpin", @"wubi"][[values[@"platform.macos.input_scheme"] unsignedIntegerValue]] forKey:@"MSIMEClientInputScheme"];
    NSDictionary *booleans = MSIMECloudBooleanPreferences();
    for (NSString *key in booleans) {
        [defaults setObject:values[[@"platform.macos." stringByAppendingString:key]] forKey:booleans[key][0]];
    }
    return YES;
}
