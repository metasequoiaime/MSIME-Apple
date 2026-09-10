#import "ChineseTextConversion.h"

BOOL MSIMEScriptConversionApplies(NSDictionary *context) {
    if (![context isKindOfClass:NSDictionary.class]) return NO;
    NSNumber *scheme = context[@"scheme"];
    NSString *mode = context[@"local_mode"];
    // Unknown/old hosts fail closed; Unicode means an exact code point, not a Chinese word.
    return [scheme isKindOfClass:NSNumber.class] && scheme.integerValue >= 0 && scheme.integerValue <= 2 &&
           [mode isKindOfClass:NSString.class] && mode.length && ![mode isEqual:@"unicode"] && ![mode isEqual:@"unknown"];
}

NSString *MSIMEChineseOutputString(NSString *text, BOOL traditionalOutput) {
    if (!traditionalOutput || text.length == 0) return text;
    NSMutableString *converted = [text mutableCopy];
    if (!CFStringTransform((__bridge CFMutableStringRef)converted, nullptr, CFSTR("Simplified-Traditional"), false)) return text;
    return [converted copy];
}
