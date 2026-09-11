#pragma once
#import <Foundation/Foundation.h>
#include "CandidateSkin.h"

static inline NSDictionary *MSIMECloudAppearanceSnapshot(NSUserDefaults *defaults) {
    NSInteger font = [defaults integerForKey:@"MSIMEClientCandidateFontSize"];
    NSInteger page = [defaults integerForKey:@"MSIMEClientCandidatePageSize"];
    NSString *skin = [defaults stringForKey:@"MSIMEClientCandidateSkin"];
    return @{@"platform.macos.candidate_skin": @(msime::mac::NormalizeSkinId(skin.UTF8String ?: "").c_str()),
             @"platform.macos.candidate_panel_style": @([defaults integerForKey:@"MSIMEClientCandidatePanelStyle"] == 1 ? 1 : 0),
             @"platform.macos.candidate_font_size": @(font == 16 || font == 20 ? font : 18),
             @"platform.macos.candidate_page_size": @(page == 5 || page == 7 ? page : 9)};
}

static inline BOOL MSIMEValidateCloudAppearance(NSDictionary *values) {
    if (![values isKindOfClass:NSDictionary.class] || values.count != 4) return NO;
    id skin = values[@"platform.macos.candidate_skin"];
    if (![skin isKindOfClass:NSString.class] || ![skin length] || [skin length] > 64) return NO;
    NSString *normalized = @(msime::mac::NormalizeSkinId([skin UTF8String]).c_str());
    if (![skin isEqual:normalized]) return NO;
    NSDictionary *options = @{@"platform.macos.candidate_panel_style": @[@0,@1],
                              @"platform.macos.candidate_font_size": @[@16,@18,@20],
                              @"platform.macos.candidate_page_size": @[@5,@7,@9]};
    for (NSString *key in options) {
        id value = values[key];
        if (![value isKindOfClass:NSNumber.class] || CFGetTypeID((__bridge CFTypeRef)value) == CFBooleanGetTypeID() ||
            ![options[key] containsObject:value]) return NO;
    }
    return YES;
}

static inline BOOL MSIMEApplyCloudAppearance(NSDictionary *values, NSUserDefaults *defaults) {
    if (!MSIMEValidateCloudAppearance(values)) return NO;
    [defaults setObject:values[@"platform.macos.candidate_skin"] forKey:@"MSIMEClientCandidateSkin"];
    [defaults setObject:values[@"platform.macos.candidate_panel_style"] forKey:@"MSIMEClientCandidatePanelStyle"];
    [defaults setObject:values[@"platform.macos.candidate_font_size"] forKey:@"MSIMEClientCandidateFontSize"];
    [defaults setObject:values[@"platform.macos.candidate_page_size"] forKey:@"MSIMEClientCandidatePageSize"];
    return YES;
}
